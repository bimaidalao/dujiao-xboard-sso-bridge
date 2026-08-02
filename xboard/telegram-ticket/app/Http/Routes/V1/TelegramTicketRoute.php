<?php

namespace App\Http\Routes\V1;

use App\Http\Controllers\V1\Guest\TelegramTicketController;
use Illuminate\Contracts\Routing\Registrar;

class TelegramTicketRoute
{
    public function map(Registrar $router)
    {
        $router->post('/telegram/ticket/webhook', [TelegramTicketController::class, 'webhook']);
    }
}
