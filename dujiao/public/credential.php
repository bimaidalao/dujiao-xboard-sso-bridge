<?php

declare(strict_types=1);

function value(string $name): string
{
    $value = getenv($name);
    if ($value === false || $value === '') throw new RuntimeException("Missing environment variable: {$name}");
    return $value;
}

function output(int $status, array $payload): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, private');
    header('X-Content-Type-Options: nosniff');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    exit;
}

if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true)) {
    output(403, ['error' => 'local_requests_only']);
}

$authorization = trim((string) ($_SERVER['HTTP_AUTHORIZATION'] ?? ''));
if (!preg_match('/^Bearer\s+(.+)$/i', $authorization, $matches)) output(401, ['error' => 'missing_token']);
$token = trim($matches[1]);
if ($token === '' || strlen($token) > 4096) output(401, ['error' => 'invalid_token']);

$curl = curl_init(value('DUJIAO_IDENTITY_URL'));
curl_setopt_array($curl, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 5,
    CURLOPT_HTTPHEADER => ['Accept: application/json', 'Authorization: Bearer ' . $token],
]);
$body = curl_exec($curl);
$status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
curl_close($curl);
$identity = is_string($body) ? json_decode($body, true) : null;
$profile = is_array($identity['data'] ?? null) ? $identity['data'] : [];
$email = strtolower(trim((string) ($profile['email'] ?? '')));
if (
    $status !== 200
    || (int) ($identity['status_code'] ?? -1) !== 0
    || !filter_var($email, FILTER_VALIDATE_EMAIL)
    || empty($profile['email_verified_at'])
    || (string) ($profile['status'] ?? 'active') !== 'active'
) {
    output(401, ['error' => 'identity_rejected']);
}

$database = new PDO('sqlite:' . value('DUJIAO_DATABASE_PATH'), null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$query = $database->prepare('SELECT password_hash FROM users WHERE lower(email) = lower(:email) AND deleted_at IS NULL LIMIT 1');
$query->execute([':email' => $email]);
$hash = (string) $query->fetchColumn();
if (!preg_match('/^\$2[aby]\$\d{2}\$[.\/A-Za-z0-9]{53}$/', $hash)) {
    output(409, ['error' => 'unsupported_password_hash']);
}
output(200, ['password_hash' => $hash]);
