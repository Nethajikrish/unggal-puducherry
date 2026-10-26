import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'api.dart';
import 'places.dart';

const _puducherry = LatLng(11.9416, 79.8083);
const _vehicleIcons = {
  'auto': Icons.electric_rickshaw,
  'hatchback': Icons.directions_car,
  'sedan': Icons.directions_car_filled,
  'suv': Icons.airport_shuttle,
};
const _statusText = {
  'requested': 'Looking for a nearby driver…',
  'accepted': 'Driver is on the way',
  'arrived': 'Driver has arrived',
  'started': 'Trip in progress',
};

class HomeScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _map = MapController();
  final _promo = TextEditingController();
  Timer? _timer;
  LatLng? _me; // GPS position
  LatLng? _pickup;
  LatLng? _drop;
  String _pickupLabel = 'Current location';
  String _dropLabel = '';
  bool _pickupIsGps = true;
  List<dynamic> _fares = [];
  String _vehicle = 'auto';
  List<dynamic> _drivers = [];
  Map<String, dynamic>? _ride;
  bool _busy = false;
  List<dynamic> _areas = [];

  @override
  void initState() {
    super.initState();
    _locate();
    _poll();
    Api.serviceAreas().then((a) {
      if (mounted) setState(() => _areas = a);
    }).catchError((_) {});
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return _toast('Location permission is needed to book a cab');
      }
      final p = await Geolocator.getCurrentPosition();
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        if (_pickupIsGps) _pickup = _me;
      });
      _map.move(_me!, 15);
    } catch (e) {
      _toast('Could not get your location: $e');
    }
  }

  Future<void> _poll() async {
    try {
      final ride = await Api.currentRide();
      List<dynamic> drivers = [];
      final near = _pickup ?? _me;
      if (ride == null && near != null) drivers = await Api.nearbyDrivers(near.latitude, near.longitude);
      if (mounted) setState(() {
        _ride = ride;
        _drivers = drivers;
      });
    } catch (e) {
      if (Api.token == null) widget.onLogout();
    }
  }

  Map<String, dynamic> _pt(LatLng p) => {'lat': p.latitude, 'lng': p.longitude};

  Future<void> _setDrop(LatLng p, [String label = 'Pinned location']) async {
    if (label != 'Pinned location') rememberPlace(Place(label, p));
    setState(() {
      _drop = p;
      _dropLabel = label;
    });
    _showTrip();
    await _loadFares();
  }

  Future<void> _setPickup(LatLng p, String label, {bool gps = false}) async {
    setState(() {
      _pickup = p;
      _pickupLabel = label;
      _pickupIsGps = gps;
    });
    _showTrip();
    await _loadFares();
    _poll();
  }

  // Zoom the map to show pickup and drop together.
  void _showTrip() {
    final pts = [if (_pickup != null) _pickup!, if (_drop != null) _drop!];
    if (pts.length == 2) {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(60)));
    } else if (pts.length == 1) {
      _map.move(pts.first, 14);
    }
  }

  Future<void> _choosePickup() async {
    final r = await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const PlaceSearchScreen(title: 'Pickup location', allowCurrentLocation: true)));
    if (r == 'gps') {
      if (_me == null) await _locate();
      if (_me != null) await _setPickup(_me!, 'Current location', gps: true);
    } else if (r is Place) {
      await _setPickup(r.point, r.name);
    }
  }

  Future<void> _chooseDrop() async {
    final r = await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const PlaceSearchScreen(title: 'Where to?')));
    if (r is Place) await _setDrop(r.point, r.name);
  }

  Future<void> _loadFares() async {
    if (_pickup == null || _drop == null) return;
    try {
      final f = await Api.fares(_pt(_pickup!), _pt(_drop!), promoCode: _promo.text.trim());
      if (!mounted) return;
      setState(() => _fares = f);
      final err = f.map((x) => x['promoError']).whereType<String>().toList();
      if (_promo.text.trim().isNotEmpty) {
        _toast(err.isNotEmpty && err.length == f.length ? err.first : 'Promo applied');
      }
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _openOffers() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const OffersScreen()));
    if (code != null) {
      _promo.text = code;
      await _loadFares();
    }
  }

  Future<void> _book() async {
    setState(() => _busy = true);
    try {
      final ride = await Api.bookRide(_vehicle, _pt(_pickup!), _pt(_drop!), promoCode: _promo.text.trim());
      setState(() {
        _ride = ride;
        _drop = null;
        _fares = [];
        _promo.clear();
      });
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await Api.cancelRide(_ride!['id']);
      setState(() => _ride = null);
    } catch (e) {
      _toast(e);
    }
  }

  List<Marker> _markers() {
    final m = <Marker>[];
    Marker pin(LatLng p, IconData i, Color c) =>
        Marker(point: p, width: 40, height: 40, child: Icon(i, color: c, size: 36));
    if (_ride != null) {
      m.add(pin(LatLng(_ride!['pickup_lat'], _ride!['pickup_lng']), Icons.my_location, Colors.blue));
      m.add(pin(LatLng(_ride!['drop_lat'], _ride!['drop_lng']), Icons.location_on, Colors.red));
      if (_ride!['driver_lat'] != null) {
        m.add(pin(LatLng(_ride!['driver_lat'], _ride!['driver_lng']), Icons.local_taxi, Colors.teal));
      }
    } else {
      if (_pickup != null) m.add(pin(_pickup!, Icons.my_location, Colors.blue));
      if (_drop != null) m.add(pin(_drop!, Icons.location_on, Colors.red));
      for (final d in _drivers) {
        m.add(pin(LatLng(d['lat'], d['lng']), _vehicleIcons[d['vehicle_type']] ?? Icons.local_taxi, Colors.teal));
      }
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book a cab'),
        actions: [
          IconButton(icon: const Icon(Icons.local_offer_outlined), onPressed: _openOffers),
          IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
          IconButton(icon: const Icon(Icons.logout), onPressed: widget.onLogout),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _puducherry,
              initialZoom: 13,
              onTap: _ride == null ? (_, p) => _setDrop(p) : null,
              onLongPress: _ride == null ? (_, p) => _setPickup(p, 'Pinned pickup') : null,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'in.nama.puducherry.customer',
              ),
              MarkerLayer(markers: _markers()),
            ],
          ),
          if (_pickup == null && _ride == null) _locationBanner(),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ride == null ? _bookingSheet() : _ridePanel(),
          ),
        ],
      ),
    );
  }

  // Shown until GPS or a manual pickup is known (mirrors the "can't find you" banner).
  Widget _locationBanner() {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.info_outline, color: Colors.redAccent),
            SizedBox(width: 10),
            Expanded(child: Text('Uh oh, we can\'t find you! Enter your pickup location for a smooth ride.')),
          ]),
        ),
      ),
    );
  }

  Widget _bookingSheet() {
    return Material(
      color: Colors.white,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              _searchPill(),
              const SizedBox(height: 8),
              if (_drop == null) ...[
                for (final p in recentPlaces.take(3))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.favorite_border),
                    onTap: () => _setDrop(p.point, p.name),
                  ),
                if (_areas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final a in _areas)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.location_city, size: 18),
                            label: Text(a['name']),
                            onPressed: () => _setDrop(LatLng(a['lat'] * 1.0, a['lng'] * 1.0), a['name']),
                          ),
                        ),
                    ]),
                  ),
                ],
              ] else
                _fareList(),
            ]),
          ),
        ),
      ),
    );
  }

  // Rapido-style search pill: pickup and drop summarised, tapping opens the search screens.
  Widget _searchPill() {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: _chooseDrop,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(children: [
          const Icon(Icons.search),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _dropLabel.isEmpty ? 'Where do you want to go?' : _dropLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pickupRow() {
    return InkWell(
      onTap: _choosePickup,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const Icon(Icons.my_location, color: Colors.blue, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_pickupLabel, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Widget _fareList() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pickupRow(),
      const Divider(height: 1),
      _bookingPanel(),
    ]);
  }

  Widget _bookingPanel() {
    if (_drop == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Choose your destination to see fares'),
      );
    }
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in _fares)
            RadioListTile<String>(
              value: f['vehicleType'],
              groupValue: _vehicle,
              onChanged: (v) => setState(() => _vehicle = v!),
              secondary: Icon(_vehicleIcons[f['vehicleType']]),
              title: Text(f['vehicleType'].toString().toUpperCase()),
              subtitle: Text(f['discount'] > 0
                  ? '${f['distanceKm']} km · ₹${f['payable']} (was ₹${f['fare']})'
                  : '${f['distanceKm']} km · ₹${f['fare']}'),
              dense: true,
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: EdgeInsets.zero,
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _promo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Promo code', isDense: true),
                onSubmitted: (_) => _loadFares(),
              ),
            ),
            TextButton(onPressed: _loadFares, child: const Text('Apply')),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || _fares.isEmpty ? null : _book,
              child: Text(_busy
                  ? 'Booking…'
                  : 'Book ${_vehicle.toUpperCase()} · ₹${_fares.firstWhere((f) => f['vehicleType'] == _vehicle, orElse: () => {'payable': '-'})['payable']}'),
            ),
          ),
        ],
    );
  }

  Widget _ridePanel() {
    final r = _ride!;
    final hasDriver = r['driver_name'] != null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_statusText[r['status']] ?? r['status'], style: Theme.of(context).textTheme.titleMedium),
          if (hasDriver)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(r['driver_name']),
              subtitle: Text('${r['vehicle_number']} · ${r['driver_phone']}'),
              trailing: Text('₹${r['fare'] - r['discount']}', style: Theme.of(context).textTheme.titleMedium),
            )
          else
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Fare ₹${r['fare'] - r['discount']}')),
          if (r['status'] != 'started')
            OutlinedButton(onPressed: _cancel, child: const Text('Cancel ride')),
        ],
      ),
    );
  }
}

class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offers')),
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
                    leading: const Icon(Icons.local_offer, color: Colors.teal),
                    title: Text(o['title']),
                    subtitle: Text([
                      if (o['description'] != null) o['description'],
                      if (o['valid_to'] != null) 'Valid till ${o['valid_to']}',
                    ].join('\n')),
                    isThreeLine: o['description'] != null && o['valid_to'] != null,
                    trailing: o['code'] == null
                        ? null
                        : OutlinedButton(onPressed: () => Navigator.pop(context, o['code']), child: Text('${o['code']}')),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My rides')),
      body: FutureBuilder<List<dynamic>>(
        future: Api.history(),
        builder: (context, s) {
          if (s.hasError) return Center(child: Text('${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Text('No rides yet'));
          return ListView(
            children: [
              for (final r in s.data!)
                ListTile(
                  leading: Icon(_vehicleIcons[r['vehicle_type']]),
                  title: Text('₹${r['fare'] - r['discount']} · ${r['distance_km']} km'),
                  subtitle: Text('${r['created_at']}'),
                  trailing: Text(r['status']),
                ),
            ],
          );
        },
      ),
    );
  }
}
