import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _map = MapController();
  Timer? _timer;
  Map<String, dynamic>? _me; // driver profile incl. approval status
  Map<String, dynamic>? _ride;
  List<dynamic> _requests = [];
  LatLng? _pos;
  bool _online = false;
  bool _ticking = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _loadProfile() async {
    try {
      final me = await Api.me();
      if (mounted) setState(() {
        _me = me;
        _online = me['is_online'] == 1;
      });
    } catch (e) {
      if (Api.token == null) widget.onLogout();
    }
  }

  Future<bool> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    return perm != LocationPermission.denied && perm != LocationPermission.deniedForever;
  }

  // Every few seconds: report GPS position, then refresh the active ride / nearby requests.
  Future<void> _tick() async {
    if (_ticking || _me == null) return;
    _ticking = true;
    try {
      if (_me!['status'] != 'approved') return _loadProfile();
      if (await _ensurePermission()) {
        final p = await Geolocator.getCurrentPosition();
        _pos = LatLng(p.latitude, p.longitude);
        if (_online) await Api.sendLocation(p.latitude, p.longitude);
      }
      final ride = await Api.currentRide();
      final reqs = (_online && ride == null) ? await Api.requests() : <dynamic>[];
      if (mounted) setState(() {
        _ride = ride;
        _requests = reqs;
      });
    } catch (e) {
      if (Api.token == null) widget.onLogout();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _toggleOnline(bool v) async {
    try {
      if (!await _ensurePermission()) return _toast('Location permission is required');
      final p = await Geolocator.getCurrentPosition();
      _pos = LatLng(p.latitude, p.longitude);
      await Api.sendLocation(p.latitude, p.longitude, isOnline: v);
      setState(() => _online = v);
      _map.move(_pos!, 14);
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _act(Future<void> Function() fn) async {
    try {
      await fn();
      await _tick();
    } catch (e) {
      _toast(e);
      _tick();
    }
  }

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) _toast('Could not open maps');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_me == null ? 'Driver' : 'Hi, ${_me!['name']}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.card_giftcard),
            tooltip: 'Offers',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: _me == null ? const Center(child: CircularProgressIndicator()) : _body(),
    );
  }

  Widget _body() {
    final status = _me!['status'];
    if (status != 'approved') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status == 'pending' ? Icons.hourglass_top : Icons.block, size: 64),
              const SizedBox(height: 16),
              Text(
                status == 'pending'
                    ? 'Your registration is under review. You can go online once approved.'
                    : 'Your registration was rejected. Please contact support.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _loadProfile, child: const Text('Refresh')),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        SwitchListTile(
          title: Text(_online ? 'You are ONLINE' : 'You are OFFLINE'),
          subtitle: Text('${_me!['vehicle_type']} · ${_me!['vehicle_number']}'),
          value: _online,
          onChanged: _ride == null ? _toggleOnline : null,
        ),
        Expanded(child: _ride == null ? _requestList() : _activeRide()),
      ],
    );
  }

  Widget _requestList() {
    if (!_online) return const Center(child: Text('Go online to receive ride requests'));
    if (_requests.isEmpty) return const Center(child: Text('Waiting for ride requests nearby…'));
    return ListView(
      children: [
        for (final r in _requests)
          Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text('₹${r['fare']} · ${r['distance_km']} km'),
              subtitle: Text('Pickup ${r['pickup_lat'].toStringAsFixed(4)}, ${r['pickup_lng'].toStringAsFixed(4)}'),
              trailing: FilledButton(
                onPressed: () => _act(() => Api.accept(r['id'])),
                child: const Text('Accept'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _activeRide() {
    final r = _ride!;
    final status = r['status'] as String;
    final toPickup = status == 'accepted' || status == 'arrived';
    final target = toPickup ? LatLng(r['pickup_lat'], r['pickup_lng']) : LatLng(r['drop_lat'], r['drop_lng']);
    const next = {'accepted': 'arrived', 'arrived': 'started', 'started': 'completed'};
    const label = {'accepted': 'I have arrived', 'arrived': 'Start trip', 'started': 'Complete trip'};
    Marker pin(LatLng p, IconData i, Color c) => Marker(point: p, width: 40, height: 40, child: Icon(i, color: c, size: 36));

    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: _pos ?? target, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'in.nama.puducherry.driver',
              ),
              MarkerLayer(markers: [
                pin(LatLng(r['pickup_lat'], r['pickup_lng']), Icons.my_location, Colors.blue),
                pin(LatLng(r['drop_lat'], r['drop_lng']), Icons.location_on, Colors.red),
                if (_pos != null) pin(_pos!, Icons.local_taxi, Colors.orange),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(r['customer_name'] ?? 'Customer'),
                subtitle: Text('${r['customer_phone']} · ${toPickup ? 'Pickup' : 'Drop'}'),
                trailing: Text('₹${r['fare']}', style: Theme.of(context).textTheme.titleLarge),
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.navigation),
                    label: const Text('Navigate'),
                    onPressed: () => _navigate(target.latitude, target.longitude),
                  ),
                ),
                if (status != 'started') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _act(() => Api.cancel(r['id'])),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _act(() => Api.setStatus(r['id'], next[status]!)),
                child: Text(label[status]!),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offers & incentives')),
      body: FutureBuilder<List<dynamic>>(
        future: Api.offers(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Text('${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Text('No offers right now'));
          return ListView(
            children: [
              for (final o in s.data!)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ListTile(
                    leading: const Icon(Icons.card_giftcard, color: Colors.orange),
                    title: Text(o['title']),
                    subtitle: Text([
                      if (o['description'] != null) o['description'],
                      if (o['valid_to'] != null) 'Valid till ${o['valid_to']}',
                    ].join('\n')),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
