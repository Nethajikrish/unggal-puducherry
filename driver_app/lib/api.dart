import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Android emulator reaches the PC's XAMPP at 10.0.2.2. On a real phone use the PC's LAN IP,
// e.g. http://192.168.1.10/nama-puducherry/api
const baseUrl = 'http://localhost/nama-puducherry/api';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static String? token;
  static Map<String, dynamic>? user;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    final u = p.getString('user');
    user = u == null ? null : jsonDecode(u);
  }

  static Future<void> _save(Map<String, dynamic> res) async {
    token = res['token'];
    user = res['user'];
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token!);
    await p.setString('user', jsonEncode(user));
  }

  static Future<void> logout() async {
    token = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.clear();
  }

  static Future<dynamic> _req(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 15)));
    final data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      if (res.statusCode == 401) await logout();
      throw ApiException((data is Map ? data['error'] : null) ?? 'Request failed (${res.statusCode})');
    }
    return data;
  }

  static Future<void> login(String phone, String password) async =>
      _save(await _req('POST', '/auth/login', {'phone': phone, 'password': password, 'role': 'driver'}));

  static Future<void> register({
    required String name,
    required String phone,
    required String password,
    required String vehicleType,
    required String vehicleNumber,
    required String licenseNumber,
  }) async =>
      _save(await _req('POST', '/auth/register', {
        'name': name,
        'phone': phone,
        'password': password,
        'role': 'driver',
        'vehicleType': vehicleType,
        'vehicleNumber': vehicleNumber,
        'licenseNumber': licenseNumber,
      }));

  static Future<Map<String, dynamic>> me() async => await _req('GET', '/driver/me');

  static Future<void> sendLocation(double lat, double lng, {bool? isOnline}) async =>
      await _req('POST', '/driver/location',
          {'lat': lat, 'lng': lng, if (isOnline != null) 'isOnline': isOnline});

  static Future<List<dynamic>> requests() async => await _req('GET', '/driver/requests');

  static Future<Map<String, dynamic>?> currentRide() async => await _req('GET', '/rides/current');

  static Future<void> accept(int id) async => await _req('POST', '/rides/$id/accept');

  static Future<void> setStatus(int id, String status) async =>
      await _req('POST', '/rides/$id/status', {'status': status});

  static Future<void> cancel(int id) async => await _req('POST', '/rides/$id/cancel');

  static Future<List<dynamic>> offers() async => await _req('GET', '/offers');

  static Future<List<dynamic>> history() async => await _req('GET', '/rides/history');
}
