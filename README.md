# Nama Puducherry – Cab Booking

- `api/` – PHP + MySQL REST API (runs on XAMPP)
- `customer_app/` – Flutter customer app
- `driver_app/` – Flutter driver app

## 1. Backend
1. Start Apache and MySQL in XAMPP.
2. Import `api/schema.sql` (phpMyAdmin → Import, or `mysql -u root < api/schema.sql`).
3. Edit `api/config.php` (DB password, `admin_key`).
4. Check: http://localhost/nama-puducherry/api/health → `{"ok":true}`

Upgrading an existing database? Import `api/migrations/002_offers.sql` (adds offers + ride discounts).

Admin app: http://localhost/nama-puducherry/admin/ (sign in with `admin_key` from `api/config.php`).
Tabs: Dashboard (daily rides, revenue, drivers online, 14-day chart), Drivers (approve/reject),
Rides (by day/status), Customers, Offers (promo codes for customers, incentives for drivers).

Drivers register as `pending`. Approve them in the admin app, or by command line:
```
curl -X PATCH http://localhost/nama-puducherry/api/admin/drivers/2 \
  -H "X-Admin-Key: change-admin-key" -H "Content-Type: application/json" -d '{"status":"approved"}'
```
List pending: `GET /api/admin/drivers?status=pending` with the same header.

## 2. Flutter apps
Install Flutter, then in each app folder:
```
flutter create --org in.nama.puducherry .
flutter pub get
```
Add permissions after `flutter create`:
- Android `android/app/src/main/AndroidManifest.xml` (inside `<manifest>`):
  `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, and
  `android:usesCleartextTraffic="true"` on `<application>` (dev only, for http).
  Driver app also needs a `<queries>` entry for `https` VIEW intents (url_launcher).
- iOS `Info.plist`: `NSLocationWhenInUseUsageDescription`.

Set `baseUrl` in `lib/api.dart` (emulator: `10.0.2.2`; real phone: your PC's LAN IP).
Run: `flutter run`.

## How it works
Customer taps destination → sees fare per vehicle type → books. Online approved drivers of that
vehicle type within 5 km see the request (apps poll every 4 s), first to accept wins.
Driver GPS is sent every 4 s; the customer sees the cab move. Pickup and drop must each be inside a service area (Puducherry, Cuddalore, Villupuram, Tindivanam –
edit `areas` in `api/config.php`); trips between towns are allowed.

## Next steps
Payments, OTP login, push notifications (FCM), place search/geocoding, ratings, admin web panel, HTTPS.
