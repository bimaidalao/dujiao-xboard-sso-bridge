<?php

namespace App\Http\Controllers\V1\User;

use App\Http\Controllers\Controller;
use App\Http\Requests\User\TicketSave;
use App\Http\Requests\User\TicketWithdraw;
use App\Http\Resources\TicketResource;
use App\Models\Ticket;
use App\Models\TicketMessage;
use App\Models\TicketMedia;
use App\Models\User;
use App\Models\Order;
use App\Services\TicketService;
use App\Utils\Dict;
use Illuminate\Http\Request;
use App\Services\Plugin\HookManager;
use Illuminate\Support\Facades\Log;

class TicketController extends Controller
{
    private function pendingMedia(Request $request)
    {
        $ids = array_values(array_unique(array_filter((array) $request->input('media_ids', []))));
        if (count($ids) > 4) {
            abort(422, '每条消息最多上传 4 个媒体');
        }
        if ($ids === []) {
            return collect();
        }
        $media = TicketMedia::whereIn('id', $ids)
            ->where('user_id', (int) $request->user()->id)
            ->whereNull('ticket_id')
            ->get();
        if ($media->count() !== count($ids)) {
            abort(422, '附件无效、已使用或不属于当前账号');
        }
        return $media;
    }

    private function appendMediaMarkers(string $message, $media): string
    {
        foreach ($media as $item) {
            $message = rtrim($message) . "\n[[ticket-media:{$item->id}:{$item->kind}]]";
        }
        return trim($message);
    }

    private function attachMedia($media, Ticket $ticket, TicketMessage $ticketMessage): void
    {
        foreach ($media as $item) {
            $item->ticket_id = $ticket->id;
            $item->ticket_message_id = $ticketMessage->id;
            $item->save();
        }
    }

    public function fetch(Request $request)
    {
        if ($request->input('id')) {
            $ticket = Ticket::where('id', $request->input('id'))
                ->where('user_id', $request->user()->id)
                ->first();
            if (!$ticket) {
                return $this->fail([400, __('Ticket does not exist')]);
            }
            $ticket['message'] = TicketMessage::where('ticket_id', $ticket->id)->get();
            $ticket['message']->each(function ($message) use ($ticket) {
                $message['is_me'] = ($message['user_id'] == $ticket->user_id);
            });
            return $this->success(TicketResource::make($ticket)->additional(['message' => true]));
        }
        $ticket = Ticket::where('user_id', $request->user()->id)
            ->orderBy('created_at', 'DESC')
            ->get();
        return $this->success(TicketResource::collection($ticket));
    }

    private function fetchStoreOrder(Request $request, int $orderId): ?array
    {
        $authorization = trim((string) $request->header('Authorization', ''));
        if ($authorization === '') {
            return null;
        }
        $curl = curl_init('https://go.laowu.life/sso/orders');
        curl_setopt_array($curl, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 8,
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Accept: application/json', 'Content-Type: application/json'],
            CURLOPT_POSTFIELDS => json_encode(array_filter([
                'xboard_auth' => $authorization,
                'order_id' => $orderId > 0 ? $orderId : null,
            ], static fn ($value) => $value !== null)),
        ]);
        $body = curl_exec($curl);
        $status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
        curl_close($curl);
        if (!is_string($body) || $status !== 200) {
            Log::warning('AI store order verification failed', ['status' => $status, 'order_id' => $orderId]);
            return null;
        }
        $payload = json_decode($body, true);
        $order = is_array($payload['orders'][0] ?? null) ? $payload['orders'][0] : null;
        if (!$order) return null;
        return $orderId < 1 || (int) ($order['id'] ?? 0) === $orderId ? $order : null;
    }

    private function appendNodeOrderSummary(string $message, int $userId): string
    {
        $order = Order::with('plan')->where('user_id', $userId)->orderByDesc('created_at')->first();
        if (!$order) return $message;
        $periodMap = ['monthly' => '月付', 'quarterly' => '季付', 'half_yearly' => '半年付', 'yearly' => '年付', 'two_yearly' => '两年付', 'three_yearly' => '三年付', 'onetime' => '一次性', 'reset_traffic' => '流量重置'];
        return rtrim($message) . "\n\n" . implode("\n", [
            '[跨境速云最近订单]',
            '订单号：' . $order->trade_no,
            '套餐：' . ($order->plan->name ?? '套餐已下架'),
            '类型：' . (Order::$typeMap[$order->type] ?? (string) $order->type),
            '周期：' . ($periodMap[$order->period] ?? $order->period),
            '金额：' . number_format(((int) $order->total_amount) / 100, 2) . ' CNY',
            '状态：' . (Order::$statusMap[$order->status] ?? (string) $order->status),
            '下单时间：' . date('Y-m-d H:i:s', (int) $order->created_at),
        ]);
    }

    private function appendStoreOrderSummary(string $message, array $order): string
    {
        $products = implode('、', array_map('strval', (array) ($order['products'] ?? [])));
        $statusMap = [
            'pending' => '待处理', 'unpaid' => '待支付', 'paid' => '已支付', 'processing' => '处理中',
            'delivered' => '已交付', 'completed' => '已完成', 'canceled' => '已取消', 'cancelled' => '已取消',
            'refunded' => '已退款', 'failed' => '失败',
        ];
        $rawStatus = strtolower((string) ($order['status'] ?? ''));
        $status = $statusMap[$rawStatus] ?? ($order['status'] ?? '未知状态');
        $lines = [
            '[关联 AI 工具商店订单]',
            '订单号：' . ($order['order_no'] ?? ''),
            '商品：' . ($products !== '' ? $products : '未命名商品'),
            '金额：' . ($order['amount'] ?? '0.00') . ' ' . ($order['currency'] ?? ''),
            '订单状态：' . $status,
            '下单时间：' . ($order['created_at'] ?? ''),
        ];
        return rtrim($message) . "\n\n" . implode("\n", $lines);
    }

    public function save(TicketSave $request)
    {
        $media = $this->pendingMedia($request);
        $orderId = (int) $request->input('go_order_id', 0);
        $order = $this->fetchStoreOrder($request, $orderId);
        if ($orderId > 0 && !$order) {
            return $this->fail([422, '所选 AI 工具商店订单无效或不属于当前账号']);
        }
        $message = $this->appendNodeOrderSummary((string) $request->input('message'), (int) $request->user()->id);
        if ($order) {
            $message = $this->appendStoreOrderSummary($message, $order);
        }
        $message = $this->appendMediaMarkers($message, $media);
        $ticketService = new TicketService();
        $ticket = $ticketService->createTicket(
            $request->user()->id,
            $request->input('subject'),
            $request->input('level'),
            $message
        );
        if ($order) {
            $ticket->go_order_id = (int) $order['id'];
            $ticket->go_order_no = (string) $order['order_no'];
            $ticket->save();
        }
        $ticketMessage = TicketMessage::where('ticket_id', $ticket->id)->latest('id')->first();
        if ($ticketMessage) {
            $this->attachMedia($media, $ticket, $ticketMessage);
        }
        HookManager::call('ticket.create.after', $ticket);
        return $this->success(true);
    }

    public function reply(Request $request)
    {
        if (empty($request->input('id'))) return $this->fail([400, __('Invalid parameter')]);
        $media = $this->pendingMedia($request);
        if (empty($request->input('message')) && $media->isEmpty()) return $this->fail([400, __('Message cannot be empty')]);
        $ticket = Ticket::where('id', $request->input('id'))->where('user_id', $request->user()->id)->first();
        if (!$ticket) return $this->fail([400, __('Ticket does not exist')]);
        if ($ticket->status) return $this->fail([400, __('The ticket is closed and cannot be replied')]);
        if ($request->user()->id == $this->getLastMessage($ticket->id)->user_id) return $this->fail(codeResponse: [400, __('Please wait for the technical enginneer to reply')]);
        $ticketService = new TicketService();
        $message = $this->appendMediaMarkers((string) $request->input('message', ''), $media);
        $ticketMessage = $ticketService->reply($ticket, $message, $request->user()->id);
        if (!$ticketMessage) return $this->fail([400, __('Ticket reply failed')]);
        $this->attachMedia($media, $ticket, $ticketMessage);
        HookManager::call('ticket.reply.user.after', $ticket);
        return $this->success(true);
    }

    public function close(Request $request)
    {
        if (empty($request->input('id'))) return $this->fail([422, __('Invalid parameter')]);
        $ticket = Ticket::where('id', $request->input('id'))->where('user_id', $request->user()->id)->first();
        if (!$ticket) return $this->fail([400, __('Ticket does not exist')]);
        $ticket->status = Ticket::STATUS_CLOSED;
        if (!$ticket->save()) return $this->fail([500, __('Close failed')]);
        return $this->success(true);
    }

    private function getLastMessage($ticketId)
    {
        return TicketMessage::where('ticket_id', $ticketId)->orderBy('id', 'DESC')->first();
    }

    public function withdraw(TicketWithdraw $request)
    {
        if ((int) admin_setting('withdraw_close_enable', 0)) return $this->fail([400, 'Unsupported withdraw']);
        if (!in_array($request->input('withdraw_method'), admin_setting('commission_withdraw_method', Dict::WITHDRAW_METHOD_WHITELIST_DEFAULT))) return $this->fail([422, __('Unsupported withdrawal method')]);
        $user = User::find($request->user()->id);
        $limit = admin_setting('commission_withdraw_limit', 100);
        if ($limit > ($user->commission_balance / 100)) return $this->fail([422, __('The current required minimum withdrawal commission is :limit', ['limit' => $limit])]);
        $ticketService = new TicketService();
        $message = sprintf("%s\r\n%s", __('Withdrawal method') . '：' . $request->input('withdraw_method'), __('Withdrawal account') . '：' . $request->input('withdraw_account'));
        $ticket = $ticketService->createTicket($request->user()->id, __('[Commission Withdrawal Request] This ticket is opened by the system'), 2, $message);
        HookManager::call('ticket.create.after', $ticket);
        return $this->success(true);
    }
}
