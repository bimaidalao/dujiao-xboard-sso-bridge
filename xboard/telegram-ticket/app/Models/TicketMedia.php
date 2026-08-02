<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TicketMedia extends Model
{
    protected $table = 'v2_ticket_media';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $dateFormat = 'U';
    protected $guarded = [];
    protected $casts = [
        'size' => 'integer',
        'created_at' => 'timestamp',
        'updated_at' => 'timestamp',
    ];
}
