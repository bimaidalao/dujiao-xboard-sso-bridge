<?php

namespace App\Http\Requests\User;

use Illuminate\Foundation\Http\FormRequest;

class TicketSave extends FormRequest
{
    public function rules()
    {
        return [
            'subject' => 'required',
            'level' => 'required|in:0,1,2',
            'message' => 'nullable|required_without:media_ids',
            'media_ids' => 'nullable|array|max:4',
            'media_ids.*' => 'string|uuid',
            'go_order_id' => 'nullable|integer|min:1',
        ];
    }

    public function messages()
    {
        return [
            'subject.required' => __('Ticket subject cannot be empty'),
            'level.required' => __('Ticket level cannot be empty'),
            'level.in' => __('Incorrect ticket level format'),
            'message.required' => __('Message cannot be empty'),
            'message.required_without' => '消息内容和附件不能同时为空',
            'go_order_id.integer' => 'AI 工具商店订单格式不正确',
        ];
    }
}
