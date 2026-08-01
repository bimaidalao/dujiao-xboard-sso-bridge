<?php

namespace App\Http\Controllers\V1\User;

use App\Http\Controllers\Controller;
use App\Http\Requests\User\TicketSave;
use App\Services\Plugin\HookManager;
use App\Services\TicketService;
use Illuminate\Support\Facades\Log;

class StoreOrderTicketController extends Controller
{
    private function fetchStoreOrder(TicketSave $request, int $orderId): ?array
    {
        if ($orderId < 1) return null;
        $authorization = trim((string) $request->header('Authorization', ''));
        if ($authorization === '') return null;

        $curl = curl_init(rtrim((string) env('DUJIAO_PUBLIC_URL'), '/') . '/sso/orders');
        curl_setopt_array($curl, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 8,
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Accept: application/json', 'Content-Type: application/json'],
            CURLOPT_POSTFIELDS => json_encode(['xboard_auth' => $authorization, 'order_id' => $orderId]),
        ]);
        $body = curl_exec($curl);
        $status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
        curl_close($curl);
        if (!is_string($body) || $status !== 200) {
            Log::warning('Dujiao order verification failed', ['status' => $status, 'order_id' => $orderId]);
            return null;
        }
        $payload = json_decode($body, true);
        $order = is_array($payload['orders'][0] ?? null) ? $payload['orders'][0] : null;
        return $order && (int) ($order['id'] ?? 0) === $orderId ? $order : null;
    }

    private function appendOrderSummary(string $message, array $order): string
    {
        $statusMap = [
            'pending' => '待处理', 'unpaid' => '待支付', 'paid' => '已支付', 'processing' => '处理中',
            'delivered' => '已交付', 'completed' => '已完成', 'canceled' => '已取消', 'cancelled' => '已取消',
            'refunded' => '已退款', 'failed' => '失败',
        ];
        $rawStatus = strtolower((string) ($order['status'] ?? ''));
        $products = implode('、', array_map('strval', (array) ($order['products'] ?? [])));
        return rtrim($message) . "\n\n" . implode("\n", [
            '[关联 AI 工具商店订单]',
            '订单号：' . ($order['order_no'] ?? ''),
            '商品：' . ($products !== '' ? $products : '未命名商品'),
            '金额：' . ($order['amount'] ?? '0.00') . ' ' . ($order['currency'] ?? ''),
            '订单状态：' . ($statusMap[$rawStatus] ?? ($order['status'] ?? '未知状态')),
            '下单时间：' . ($order['created_at'] ?? ''),
        ]);
    }

    public function save(TicketSave $request)
    {
        $request->validate(['go_order_id' => 'nullable|integer|min:1']);
        $orderId = (int) $request->input('go_order_id', 0);
        $order = $this->fetchStoreOrder($request, $orderId);
        if ($orderId > 0 && !$order) {
            return $this->fail([422, '所选 AI 工具商店订单无效或不属于当前账号']);
        }
        $message = (string) $request->input('message');
        if ($order) $message = $this->appendOrderSummary($message, $order);

        $ticket = (new TicketService())->createTicket(
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
        HookManager::call('ticket.create.after', $ticket);
        return $this->success(true);
    }
}
