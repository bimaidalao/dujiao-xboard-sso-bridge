<?php

namespace App\Http\Controllers\V1\Guest;

use App\Http\Controllers\Controller;
use App\Models\Ticket;
use App\Models\TicketMessage;
use App\Services\TelegramTicketService;
use App\Services\TicketService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class TelegramTicketController extends Controller
{
    public function webhook(Request $request, TelegramTicketService $telegram)
    {
        $expected = (string) config('telegram_ticket.webhook_secret');
        $provided = (string) $request->header('X-Telegram-Bot-Api-Secret-Token', '');
        if ($expected === '' || $provided === '' || !hash_equals($expected, $provided)) {
            return response()->json(['ok' => false], 403);
        }

        $update = $request->all();
        if (!$telegram->isAllowed($update)) {
            Log::warning('Rejected Telegram ticket update', ['update_id' => $update['update_id'] ?? null]);
            return response()->json(['ok' => true]);
        }

        try {
            if (isset($update['callback_query'])) {
                $this->handleCallback($update['callback_query'], $telegram);
            } elseif (isset($update['message'])) {
                $this->handleMessage($update['message'], $telegram);
            }
        } catch (\Throwable $e) {
            Log::error('Telegram ticket webhook failed', [
                'update_id' => $update['update_id'] ?? null,
                'error' => $e->getMessage(),
            ]);
            $telegram->sendText('鉂?鎿嶄綔澶辫触锛? . htmlspecialchars($e->getMessage(), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'));
        }

        return response()->json(['ok' => true]);
    }

    private function handleMessage(array $message, TelegramTicketService $telegram): void
    {
        $text = trim((string) ($message['text'] ?? $message['caption'] ?? ''));
        if ($text === '/start' || $text === '/help') {
            $telegram->sendText("<b>璺ㄥ閫熶簯宸ュ崟鍔╂墜</b>\n\n鍥炲鏈哄櫒浜哄彂鏉ョ殑宸ュ崟閫氱煡锛屽彲鐩存帴鍥炲缃戠珯宸ュ崟銆俓n涔熷彲浣跨敤锛歕n<code>/reply 宸ュ崟ID 鍥炲鍐呭</code>\n<code>/close 宸ュ崟ID</code>\n<code>/ticket 宸ュ崟ID</code>");
            return;
        }

        if (preg_match('/^\/reply\s+(\d+)\s+([\s\S]+)$/u', $text, $match)) {
            $this->replyToTicket((int) $match[1], trim($match[2]), $telegram, $message);
            return;
        }
        if (preg_match('/^\/close\s+(\d+)$/u', $text, $match)) {
            $this->closeTicket((int) $match[1], $telegram);
            return;
        }
        if (preg_match('/^\/ticket\s+(\d+)$/u', $text, $match)) {
            $this->showTicket((int) $match[1], $telegram);
            return;
        }

        $replyText = (string) ($message['reply_to_message']['text'] ?? $message['reply_to_message']['caption'] ?? '');
        if ($replyText !== '' && preg_match('/#\s*(\d+)/u', $replyText, $match)) {
            $hasMedia = !empty($message['photo']) || !empty($message['video']) || !empty($message['animation']) || !empty($message['sticker']);
            if ($text === '' && !$hasMedia) {
                $telegram->sendText('璇疯緭鍏ユ枃瀛楋紝鎴栧彂閫佸浘鐗囥€佽创绾搞€佽棰戙€?);
                return;
            }
            $this->replyToTicket((int) $match[1], $text, $telegram, $message);
            return;
        }

        $telegram->sendText('璇风洿鎺モ€滃洖澶嶁€濇煇鏉″伐鍗曢€氱煡锛屾垨鍙戦€?<code>/help</code> 鏌ョ湅鍛戒护銆?);
    }

    private function handleCallback(array $callback, TelegramTicketService $telegram): void
    {
        $data = (string) ($callback['data'] ?? '');
        $callbackId = (string) ($callback['id'] ?? '');
        if (preg_match('/^ticket_close:(\d+)$/', $data, $match)) {
            $ticket = Ticket::find((int) $match[1]);
            if (!$ticket) {
                $telegram->answerCallback($callbackId, '宸ュ崟涓嶅瓨鍦?);
                return;
            }
            $ticket->status = Ticket::STATUS_CLOSED;
            $ticket->save();
            $telegram->answerCallback($callbackId, '宸ュ崟宸插叧闂?);
            $telegram->sendText('鉁?宸ュ崟 #' . $ticket->id . ' 宸插叧闂?);
        }
    }

    private function replyToTicket(int $ticketId, string $message, TelegramTicketService $telegram, array $telegramMessage = []): void
    {
        $ticket = Ticket::find($ticketId);
        if (!$ticket) {
            throw new \RuntimeException('宸ュ崟涓嶅瓨鍦?);
        }
        if ((int) $ticket->status === Ticket::STATUS_CLOSED) {
            throw new \RuntimeException('宸ュ崟宸插叧闂紝涓嶈兘鍥炲');
        }
        $adminId = $telegram->resolveAdminUserId();
        if (!$adminId) {
            throw new \RuntimeException('鏈壘鍒?Xboard 绠＄悊鍛樿处鍙?);
        }
        $media = $telegram->importTelegramMedia($telegramMessage, $ticket);
        if ($media) {
            $label = $media->kind === 'video' ? '瀹㈡湇鍙戦€佷簡瑙嗛' : ($media->kind === 'sticker' ? '瀹㈡湇鍙戦€佷簡琛ㄦ儏鍖? : '瀹㈡湇鍙戦€佷簡鍥剧墖');
            $message = trim($message) !== '' ? trim($message) : $label;
            $message .= "\n[[ticket-media:{$media->id}:{$media->kind}]]";
        }
        (new TicketService())->replyByAdmin($ticketId, $message, $adminId);
        if ($media) {
            $media->ticket_message_id = TicketMessage::where('ticket_id', $ticketId)->latest('id')->value('id');
            $media->save();
        }
        $telegram->sendText('鉁?宸插洖澶嶅伐鍗?#' . $ticketId);
    }

    private function closeTicket(int $ticketId, TelegramTicketService $telegram): void
    {
        $ticket = Ticket::find($ticketId);
        if (!$ticket) {
            throw new \RuntimeException('宸ュ崟涓嶅瓨鍦?);
        }
        $ticket->status = Ticket::STATUS_CLOSED;
        $ticket->save();
        $telegram->sendText('鉁?宸ュ崟 #' . $ticketId . ' 宸插叧闂?);
    }

    private function showTicket(int $ticketId, TelegramTicketService $telegram): void
    {
        $ticket = Ticket::with(['user', 'messages' => fn ($query) => $query->latest('id')->limit(5)])->find($ticketId);
        if (!$ticket) {
            throw new \RuntimeException('宸ュ崟涓嶅瓨鍦?);
        }
        $lines = [
            '<b>宸ュ崟 #' . $ticket->id . '</b>',
            '<b>涓婚锛?/b>' . htmlspecialchars((string) $ticket->subject, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'),
            '<b>鐢ㄦ埛锛?/b>' . htmlspecialchars((string) ($ticket->user->email ?? $ticket->user_id), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'),
            '<b>鐘舵€侊細</b>' . ((int) $ticket->status === Ticket::STATUS_CLOSED ? '宸插叧闂? : '澶勭悊涓?),
            '',
        ];
        foreach ($ticket->messages->reverse() as $item) {
            $role = (int) $item->user_id === (int) $ticket->user_id ? '鐢ㄦ埛' : '瀹㈡湇';
            $lines[] = '<b>' . $role . '锛?/b>' . htmlspecialchars((string) $item->message, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        }
        $telegram->sendText(implode("\n", $lines));
    }
}
