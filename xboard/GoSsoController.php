<?php

namespace App\Http\Controllers\V1\Passport;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\LoginService;
use App\Services\UserService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class GoSsoController extends Controller
{
    protected $loginService;

    public function __construct(LoginService $loginService)
    {
        $this->loginService = $loginService;
    }

    public function login(Request $request)
    {
        $params = $request->validate([
            'dujiao_token' => 'required|string|max:4096',
            'redirect' => 'nullable|string|max:40',
        ]);

        $allowedRedirects = ['dashboard', 'tickets', 'mobile/tickets', 'plan'];
        $redirect = in_array($params['redirect'] ?? '', $allowedRedirects, true)
            ? $params['redirect']
            : 'dashboard';

        try {
            $response = Http::acceptJson()
                ->withToken($params['dujiao_token'])
                ->timeout(5)
                ->get((string) env('DUJIAO_IDENTITY_URL'));
        } catch (\Throwable $exception) {
            Log::warning('Dujiao SSO identity request failed', ['error' => $exception->getMessage()]);
            return $this->failureRedirect();
        }

        $payload = $response->json();
        $profile = is_array(data_get($payload, 'data')) ? data_get($payload, 'data') : [];
        $email = strtolower(trim((string) data_get($profile, 'email', '')));

        if (
            !$response->successful()
            || !filter_var($email, FILTER_VALIDATE_EMAIL)
            || empty(data_get($profile, 'email_verified_at'))
            || (string) data_get($profile, 'status', 'active') !== 'active'
        ) {
            return $this->failureRedirect();
        }

        $user = User::whereRaw('LOWER(email) = ?', [$email])->first();
        if (!$user) {
            $user = app(UserService::class)->createUser([
                'email' => $email,
                'password' => Str::random(64),
            ]);
            $user->save();
        }

        if ($user->banned) {
            return $this->failureRedirect();
        }

        $user->last_login_at = time();
        $user->save();

        $url = $this->loginService->generateQuickLoginUrl($user, $redirect);
        return $url ? redirect()->away($url) : $this->failureRedirect();
    }

    private function failureRedirect()
    {
        return redirect()->away((string) env('DUJIAO_SSO_FAILURE_URL', '/'));
    }
}
