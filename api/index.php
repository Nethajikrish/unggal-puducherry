<?php
require __DIR__ . '/lib.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Admin-Key');
header('Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') exit;

$method = $_SERVER['REQUEST_METHOD'];
$path = '/' . trim(substr(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH), strlen(dirname($_SERVER['SCRIPT_NAME']))), '/');
$in = body();

try {
    route($method, $path, $in);
    fail('Not found', 404);
} catch (PDOException $e) {
    error_log($e->getMessage());
    fail('Server error', 500);
}

function route(string $method, string $path, array $in): void {
    global $CONFIG;
    $m = fn(string $verb, string $pattern, &$args = null) =>
        $method === $verb && preg_match('#^' . $pattern . '$#', $path, $args);

    // ---------- Auth ----------
    if ($m('POST', '/auth/register')) {
        $name = trim($in['name'] ?? '');
        $phone = $in['phone'] ?? '';
        $role = $in['role'] ?? '';
        if (!$name || !preg_match('/^\d{10}$/', $phone) || strlen($in['password'] ?? '') < 6 || !in_array($role, ['customer', 'driver'], true))
            fail('Invalid name, 10-digit phone, password (min 6) or role');
        if ($role === 'driver' && (!isset($CONFIG['rates'][$in['vehicleType'] ?? '']) || empty($in['vehicleNumber']) || empty($in['licenseNumber'])))
            fail('Vehicle type, vehicle number and license number required');
        if (q('SELECT 1 FROM users WHERE phone = ? AND role = ?', [$phone, $role])->fetch())
            fail('Phone already registered', 409);

        $token = bin2hex(random_bytes(32));
        db()->beginTransaction();
        q('INSERT INTO users (name, phone, password_hash, role, api_token) VALUES (?,?,?,?,?)',
            [$name, $phone, password_hash($in['password'], PASSWORD_DEFAULT), $role, $token]);
        $id = (int) db()->lastInsertId();
        if ($role === 'driver')
            q('INSERT INTO drivers (user_id, vehicle_type, vehicle_number, license_number) VALUES (?,?,?,?)',
                [$id, $in['vehicleType'], strtoupper($in['vehicleNumber']), $in['licenseNumber']]);
        db()->commit();
        respond(['token' => $token, 'user' => ['id' => $id, 'name' => $name, 'phone' => $phone, 'role' => $role]]);
    }

    if ($m('POST', '/auth/login')) {
        $u = q('SELECT * FROM users WHERE phone = ? AND role = ?', [$in['phone'] ?? '', $in['role'] ?? ''])->fetch();
        if (!$u || !password_verify($in['password'] ?? '', $u['password_hash'])) fail('Wrong phone or password', 401);
        $token = bin2hex(random_bytes(32));
        q('UPDATE users SET api_token = ? WHERE id = ?', [$token, $u['id']]);
        respond(['token' => $token, 'user' => ['id' => $u['id'], 'name' => $u['name'], 'phone' => $u['phone'], 'role' => $u['role']]]);
    }

    // ---------- Admin: approve drivers (send header X-Admin-Key) ----------
    if ($m('GET', '/admin/drivers')) {
        requireAdmin();
        respond(q("SELECT u.id, u.name, u.phone, u.created_at, d.vehicle_type, d.vehicle_number, d.license_number, d.status, d.is_online,
                          (SELECT COUNT(*) FROM rides r WHERE r.driver_id = u.id AND r.status = 'completed') AS rides_done
                   FROM drivers d JOIN users u ON u.id = d.user_id
                   WHERE d.status = COALESCE(?, d.status) ORDER BY u.id DESC", [$_GET['status'] ?? null])->fetchAll());
    }
    if ($m('GET', '/admin/customers')) {
        requireAdmin();
        respond(q("SELECT u.id, u.name, u.phone, u.created_at,
                          (SELECT COUNT(*) FROM rides r WHERE r.customer_id = u.id AND r.status = 'completed') AS rides_done
                   FROM users u WHERE u.role = 'customer' ORDER BY u.id DESC LIMIT 500")->fetchAll());
    }

    // Dashboard numbers for one day (?date=YYYY-MM-DD, default today) plus the last 14 days.
    if ($m('GET', '/admin/stats')) {
        requireAdmin();
        $date = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['date'] ?? '') ? $_GET['date'] : date('Y-m-d');
        $day = q("SELECT COUNT(*) AS total,
                         COALESCE(SUM(status = 'completed'), 0) AS completed,
                         COALESCE(SUM(status = 'cancelled'), 0) AS cancelled,
                         COALESCE(SUM(status IN ('requested','accepted','arrived','started')), 0) AS active,
                         COALESCE(SUM(CASE WHEN status = 'completed' THEN fare - discount END), 0) AS revenue,
                         COALESCE(SUM(CASE WHEN status = 'completed' THEN discount END), 0) AS discounts
                  FROM rides WHERE DATE(created_at) = ?", [$date])->fetch();
        $totals = q("SELECT
                       (SELECT COUNT(*) FROM users WHERE role = 'customer') AS customers,
                       (SELECT COUNT(*) FROM drivers WHERE status = 'approved') AS drivers_approved,
                       (SELECT COUNT(*) FROM drivers WHERE status = 'pending') AS drivers_pending,
                       (SELECT COUNT(*) FROM drivers WHERE is_online = 1 AND status = 'approved'
                          AND location_updated_at > NOW() - INTERVAL 2 MINUTE) AS drivers_online")->fetch();
        $series = q("SELECT DATE(created_at) AS day, COUNT(*) AS rides,
                            COALESCE(SUM(CASE WHEN status = 'completed' THEN fare - discount END), 0) AS revenue
                     FROM rides WHERE created_at >= CURDATE() - INTERVAL 13 DAY
                     GROUP BY DATE(created_at) ORDER BY day")->fetchAll();
        respond(['date' => $date, 'day' => $day, 'totals' => $totals, 'series' => $series]);
    }

    // Rides for one day, optionally filtered by status.
    if ($m('GET', '/admin/rides')) {
        requireAdmin();
        $date = preg_match('/^\d{4}-\d{2}-\d{2}$/', $_GET['date'] ?? '') ? $_GET['date'] : date('Y-m-d');
        respond(q("SELECT r.id, r.created_at, r.status, r.vehicle_type, r.distance_km, r.fare, r.discount, r.offer_code,
                          cu.name AS customer_name, cu.phone AS customer_phone,
                          du.name AS driver_name, du.phone AS driver_phone
                   FROM rides r JOIN users cu ON cu.id = r.customer_id LEFT JOIN users du ON du.id = r.driver_id
                   WHERE DATE(r.created_at) = ? AND r.status = COALESCE(?, r.status)
                   ORDER BY r.id DESC", [$date, ($_GET['status'] ?? '') ?: null])->fetchAll());
    }

    // Offers: customer promo codes (discount) and driver/both announcements.
    if ($m('GET', '/admin/offers')) {
        requireAdmin();
        respond(q('SELECT * FROM offers ORDER BY id DESC')->fetchAll());
    }
    if ($m('POST', '/admin/offers') || $m('PATCH', '/admin/offers/(\d+)', $a)) {
        requireAdmin();
        $title = trim($in['title'] ?? '');
        $aud = $in['audience'] ?? 'customer';
        $code = strtoupper(trim($in['code'] ?? '')) ?: null;
        $type = ($in['discountType'] ?? '') ?: null;
        $val = is_numeric($in['discountValue'] ?? null) ? (float) $in['discountValue'] : null;
        if (!$title) fail('Title required');
        if (!in_array($aud, ['customer', 'driver', 'both'], true)) fail('Bad audience');
        if ($code && !preg_match('/^[A-Z0-9]{3,20}$/', $code)) fail('Code must be 3-20 letters/numbers');
        if ($type && (!in_array($type, ['percent', 'flat'], true) || !$val || $val <= 0 || ($type === 'percent' && $val > 100)))
            fail('Bad discount');
        if ($type && !$code) fail('A discount offer needs a promo code');
        $vals = [$title, trim($in['description'] ?? '') ?: null, $aud, $code, $type, $type ? $val : null,
                 is_numeric($in['maxDiscount'] ?? null) ? $in['maxDiscount'] : null,
                 is_numeric($in['minFare'] ?? null) ? $in['minFare'] : 0,
                 ($in['validFrom'] ?? '') ?: null, ($in['validTo'] ?? '') ?: null, (int) ($in['isActive'] ?? 1)];
        try {
            if (isset($a[1])) {
                q('UPDATE offers SET title=?, description=?, audience=?, code=?, discount_type=?, discount_value=?, max_discount=?,
                   min_fare=?, valid_from=?, valid_to=?, is_active=? WHERE id=?', [...$vals, $a[1]]);
                respond(['ok' => true]);
            }
            q('INSERT INTO offers (title, description, audience, code, discount_type, discount_value, max_discount, min_fare, valid_from, valid_to, is_active)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)', $vals);
            respond(['id' => (int) db()->lastInsertId()]);
        } catch (PDOException $e) {
            if ($e->getCode() === '23000') fail('Promo code already exists', 409);
            throw $e;
        }
    }
    if ($m('DELETE', '/admin/offers/(\d+)', $a)) {
        requireAdmin();
        q('DELETE FROM offers WHERE id = ?', [$a[1]]);
        respond(['ok' => true]);
    }
    if ($m('PATCH', '/admin/drivers/(\d+)', $a)) {
        requireAdmin();
        if (!in_array($in['status'] ?? '', ['approved', 'rejected'], true)) fail('Bad status');
        q('UPDATE drivers SET status = ? WHERE user_id = ?', [$in['status'], $a[1]]);
        respond(['ok' => true]);
    }

    // ---------- Driver ----------
    if ($m('GET', '/driver/me')) {
        $u = authUser('driver');
        respond(q('SELECT u.name, u.phone, d.* FROM drivers d JOIN users u ON u.id = d.user_id WHERE d.user_id = ?', [$u['id']])->fetch());
    }

    if ($m('POST', '/driver/location')) {
        $u = authUser('driver');
        if (!is_numeric($in['lat'] ?? null) || !is_numeric($in['lng'] ?? null)) fail('lat/lng required');
        $online = array_key_exists('isOnline', $in) ? (int) (bool) $in['isOnline'] : null;
        $d = q('SELECT status FROM drivers WHERE user_id = ?', [$u['id']])->fetch();
        if ($online && $d['status'] !== 'approved') fail('Account not approved yet', 403);
        q('UPDATE drivers SET lat = ?, lng = ?, location_updated_at = NOW(), is_online = COALESCE(?, is_online) WHERE user_id = ?',
            [$in['lat'], $in['lng'], $online, $u['id']]);
        respond(['ok' => true]);
    }

    // Open requests near this online driver, matching their vehicle type.
    if ($m('GET', '/driver/requests')) {
        $u = authUser('driver');
        $near = sqlNear('r.pickup_lat', 'r.pickup_lng', 'd.lat', 'd.lng');
        respond(q("SELECT r.* FROM rides r JOIN drivers d ON d.user_id = ? AND d.vehicle_type = r.vehicle_type
                   WHERE r.status = 'requested' AND d.is_online = 1 AND d.status = 'approved' AND $near <= ?
                   ORDER BY r.id DESC", [$u['id'], $CONFIG['nearby_km']])->fetchAll());
    }

    // ---------- Customer ----------
    if ($m('GET', '/drivers/nearby')) {
        authUser('customer');
        $near = sqlNear('?', '?', 'lat', 'lng');
        respond(q("SELECT user_id AS id, vehicle_type, lat, lng FROM drivers
                   WHERE is_online = 1 AND status = 'approved' AND location_updated_at > NOW() - INTERVAL 2 MINUTE
                     AND $near <= ?", [(float) ($_GET['lat'] ?? 0), (float) ($_GET['lng'] ?? 0), $CONFIG['nearby_km']])->fetchAll());
    }

    if ($m('POST', '/fare')) {
        authUser('customer');
        requireServiceable($in['pickup'] ?? [], $in['drop'] ?? []);
        $out = [];
        foreach (array_keys($CONFIG['rates']) as $t) {
            $row = ['vehicleType' => $t] + estimateFare($t, $in['pickup'], $in['drop']) + ['discount' => 0];
            if (!empty($in['promoCode'])) {
                $p = applyPromo($in['promoCode'], $row['fare']);
                if (isset($p['error'])) $row['promoError'] = $p['error'];
                else $row['discount'] = $p['discount'];
            }
            $row['payable'] = $row['fare'] - $row['discount'];
            $out[] = $row;
        }
        respond($out);
    }

    // Cities we serve (used by the app for quick picks).
    if ($m('GET', '/service-areas')) respond($CONFIG['areas']);

    // Active offers for the logged-in customer or driver.
    if ($m('GET', '/offers')) {
        $u = authUser();
        respond(activeOffers($u['role']));
    }

    if ($m('POST', '/rides')) {
        $u = authUser('customer');
        $type = $in['vehicleType'] ?? '';
        $p = $in['pickup'] ?? [];
        $d = $in['drop'] ?? [];
        if (!isset($CONFIG['rates'][$type])) fail('Bad vehicle type');
        requireServiceable($p, $d);
        if (q("SELECT 1 FROM rides WHERE customer_id = ? AND status IN ('requested','accepted','arrived','started')", [$u['id']])->fetch())
            fail('You already have an active ride', 409);

        $f = estimateFare($type, $p, $d);
        $promo = ['code' => null, 'discount' => 0];
        if (!empty($in['promoCode'])) {
            $promo = applyPromo($in['promoCode'], $f['fare']);
            if (isset($promo['error'])) fail($promo['error']);
        }
        q('INSERT INTO rides (customer_id, vehicle_type, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, distance_km, fare, discount, offer_code)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
            [$u['id'], $type, $p['lat'], $p['lng'], $p['address'] ?? null, $d['lat'], $d['lng'], $d['address'] ?? null,
             $f['distanceKm'], $f['fare'], $promo['discount'], $promo['code']]);
        respond(getRide((int) db()->lastInsertId()));
    }

    // Current active ride for either role, with the other party's details and live driver position.
    if ($m('GET', '/rides/current')) {
        $u = authUser();
        $col = $u['role'] === 'customer' ? 'customer_id' : 'driver_id';
        $ride = q("SELECT r.*, cu.name AS customer_name, cu.phone AS customer_phone,
                          du.name AS driver_name, du.phone AS driver_phone,
                          d.vehicle_number, d.lat AS driver_lat, d.lng AS driver_lng
                   FROM rides r JOIN users cu ON cu.id = r.customer_id
                   LEFT JOIN users du ON du.id = r.driver_id LEFT JOIN drivers d ON d.user_id = r.driver_id
                   WHERE r.$col = ? AND r.status IN ('requested','accepted','arrived','started')", [$u['id']])->fetch();
        respond($ride ?: null);
    }

    if ($m('GET', '/rides/history')) {
        $u = authUser();
        $col = $u['role'] === 'customer' ? 'customer_id' : 'driver_id';
        respond(q("SELECT * FROM rides WHERE $col = ? ORDER BY id DESC LIMIT 50", [$u['id']])->fetchAll());
    }

    // ---------- Ride lifecycle ----------
    if ($m('POST', '/rides/(\d+)/accept', $a)) {
        $u = authUser('driver');
        if (q("SELECT 1 FROM rides WHERE driver_id = ? AND status IN ('accepted','arrived','started')", [$u['id']])->fetch())
            fail('Finish your current ride first', 409);
        // Atomic: only one driver can win the request.
        $st = q("UPDATE rides SET driver_id = ?, status = 'accepted' WHERE id = ? AND status = 'requested'", [$u['id'], $a[1]]);
        if (!$st->rowCount()) fail('Ride already taken or cancelled', 409);
        respond(getRide((int) $a[1]));
    }

    if ($m('POST', '/rides/(\d+)/status', $a)) {
        $u = authUser('driver');
        $from = ['arrived' => 'accepted', 'started' => 'arrived', 'completed' => 'started'][$in['status'] ?? ''] ?? null;
        if (!$from) fail('Bad status');
        $st = q('UPDATE rides SET status = ? WHERE id = ? AND driver_id = ? AND status = ?', [$in['status'], $a[1], $u['id'], $from]);
        if (!$st->rowCount()) fail('Invalid status change', 409);
        respond(getRide((int) $a[1]));
    }

    if ($m('POST', '/rides/(\d+)/cancel', $a)) {
        $u = authUser();
        $col = $u['role'] === 'customer' ? 'customer_id' : 'driver_id';
        $ride = q("SELECT * FROM rides WHERE id = ? AND $col = ?", [$a[1], $u['id']])->fetch();
        if (!$ride || !in_array($ride['status'], ['requested', 'accepted', 'arrived'], true)) fail('Cannot cancel this ride', 409);
        // A driver cancelling re-opens the request for other drivers.
        if ($u['role'] === 'driver') q("UPDATE rides SET driver_id = NULL, status = 'requested' WHERE id = ?", [$ride['id']]);
        else q("UPDATE rides SET status = 'cancelled' WHERE id = ?", [$ride['id']]);
        respond(getRide((int) $ride['id']));
    }

    if ($m('GET', '/health')) respond(['ok' => true]);
}
