<?php

declare(strict_types=1);

function orderEnv(string $name): string
{
    $value = getenv($name);
    if ($value === false || $value === '') {
        throw new RuntimeException("Missing environment variable: {$name}");
    }
    return $value;
}

function orderRespond(int $status, array $payload): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, private');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function localizedOrderTitle(?string $json): string
{
    $decoded = json_decode((string) $json, true);
    if (is_string($decoded)) return trim($decoded);
    if (!is_array($decoded)) return '未命名商品';
    foreach (['zh-CN', 'zh_CN', 'zh', 'en-US', 'en'] as $key) {
        if (isset($decoded[$key]) && is_string($decoded[$key]) && trim($decoded[$key]) !== '') {
            return trim($decoded[$key]);
        }
    }
    foreach ($decoded as $value) {
        if (is_string($value) && trim($value) !== '') return trim($value);
    }
    return '未命名商品';
}

$allowedOrigins = array_values(array_filter(array_map('trim', explode(',', orderEnv('XBOARD_PUBLIC_ORIGINS')))));
$origin = (string) ($_SERVER['HTTP_ORIGIN'] ?? '');
$originAllowed = $origin !== '' && in_array($origin, $allowedOrigins, true);
if ($originAllowed) {
    header('Access-Control-Allow-Origin: ' . $origin);
    header('Vary: Origin');
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
    header('Access-Control-Max-Age: 600');
}
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    if (!$originAllowed) orderRespond(403, ['ok' => false, 'message' => 'Origin rejected']);
    http_response_code(204);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST' || ($origin !== '' && !$originAllowed)) {
    orderRespond(405, ['ok' => false, 'message' => 'Method rejected']);
}

$input = json_decode((string) file_get_contents('php://input'), true);
if (!is_array($input)) $input = $_POST;
$authData = trim((string) ($input['xboard_auth'] ?? ''));
$orderId = isset($input['order_id']) ? (int) $input['order_id'] : 0;
if ($authData === '' || strlen($authData) > 8192) {
    orderRespond(401, ['ok' => false, 'message' => 'Authentication required']);
}

$curl = curl_init(orderEnv('XBOARD_USER_INFO_URL'));
curl_setopt_array($curl, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 6,
    CURLOPT_HTTPHEADER => ['Accept: application/json', 'Authorization: ' . $authData],
]);
$body = curl_exec($curl);
$status = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
curl_close($curl);
if (!is_string($body) || $status < 200 || $status >= 300) {
    orderRespond(401, ['ok' => false, 'message' => 'Session rejected']);
}
$profilePayload = json_decode($body, true);
$profile = is_array($profilePayload['data'] ?? null) ? $profilePayload['data'] : [];
$email = strtolower(trim((string) ($profile['email'] ?? '')));
if (!filter_var($email, FILTER_VALIDATE_EMAIL) || !empty($profile['banned'])) {
    orderRespond(401, ['ok' => false, 'message' => 'Invalid account']);
}

try {
    $database = new PDO('sqlite:' . orderEnv('DUJIAO_DATABASE_PATH'), null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $userQuery = $database->prepare('SELECT id FROM users WHERE lower(email) = lower(:email) AND deleted_at IS NULL LIMIT 1');
    $userQuery->execute([':email' => $email]);
    $userId = (int) ($userQuery->fetchColumn() ?: 0);
    if ($userId === 0) orderRespond(200, ['ok' => true, 'orders' => []]);

    $sql = 'SELECT o.id, o.order_no, o.status, o.currency, o.total_amount, o.created_at, '
        . 'GROUP_CONCAT(oi.title_json, char(30)) AS item_titles '
        . 'FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.id AND oi.deleted_at IS NULL '
        . 'WHERE o.user_id = :user_id AND o.deleted_at IS NULL ';
    $params = [':user_id' => $userId];
    if ($orderId > 0) {
        $sql .= 'AND o.id = :order_id ';
        $params[':order_id'] = $orderId;
    }
    $sql .= 'GROUP BY o.id HAVING COUNT(oi.id) > 0 ORDER BY o.created_at DESC LIMIT 20';
    $query = $database->prepare($sql);
    $query->execute($params);
    $orders = [];
    foreach ($query->fetchAll() as $row) {
        $titles = [];
        foreach (explode(chr(30), (string) ($row['item_titles'] ?? '')) as $titleJson) {
            if ($titleJson !== '') $titles[] = localizedOrderTitle($titleJson);
        }
        $orders[] = [
            'id' => (int) $row['id'],
            'order_no' => (string) $row['order_no'],
            'products' => array_values(array_unique($titles)),
            'amount' => number_format((float) $row['total_amount'], 2, '.', ''),
            'currency' => (string) $row['currency'],
            'status' => (string) $row['status'],
            'created_at' => (string) $row['created_at'],
        ];
    }
    orderRespond(200, ['ok' => true, 'orders' => $orders]);
} catch (Throwable $exception) {
    error_log('Dujiao ticket order lookup failed: ' . $exception->getMessage());
    orderRespond(500, ['ok' => false, 'message' => 'Order lookup failed']);
}
