<?php
$CONFIG = require __DIR__ . '/config.php';

function db(): PDO {
    global $CONFIG;
    static $pdo;
    if (!$pdo) {
        $pdo = new PDO(
            "mysql:host={$CONFIG['db_host']};dbname={$CONFIG['db_name']};charset=utf8mb4",
            $CONFIG['db_user'], $CONFIG['db_pass'],
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
        );
    }
    return $pdo;
}

function q(string $sql, array $params = []): PDOStatement {
    $st = db()->prepare($sql);
    $st->execute($params);
    return $st;
}

function respond($data, int $code = 200): never {
    http_response_code($code);
    echo json_encode($data, JSON_NUMERIC_CHECK);
    exit;
}

function fail(string $msg, int $code = 400): never {
    respond(['error' => $msg], $code);
}

function body(): array {
    return json_decode(file_get_contents('php://input'), true) ?: [];
}

function authUser(?string $role = null): array {
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    $token = trim(preg_replace('/^Bearer\s+/i', '', $h));
    $u = $token ? q('SELECT id, name, phone, role FROM users WHERE api_token = ?', [$token])->fetch() : null;
    if (!$u) fail('Unauthorized', 401);
    if ($role && $u['role'] !== $role) fail('Forbidden', 403);
    return $u;
}

function requireAdmin(): void {
    global $CONFIG;
    if (!hash_equals($CONFIG['admin_key'], $_SERVER['HTTP_X_ADMIN_KEY'] ?? '')) fail('Forbidden', 403);
}

// Name of the service area containing the point, or null if outside all of them.
function serviceArea(float $lat, float $lng): ?string {
    global $CONFIG;
    foreach ($CONFIG['areas'] as $a)
        if (haversineKm($lat, $lng, $a['lat'], $a['lng']) <= $a['radius_km']) return $a['name'];
    return null;
}

function areaNames(): string {
    global $CONFIG;
    return implode(', ', array_column($CONFIG['areas'], 'name'));
}

// Fails unless both points are inside a service area.
function requireServiceable(array $pickup, array $drop): void {
    foreach (['Pickup' => $pickup, 'Drop' => $drop] as $label => $pt) {
        if (!is_numeric($pt['lat'] ?? null) || !is_numeric($pt['lng'] ?? null)) fail('Pickup and drop required');
        if (!serviceArea($pt['lat'], $pt['lng'])) fail("$label location is outside our service area (" . areaNames() . ')');
    }
}

function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float {
    $r = fn($d) => deg2rad($d);
    $a = sin($r($lat2 - $lat1) / 2) ** 2 + cos($r($lat1)) * cos($r($lat2)) * sin($r($lng2 - $lng1) / 2) ** 2;
    return 6371 * 2 * asin(sqrt($a));
}

// Road distance is roughly 1.3x straight-line distance.
function estimateFare(string $type, array $pickup, array $drop): array {
    global $CONFIG;
    $km = round(haversineKm($pickup['lat'], $pickup['lng'], $drop['lat'], $drop['lng']) * 1.3, 2);
    $rate = $CONFIG['rates'][$type];
    return ['distanceKm' => $km, 'fare' => (int) round($rate['base'] + $rate['perKm'] * $km)];
}

// Haversine distance in km as an SQL expression; params are column names or '?' placeholders.
function sqlNear(string $la1, string $ln1, string $la2, string $ln2): string {
    return "(6371 * ACOS(LEAST(1, COS(RADIANS($la1)) * COS(RADIANS($la2)) * COS(RADIANS($ln2) - RADIANS($ln1)) + SIN(RADIANS($la1)) * SIN(RADIANS($la2)))))";
}

function getRide(int $id): array {
    return q('SELECT * FROM rides WHERE id = ?', [$id])->fetch();
}

// Active offers for an audience ('customer' or 'driver'), valid today.
function activeOffers(string $audience): array {
    return q("SELECT id, title, description, audience, code, discount_type, discount_value, max_discount, min_fare, valid_to
              FROM offers
              WHERE is_active = 1 AND audience IN (?, 'both')
                AND (valid_from IS NULL OR valid_from <= CURDATE())
                AND (valid_to IS NULL OR valid_to >= CURDATE())
              ORDER BY id DESC", [$audience])->fetchAll();
}

// Discount in rupees for a promo code on a fare. Returns ['error' => msg] if the code can't be used.
function applyPromo(string $code, int $fare): array {
    $o = q("SELECT * FROM offers WHERE code = ? AND is_active = 1 AND audience IN ('customer','both')
              AND (valid_from IS NULL OR valid_from <= CURDATE())
              AND (valid_to IS NULL OR valid_to >= CURDATE())", [strtoupper(trim($code))])->fetch();
    if (!$o || !$o['discount_type']) return ['error' => 'Invalid or expired promo code'];
    if ($fare < $o['min_fare']) return ['error' => 'Minimum fare for this code is ₹' . (float) $o['min_fare']];
    $d = $o['discount_type'] === 'percent' ? $fare * $o['discount_value'] / 100 : $o['discount_value'];
    if ($o['max_discount'] !== null) $d = min($d, $o['max_discount']);
    return ['code' => $o['code'], 'discount' => (int) round(min($d, $fare))];
}
