<?php

namespace App\Services;

use App\Models\Ticket;
use App\Models\TicketMedia;
use App\Models\User;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class TelegramTicketService
{
    public function enabled(): bool
    {
        return (bool) config('telegram_ticket.enabled')
            && (string) config('telegram_ticket.bot_token') !== ''
            && (string) config('telegram_ticket.chat_id') !== '';
    }

    public function notifyTicket(Ticket $ticket, string $event, ?string $message = null): void
    {
        if (!$this->enabled()) {
            return;
        }

        try {
            $ticket->loadMissing('user');
            $title = $event === 'created' ? '🆕 新工单' : '💬 用户回复';
            $levelMap = ['0' => '低', '1' => '中', '2' => '高'];
            $level = $levelMap[(string) $ticket->level] ?? (string) $ticket->level;
            $mediaIds = $this->mediaIds((string) $message);
            $cleanMessage = preg_replace('/\s*\[\[ticket-media:[0-9a-f-]{36}:[a-z]+\]\]/i', '', (string) $message);
            $body = $this->escape($this->truncate(trim((string) $cleanMessage), 3000));
            $text = implode("\n", [
                "<b>{$title} #{$ticket->id}</b>",
                '<b>主题：</b>' . $this->escape((string) $ticket->subject),
                '<b>优先级：</b>' . $this->escape($level),
                '<b>用户：</b>' . $this->escape((string) ($ticket->user->email ?? ('ID ' . $ticket->user_id))),
                '',
                $body,
                '',
                '直接回复本消息，即可回复网站工单。',
            ]);

            $keyboard = [[
                ['text' => '✅ 关闭工单', 'callback_data' => 'ticket_close:' . $ticket->id],
            ]];
            $adminUrl = trim((string) config('telegram_ticket.admin_url'));
            if ($adminUrl !== '') {
                $keyboard[0][] = ['text' => '🖥 打开后台', 'url' => $adminUrl];
            }

            $this->api('sendMessage', [
                'chat_id' => (string) config('telegram_ticket.chat_id'),
                'text' => $text,
                'parse_mode' => 'HTML',
                'disable_web_page_preview' => true,
                'reply_markup' => ['inline_keyboard' => $keyboard],
            ]);
            foreach (TicketMedia::whereIn('id', $mediaIds)->get() as $media) {
                $this->sendStoredMedia($media, $ticket->id);
            }
        } catch (\Throwable $e) {
            Log::warning('Telegram ticket notification failed', [
                'ticket_id' => $ticket->id,
                'error' => $e->getMessage(),
            ]);
        }
    }

    public function sendText(string $text, ?array $replyMarkup = null): void
    {
        if (!$this->enabled()) {
            return;
        }
        $payload = [
            'chat_id' => (string) config('telegram_ticket.chat_id'),
            'text' => $this->truncate($text, 3900),
            'parse_mode' => 'HTML',
            'disable_web_page_preview' => true,
        ];
        if ($replyMarkup !== null) {
            $payload['reply_markup'] = $replyMarkup;
        }
        $this->api('sendMessage', $payload);
    }

    public function answerCallback(string $callbackId, string $text): void
    {
        $this->api('answerCallbackQuery', [
            'callback_query_id' => $callbackId,
            'text' => $text,
        ]);
    }

    public function resolveAdminUserId(): ?int
    {
        $configured = (int) config('telegram_ticket.xboard_admin_user_id');
        if ($configured > 0) {
            return $configured;
        }
        $id = User::query()
            ->where(function ($query) {
                $query->where('is_admin', 1)->orWhere('is_staff', 1);
            })
            ->orderBy('id')
            ->value('id');
        return $id ? (int) $id : null;
    }

    public function isAllowed(array $update): bool
    {
        $message = $update['message'] ?? null;
        $callback = $update['callback_query'] ?? null;
        $chatId = (string) ($message['chat']['id'] ?? $callback['message']['chat']['id'] ?? '');
        $fromId = (string) ($message['from']['id'] ?? $callback['from']['id'] ?? '');
        if ($chatId === '' || !hash_equals((string) config('telegram_ticket.chat_id'), $chatId)) {
            return false;
        }
        $allowed = array_values(array_filter(array_map('trim', explode(',', (string) config('telegram_ticket.allowed_user_ids')))));
        return $allowed === [] || in_array($fromId, $allowed, true);
    }

    public function importTelegramMedia(array $message, Ticket $ticket): ?TicketMedia
    {
        $source = null;
        $kind = null;
        $mime = null;
        $name = null;
        if (!empty($message['photo']) && is_array($message['photo'])) {
            $photos = $message['photo'];
            $source = end($photos);
            $kind = 'image';
            $mime = 'image/jpeg';
            $name = 'telegram-photo.jpg';
        } elseif (!empty($message['video'])) {
            $source = $message['video'];
            $kind = 'video';
            $mime = strtolower((string) ($source['mime_type'] ?? 'video/mp4'));
            $name = (string) ($source['file_name'] ?? 'telegram-video.mp4');
        } elseif (!empty($message['animation'])) {
            $source = $message['animation'];
            $kind = 'sticker';
            $mime = strtolower((string) ($source['mime_type'] ?? 'video/mp4'));
            $name = (string) ($source['file_name'] ?? 'telegram-animation.mp4');
        } elseif (!empty($message['sticker'])) {
            $source = $message['sticker'];
            $kind = 'sticker';
            if (!empty($source['is_video'])) {
                $mime = 'video/webm';
                $name = 'telegram-sticker.webm';
            } elseif (!empty($source['is_animated'])) {
                throw new \RuntimeException('暂不支持 Telegram 动态 TGS 贴纸，请改发图片、GIF 或视频贴纸');
            } else {
                $mime = 'image/webp';
                $name = 'telegram-sticker.webp';
            }
        }
        if (!$source || empty($source['file_id'])) {
            return null;
        }
        if ((int) ($source['file_size'] ?? 0) > 20 * 1024 * 1024) {
            throw new \RuntimeException('媒体超过 20MB，无法同步到网站工单');
        }

        $file = $this->api('getFile', ['file_id' => $source['file_id']]);
        $filePath = (string) ($file['file_path'] ?? '');
        if ($filePath === '') {
            throw new \RuntimeException('Telegram 没有返回媒体文件地址');
        }
        $token = (string) config('telegram_ticket.bot_token');
        $response = Http::connectTimeout(3)->timeout(30)->get("https://api.telegram.org/file/bot{$token}/{$filePath}");
        if (!$response->successful() || strlen($response->body()) > 20 * 1024 * 1024) {
            throw new \RuntimeException('下载 Telegram 媒体失败或文件超过 20MB');
        }
        $extension = strtolower(pathinfo($name, PATHINFO_EXTENSION));
        if ($extension === '') {
            $extension = ['image/jpeg' => 'jpg', 'image/webp' => 'webp', 'video/mp4' => 'mp4', 'video/webm' => 'webm'][$mime] ?? 'bin';
        }
        $id = (string) Str::uuid();
        $path = 'ticket-media/' . date('Y/m') . '/' . $id . '.' . preg_replace('/[^a-z0-9]/', '', $extension);
        Storage::disk('local')->put($path, $response->body());
        return TicketMedia::create([
            'id' => $id,
            'ticket_id' => $ticket->id,
            'user_id' => $ticket->user_id,
            'kind' => $kind,
            'mime' => $mime,
            'original_name' => mb_substr($name, 0, 255),
            'path' => $path,
            'size' => strlen($response->body()),
            'telegram_file_id' => (string) $source['file_id'],
        ]);
    }

    private function mediaIds(string $message): array
    {
        preg_match_all('/\[\[ticket-media:([0-9a-f-]{36}):[a-z]+\]\]/i', $message, $matches);
        return array_values(array_unique($matches[1] ?? []));
    }

    private function sendStoredMedia(TicketMedia $media, int $ticketId): void
    {
        if (!Storage::disk('local')->exists($media->path) || $media->size > 20 * 1024 * 1024) {
            return;
        }
        $method = 'sendDocument';
        $field = 'document';
        if ($media->kind === 'image') {
            $method = 'sendPhoto';
            $field = 'photo';
        } elseif ($media->kind === 'video') {
            $method = 'sendVideo';
            $field = 'video';
        } elseif ($media->kind === 'sticker' && ($media->mime === 'image/gif' || str_starts_with($media->mime, 'video/'))) {
            $method = 'sendAnimation';
            $field = 'animation';
        } elseif ($media->kind === 'sticker' && $media->mime === 'image/webp') {
            $method = 'sendSticker';
            $field = 'sticker';
        }
        $token = (string) config('telegram_ticket.bot_token');
        $contents = Storage::disk('local')->get($media->path);
        $response = Http::attach($field, $contents, $media->original_name ?: basename($media->path))
            ->connectTimeout(3)
            ->timeout(30)
            ->post("https://api.telegram.org/bot{$token}/{$method}", [
                'chat_id' => (string) config('telegram_ticket.chat_id'),
                'caption' => $field === 'sticker' ? null : '工单 #' . $ticketId,
            ]);
        if (!$response->successful() || !$response->json('ok')) {
            throw new \RuntimeException('Telegram 媒体发送失败: HTTP ' . $response->status());
        }
    }

    private function api(string $method, array $payload): array
    {
        $token = (string) config('telegram_ticket.bot_token');
        $response = Http::asJson()
            ->connectTimeout(2)
            ->timeout(5)
            ->retry(1, 200)
            ->post("https://api.telegram.org/bot{$token}/{$method}", $payload);
        if (!$response->successful() || !$response->json('ok')) {
            throw new \RuntimeException('Telegram API request failed: HTTP ' . $response->status());
        }
        return (array) $response->json('result', []);
    }

    private function escape(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    private function truncate(string $value, int $limit): string
    {
        return mb_strlen($value) <= $limit ? $value : mb_substr($value, 0, $limit) . "\n…（内容已截断）";
    }
}
