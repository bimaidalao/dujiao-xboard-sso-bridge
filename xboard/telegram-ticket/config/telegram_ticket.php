<?php

return [
    'enabled' => env('TELEGRAM_TICKET_ENABLED', false),
    'bot_token' => env('TELEGRAM_TICKET_BOT_TOKEN', ''),
    'chat_id' => env('TELEGRAM_TICKET_CHAT_ID', ''),
    'allowed_user_ids' => env('TELEGRAM_TICKET_ALLOWED_USER_IDS', ''),
    'webhook_secret' => env('TELEGRAM_TICKET_WEBHOOK_SECRET', ''),
    'xboard_admin_user_id' => env('TELEGRAM_TICKET_XBOARD_ADMIN_USER_ID', 0),
    'admin_url' => env('TELEGRAM_TICKET_ADMIN_URL', ''),
];
