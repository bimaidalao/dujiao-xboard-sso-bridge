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
            $telegram->sendText('❌ 操作失败：' . htmlspecialchars($e->getMessage(), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'));
        }

        return response()->json(['ok' => true]);
    }

    private function handleMessage(array $message, TelegramTicketService $telegram): void
    {
        $text = trim((string) ($message['text'] ?? $message['caption'] ?? ''));
        if ($text === '/start' || $text === '/help') {
            $telegram->sendText("<b>跨境速云工单助手</b>\n\n回复机器人发来的工单通知，可直接回复网站工单。\n也可使用：\n<code>/reply 工单ID 回复内容</code>\n<code>/close 工单ID</code>\n<code>/ticket 工单ID</code>");
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
                $telegram->sendText('请输入文字，或发送图片、贴纸、视频。');
                return;
            }
            $this->replyToTicket((int) $match[1], $text, $telegram, $message);
            return;
        }

        $telegram->sendText('请直接“回复”某条工单通知，或发送 <code>/help</code> 查看命令。');
    }

    private function handleCallback(array $callback, TelegramTicketService $telegram): void
    {
        $data = (string) ($callback['data'] ?? '');
        $callbackId = (string) ($callback['id'] ?? '');
        if (preg_match('/^ticket_close:(\d+)$/', $data, $match)) {
            $ticket = Ticket::find((int) $match[1]);
            if (!$ticket) {
                $telegram->answerCallback($callbackId, '工单不存在');
                return;
            }
            $ticket->status = Ticket::STATUS_CLOSED;
            $ticket->save();
            $telegram->answerCallback($callbackId, '工单已关闭');
            $telegram->sendText('✅ 工单 #' . $ticket->id . ' 已关闭');
        }
    }

    private function replyToTicket(int $ticketId, string $message, TelegramTicketService $telegram, array $telegramMessage = []): void
    {
        $ticket = Ticket::find($ticketId);
        if (!$ticket) {
            throw new \RuntimeException('工单不存在');
        }
        if ((int) $ticket->status === Ticket::STATUS_CLOSED) {
            throw new \RuntimeException('工单已关闭，不能回复');
        }
        $adminId = $telegram->resolveAdminUserId();
        if (!$adminId) {
            throw new \RuntimeException('未找到 Xboard 管理员账号');
        }
        $media = $telegram->importTelegramMedia($telegramMessage, $ticket);
        if ($media) {
            $label = $media->kind === 'video' ? '客服发送了视频' : ($media->kind === 'sticker' ? '客服发送了表情包' : '客服发送了图片');
            $message = trim($message) !== '' ? trim($message) : $label;
            $message .= "\n[[ticket-media:{$media->id}:{$media->kind}]]";
        }
        (new TicketService())->replyByAdmin($ticketId, $message, $adminId);
        if ($media) {
            $media->ticket_message_id = TicketMessage::where('ticket_id', $ticketId)->latest('id')->value('id');
            $media->save();
        }
        $telegram->sendText('✅ 已回复工单 #' . $ticketId);
    }

    private function closeTicket(int $ticketId, TelegramTicketService $telegram): void
    {
        $ticket = Ticket::find($ticketId);
        if (!$ticket) {
            throw new \RuntimeException('工单不存在');
        }
        $ticket->status = Ticket::STATUS_CLOSED;
        $ticket->save();
        $telegram->sendText('✅ 工单 #' . $ticketId . ' 已关闭');
    }

    private function showTicket(int $ticketId, TelegramTicketService $telegram): void
    {
        $ticket = Ticket::with(['user', 'messages' => fn ($query) => $query->latest('id')->limit(5)])->find($ticketId);
        if (!$ticket) {
            throw new \RuntimeException('工单不存在');
        }
        $lines = [
            '<b>工单 #' . $ticket->id . '</b>',
            '<b>主题：</b>' . htmlspecialchars((string) $ticket->subject, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'),
            '<b>用户：</b>' . htmlspecialchars((string) ($ticket->user->email ?? $ticket->user_id), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'),
            '<b>状态：</b>' . ((int) $ticket->status === Ticket::STATUS_CLOSED ? '已关闭' : '处理中'),
            '',
        ];
        foreach ($ticket->messages->reverse() as $item) {
            $role = (int) $item->user_id === (int) $ticket->user_id ? '用户' : '客服';
            $lines[] = '<b>' . $role . '：</b>' . htmlspecialchars((string) $item->message, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        }
        $telegram->sendText(implode("\n", $lines));
    }
}
