<?php
namespace App\Services;


use App\Exceptions\ApiException;
use App\Jobs\SendEmailJob;
use App\Models\Ticket;
use App\Models\TicketMessage;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use App\Services\Plugin\HookManager;

class TicketService
{
    public function reply($ticket, $message, $userId)
    {
        try {
            DB::beginTransaction();
            $ticketMessage = TicketMessage::create([
                'user_id' => $userId,
                'ticket_id' => $ticket->id,
                'message' => $message
            ]);
            if ($userId !== $ticket->user_id) {
                $ticket->reply_status = Ticket::STATUS_OPENING;
            } else {
                $ticket->reply_status = Ticket::STATUS_CLOSED;
            }
            if (!$ticketMessage || !$ticket->save()) {
                throw new \Exception();
            }
            DB::commit();
            app(TelegramTicketService::class)->notifyTicket($ticket, 'reply', (string) $message);
            return $ticketMessage;
        } catch (\Exception $e) {
            DB::rollback();
            return false;
        }
    }

    public function replyByAdmin($ticketId, $message, $userId): void
    {
        $ticket = Ticket::where('id', $ticketId)
            ->first();
        if (!$ticket) {
            throw new ApiException('宸ュ崟涓嶅瓨鍦?);
        }
        $ticket->status = Ticket::STATUS_OPENING;
        try {
            DB::beginTransaction();
            $ticketMessage = TicketMessage::create([
                'user_id' => $userId,
                'ticket_id' => $ticket->id,
                'message' => $message
            ]);
            if ($userId !== $ticket->user_id) {
                $ticket->reply_status = Ticket::STATUS_OPENING;
            } else {
                $ticket->reply_status = Ticket::STATUS_CLOSED;
            }
            if (!$ticketMessage || !$ticket->save()) {
                throw new ApiException('宸ュ崟鍥炲澶辫触');
            }
            DB::commit();
            HookManager::call('ticket.reply.admin.after', [$ticket, $ticketMessage]);
        } catch (\Exception $e) {
            DB::rollBack();
            throw $e;
        }
        $this->sendEmailNotify($ticket, $ticketMessage);
    }

    public function createTicket($userId, $subject, $level, $message)
    {
        try {
            DB::beginTransaction();
            if (Ticket::where('status', 0)->where('user_id', $userId)->lockForUpdate()->first()) {
                DB::rollBack();
                throw new ApiException('瀛樺湪鏈叧闂殑宸ュ崟');
            }
            $ticket = Ticket::create([
                'user_id' => $userId,
                'subject' => $subject,
                'level' => $level
            ]);
            if (!$ticket) {
                throw new ApiException('宸ュ崟鍒涘缓澶辫触');
            }
            $ticketMessage = TicketMessage::create([
                'user_id' => $userId,
                'ticket_id' => $ticket->id,
                'message' => $message
            ]);
            if (!$ticketMessage) {
                DB::rollBack();
                throw new ApiException('宸ュ崟娑堟伅鍒涘缓澶辫触');
            }
            DB::commit();
            app(TelegramTicketService::class)->notifyTicket($ticket, 'created', (string) $message);
            return $ticket;
        } catch (\Exception $e) {
            DB::rollBack();
            throw $e;
        }
    }

    // 鍗婂皬鏃跺唴涓嶅啀閲嶅閫氱煡
    private function sendEmailNotify(Ticket $ticket, TicketMessage $ticketMessage)
    {
        $user = User::find($ticket->user_id);
        $cacheKey = 'ticket_sendEmailNotify_' . $ticket->user_id;
        if (!Cache::get($cacheKey)) {
            Cache::put($cacheKey, 1, 1800);
            SendEmailJob::dispatch([
                'email' => $user->email,
                'subject' => '鎮ㄥ湪' . admin_setting('app_name', 'XBoard') . '鐨勫伐鍗曞緱鍒颁簡鍥炲',
                'template_name' => 'notify',
                'template_value' => [
                    'name' => admin_setting('app_name', 'XBoard'),
                    'url' => admin_setting('app_url'),
                    'content' => "涓婚锛歿$ticket->subject}\r\n鍥炲鍐呭锛歿$ticketMessage->message}"
                ]
            ]);
        }
    }
}
