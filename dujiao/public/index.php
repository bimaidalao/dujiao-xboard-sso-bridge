<?php

declare(strict_types=1);

function envValue(string $name, ?string $default = null): string
{
    $value = getenv($name);
    if ($value === false || $value === '') {
        if ($default !== null) {
            return $default;
        }
        throw new RuntimeException("Missing environment variable: {$name}");
    }
    return $value;
}

function failRedirect(): void
{
    header('Location: ' . rtrim(envValue('DUJIAO_PUBLIC_URL'), '/') . '/auth/login?sso=failed', true, 302);
    exit;
}

function base64UrlEncode(string $value): string
{
    return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
}

function readUserJwtSecret(): string
{
    $lines = file(envValue('DUJIAO_CONFIG_PATH'), FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        throw new RuntimeException('Unable to read Dujiao config');
    }

    $inside = false;
    foreach ($lines as $line) {
        if (preg_match('/^user_jwt:\s*$/', $line)) {
            $inside = true;
            continue;
        }
        if ($inside && preg_match('/^[A-Za-z_][A-Za-z0-9_]*:\s*/', $line)) {
            break;
        }
        if ($inside && preg_match('/^\s+secret:\s*(.+?)\s*(?:#.*)?$/', $line, $matches)) {
            return trim($matches[1], " \t\n\r\0\x0B\"'");
        }
    }
    throw new RuntimeException('user_jwt.secret not found');
}

function issueUserToken(array $user): string
{
    $now = time();
    $header = ['alg' => 'HS256', 'typ' => 'JWT'];
    $claims = [
        'user_id' => (int) $user['id'],
        'email' => (string) $user['email'],
        'token_version' => (int) $user['token_version'],
        'typ' => 'access',
        'exp' => $now + 3600,
        'iat' => $now,
        'nbf' => $now,
    ];
    $encodedHeader = base64UrlEncode(json_encode($header, JSON_UNESCAPED_SLASHES));
    $encodedClaims = base64UrlEncode(json_encode($claims, JSON_UNESCAPED_SLASHES));
    $signature = hash_hmac('sha256', $encodedHeader . '.' . $encodedClaims, readUserJwtSecret(), true);
    return $encodedHeader . '.' . $encodedClaims . '.' . base64UrlEncode($signature);
}

function fetchXboardUser(string $authData): array
{
    $curl = curl_init(envValue('XBOARD_USER_INFO_URL'));
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 6,
        CURLOPT_HTTPHEADER => ['Accept: application/json', 'Authorization: ' . $authData],
    ]);
    $body = curl_exec($curl);
    $status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
    curl_close($curl);
    if (!is_string($body) || $status < 200 || $status >= 300) {
        throw new RuntimeException('Xboard session rejected');
    }

    $payload = json_decode($body, true);
    $profile = is_array($payload['data'] ?? null) ? $payload['data'] : [];
    $email = strtolower(trim((string) ($profile['email'] ?? '')));
    if (!filter_var($email, FILTER_VALIDATE_EMAIL) || !empty($profile['banned'])) {
        throw new RuntimeException('Invalid Xboard profile');
    }
    return ['email' => $email];
}

function readXboardPasswordHash(string $email): string
{
    $settings = [];
    $lines = file(envValue('XBOARD_ENV_PATH'), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $settings[trim($key)] = trim(trim($value), "\"'");
    }

    foreach (['DB_DATABASE', 'DB_USERNAME', 'DB_PASSWORD'] as $required) {
        if (!array_key_exists($required, $settings)) {
            throw new RuntimeException('Incomplete Xboard database configuration');
        }
    }

    $database = new PDO(
        'mysql:host=' . ($settings['DB_HOST'] ?? '127.0.0.1')
        . ';port=' . ($settings['DB_PORT'] ?? '3306')
        . ';dbname=' . $settings['DB_DATABASE'] . ';charset=utf8mb4',
        $settings['DB_USERNAME'],
        $settings['DB_PASSWORD'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
    $query = $database->prepare('SELECT password FROM v2_user WHERE LOWER(email) = LOWER(:email) LIMIT 1');
    $query->execute([':email' => $email]);
    $row = $query->fetch();
    $hash = (string) ($row['password'] ?? '');
    if (!preg_match('/^\$2[aby]\$\d{2}\$[.\/A-Za-z0-9]{53}$/', $hash)) {
        throw new RuntimeException('Unsupported Xboard password hash');
    }
    return strncmp($hash, '$2y$', 4) === 0 ? '$2a$' . substr($hash, 4) : $hash;
}

function findOrCreateDujiaoUser(string $email, string $passwordHash): array
{
    $database = new PDO('sqlite:' . envValue('DUJIAO_DATABASE_PATH'), null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $database->exec('PRAGMA busy_timeout = 5000');
    $database->beginTransaction();
    try {
        $select = $database->prepare('SELECT id, email, password_hash, token_version, status FROM users WHERE lower(email) = lower(:email) AND deleted_at IS NULL LIMIT 1');
        $select->execute([':email' => $email]);
        $user = $select->fetch();
        $now = gmdate('Y-m-d H:i:s');

        if (!$user) {
            $insert = $database->prepare(
                'INSERT INTO users (email, password_hash, password_setup_required, display_name, locale, status, member_level_id, total_recharged, total_spent, token_version, email_verified_at, last_login_at, created_at, updated_at) '
                . 'VALUES (:email, :password_hash, 0, :display_name, :locale, :status, 0, 0, 0, 0, :verified_at, :last_login_at, :created_at, :updated_at)'
            );
            $insert->execute([
                ':email' => $email,
                ':password_hash' => $passwordHash,
                ':display_name' => strstr($email, '@', true) ?: 'User',
                ':locale' => 'zh-CN',
                ':status' => 'active',
                ':verified_at' => $now,
                ':last_login_at' => $now,
                ':created_at' => $now,
                ':updated_at' => $now,
            ]);
            $user = ['id' => (int) $database->lastInsertId(), 'email' => $email, 'password_hash' => $passwordHash, 'token_version' => 0, 'status' => 'active'];
        } else {
            $changed = !hash_equals((string) $user['password_hash'], $passwordHash);
            $update = $database->prepare(
                'UPDATE users SET password_hash = :password_hash, password_setup_required = 0, '
                . 'token_version = token_version + :increment, last_login_at = :last_login_at, updated_at = :updated_at WHERE id = :id'
            );
            $update->execute([
                ':password_hash' => $passwordHash,
                ':increment' => $changed ? 1 : 0,
                ':last_login_at' => $now,
                ':updated_at' => $now,
                ':id' => $user['id'],
            ]);
            if ($changed) {
                $user['token_version'] = (int) $user['token_version'] + 1;
            }
        }

        if (($user['status'] ?? '') !== 'active') {
            throw new RuntimeException('Dujiao user is not active');
        }
        $database->commit();
        return $user;
    } catch (Throwable $exception) {
        if ($database->inTransaction()) {
            $database->rollBack();
        }
        throw $exception;
    }
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    failRedirect();
}

$authData = trim((string) ($_POST['xboard_auth'] ?? ''));
if ($authData === '' || strlen($authData) > 8192) {
    failRedirect();
}

try {
    $xboardUser = fetchXboardUser($authData);
    $passwordHash = readXboardPasswordHash($xboardUser['email']);
    $dujiaoUser = findOrCreateDujiaoUser($xboardUser['email'], $passwordHash);
    $token = issueUserToken($dujiaoUser);
} catch (Throwable $exception) {
    error_log('Xboard to Dujiao SSO failed: ' . $exception->getMessage());
    failRedirect();
}

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store, private');
header('Referrer-Policy: no-referrer');
header("Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'");
$encodedToken = json_encode($token, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
echo '<!doctype html><meta charset="utf-8"><title>Signing in</title>';
echo '<style>body{display:grid;place-items:center;min-height:100vh;font:14px system-ui;color:#334155;background:#f6f8fc}</style>';
echo '<body>Signing in securely…<script>localStorage.setItem("user_token",' . $encodedToken . ');location.replace("/");</script></body>';
