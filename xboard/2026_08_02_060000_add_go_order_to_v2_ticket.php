<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasColumn('v2_ticket', 'go_order_id')) {
            Schema::table('v2_ticket', fn (Blueprint $table) => $table->unsignedBigInteger('go_order_id')->nullable()->after('user_id')->index());
        }
        if (!Schema::hasColumn('v2_ticket', 'go_order_no')) {
            Schema::table('v2_ticket', fn (Blueprint $table) => $table->string('go_order_no', 64)->nullable()->after('go_order_id')->index());
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('v2_ticket', 'go_order_no')) Schema::table('v2_ticket', fn (Blueprint $table) => $table->dropColumn('go_order_no'));
        if (Schema::hasColumn('v2_ticket', 'go_order_id')) Schema::table('v2_ticket', fn (Blueprint $table) => $table->dropColumn('go_order_id'));
    }
};
