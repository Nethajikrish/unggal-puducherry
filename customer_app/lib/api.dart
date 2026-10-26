import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Android emulator reaches the PC's XAMPP at 10.0.2.2. On a real phone use the PC's LAN IP,
// e.g. http://192.168.1.10/nama-puducherry/api
//const baseUrl = 'http://10.0.2.2/nama-puducherry/api';

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
      _save(await _req('POST', '/auth/login', {'phone': phone, 'password': password, 'role': 'customer'}));

  static Future<void> register(String name, String phone, String password) async =>
      _save(await _req('POST', '/auth/register',
          {'name': name, 'phone': phone, 'password': password, 'role': 'customer'}));

  static Future<List<dynamic>> nearbyDrivers(double lat, double lng) async =>
      await _req('GET', '/drivers/nearby?lat=$lat&lng=$lng');

  static Future<List<dynamic>> fares(Map<String, dynamic> pickup, Map<String, dynamic> drop,
          {String? promoCode}) async =>
      await _req('POST', '/fare',
          {'pickup': pickup, 'drop': drop, if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode});

  static Future<Map<String, dynamic>> bookRide(
          String vehicleType, Map<String, dynamic> pickup, Map<String, dynamic> drop,
          {String? promoCode}) async =>
      await _req('POST', '/rides', {
        'vehicleType': vehicleType,
        'pickup': pickup,
        'drop': drop,
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
      });

  static Future<List<dynamic>> serviceAreas() async => await _req('GET', '/service-areas');

  static Future<List<dynamic>> offers() async => await _req('GET', '/offers');

  static Future<Map<String, dynamic>?> currentRide() async => await _req('GET', '/rides/current');

  static Future<List<dynamic>> history() async => await _req('GET', '/rides/history');

  static Future<void> cancelRide(int id) async => await _req('POST', '/rides/$id/cancel');
}
