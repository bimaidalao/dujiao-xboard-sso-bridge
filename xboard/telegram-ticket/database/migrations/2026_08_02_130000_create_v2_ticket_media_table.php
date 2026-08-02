<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('v2_ticket_media')) {
            return;
        }
        Schema::create('v2_ticket_media', function (Blueprint $table) {
            $table->string('id', 36)->primary();
            $table->unsignedBigInteger('ticket_id')->nullable()->index();
            $table->unsignedBigInteger('ticket_message_id')->nullable()->index();
            $table->unsignedBigInteger('user_id')->index();
            $table->string('kind', 16);
            $table->string('mime', 100);
            $table->string('original_name', 255)->nullable();
            $table->string('path', 500);
            $table->unsignedBigInteger('size')->default(0);
            $table->string('telegram_file_id', 255)->nullable();
            $table->unsignedInteger('created_at');
            $table->unsignedInteger('updated_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('v2_ticket_media');
    }
};
