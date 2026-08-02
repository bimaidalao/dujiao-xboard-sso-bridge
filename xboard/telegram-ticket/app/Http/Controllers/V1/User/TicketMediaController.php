<?php

namespace App\Http\Controllers\V1\User;

use App\Http\Controllers\Controller;
use App\Models\TicketMedia;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class TicketMediaController extends Controller
{
    private const MIME_MAP = [
        'image/jpeg' => ['image', 'jpg'],
        'image/png' => ['image', 'png'],
        'image/gif' => ['sticker', 'gif'],
        'image/webp' => ['sticker', 'webp'],
        'video/mp4' => ['video', 'mp4'],
        'video/webm' => ['video', 'webm'],
        'video/quicktime' => ['video', 'mov'],
    ];

    public function upload(Request $request)
    {
        $request->validate(['file' => 'required|file|max:20480']);
        $file = $request->file('file');
        $mime = strtolower((string) $file->getMimeType());
        if (!isset(self::MIME_MAP[$mime])) {
            return $this->fail([422, '浠呮敮鎸?JPG銆丳NG銆丟IF銆乄EBP銆丮P4銆乄EBM 鍜?MOV']);
        }

        [$kind, $extension] = self::MIME_MAP[$mime];
        $id = (string) Str::uuid();
        $path = 'ticket-media/' . date('Y/m') . '/' . $id . '.' . $extension;
        Storage::disk('local')->putFileAs(dirname($path), $file, basename($path));
        $media = TicketMedia::create([
            'id' => $id,
            'user_id' => (int) $request->user()->id,
            'kind' => $kind,
            'mime' => $mime,
            'original_name' => mb_substr((string) $file->getClientOriginalName(), 0, 255),
            'path' => $path,
            'size' => (int) $file->getSize(),
        ]);

        return $this->success([
            'id' => $media->id,
            'kind' => $media->kind,
            'mime' => $media->mime,
            'size' => $media->size,
        ]);
    }

    public function show(Request $request, string $id)
    {
        $media = TicketMedia::where('id', $id)
            ->where('user_id', (int) $request->user()->id)
            ->first();
        if (!$media || !Storage::disk('local')->exists($media->path)) {
            abort(404);
        }
        return response()->file(Storage::disk('local')->path($media->path), [
            'Content-Type' => $media->mime,
            'Content-Disposition' => 'inline; filename="' . addslashes($media->original_name ?: basename($media->path)) . '"',
            'X-Content-Type-Options' => 'nosniff',
            'Cache-Control' => 'private, max-age=3600',
        ]);
    }
}
