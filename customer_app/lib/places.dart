import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'api.dart';

class Place {
  final String name;
  final LatLng point;
  const Place(this.name, this.point);
}

// Destinations the customer picked this session, newest first (shown as "recent" in the sheet).
final List<Place> recentPlaces = [];

void rememberPlace(Place p) {
  recentPlaces.removeWhere((r) => r.name == p.name);
  recentPlaces.insert(0, p);
  if (recentPlaces.length > 5) recentPlaces.removeLast();
}

/// Pick a pickup or drop place: quick city picks, search by name (OpenStreetMap Nominatim),
/// and optionally "my current location". Pops a [Place]; the string 'gps' means use GPS.
class PlaceSearchScreen extends StatefulWidget {
  final String title;
  final bool allowCurrentLocation;
  const PlaceSearchScreen({super.key, required this.title, this.allowCurrentLocation = false});
  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<Place> _results = [];
  List<dynamic> _areas = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.serviceAreas().then((a) {
      if (mounted) setState(() => _areas = a);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) return setState(() => _results = []);
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Search only around our service towns (Cuddalore - Tindivanam - Villupuram - Puducherry).
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': q,
        'countrycodes': 'in',
        'limit': '8',
        'viewbox': '79.30,12.50,80.05,11.55',
        'bounded': '1',
      });
      final res = await http.get(uri, headers: {
        'Accept-Language': 'en',
        if (!kIsWeb) 'User-Agent': 'NamaPuducherryCabs/1.0',
      }).timeout(const Duration(seconds: 15));
      final list = jsonDecode(res.body) as List;
      if (!mounted || _text.text.trim() != q) return;
      setState(() => _results = [
            for (final r in list) Place(r['display_name'], LatLng(double.parse(r['lat']), double.parse(r['lon']))),
          ]);
    } catch (e) {
      if (mounted) setState(() => _error = 'Search failed. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Opens the map picker; if the customer confirms a point, this screen pops with it.
  Future<void> _pickOnMap() async {
    final p = await Navigator.push<Place>(context, MaterialPageRoute(builder: (_) => const MapPickScreen()));
    if (p != null && mounted) Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _text,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search a place, street or landmark',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
            ),
          ),
          if (widget.allowCurrentLocation)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Select on map'),
                    onPressed: _pickOnMap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_road),
                    label: const Text('Add stops'),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Multiple stops are not supported yet'))),
                  ),
                ),
              ]),
            ),
          if (widget.allowCurrentLocation)
            ListTile(
              leading: const Icon(Icons.my_location, color: Colors.blue),
              title: const Text('Use my current location'),
              onTap: () => Navigator.pop(context, 'gps'),
            ),
          if (_areas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final a in _areas)
                    ActionChip(
                      avatar: const Icon(Icons.location_city, size: 18),
                      label: Text(a['name']),
                      onPressed: () => Navigator.pop(context, Place(a['name'], LatLng(a['lat'] * 1.0, a['lng'] * 1.0))),
                    ),
                ],
              ),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_results.isEmpty && _text.text.trim().length >= 3 && !_loading && _error == null)
            const Padding(padding: EdgeInsets.all(16), child: Text('No places found. Try another name, or pick on the map.')),
          if (_text.text.trim().isEmpty)
            for (final p in recentPlaces)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.favorite_border),
                onTap: () => Navigator.pop(context, p),
              ),
          for (final p in _results)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.favorite_border),
              onTap: () => Navigator.pop(context, p),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Tip: you can also tap the map to drop a pin for the destination, or long-press for pickup.',
                style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

/// Drag the map under a fixed centre pin, then confirm. Pops a [Place] for the centre point.
class MapPickScreen extends StatefulWidget {
  const MapPickScreen({super.key});
  @override
  State<MapPickScreen> createState() => _MapPickScreenState();
}

class _MapPickScreenState extends State<MapPickScreen> {
  static const _puducherry = LatLng(11.9416, 79.8083);
  LatLng _center = _puducherry;
  bool _busy = false;

  // Name the point with OpenStreetMap reverse geocoding; fall back to coordinates.
  Future<String> _nameFor(LatLng p) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '${p.latitude}',
        'lon': '${p.longitude}',
      });
      final res = await http.get(uri, headers: {
        'Accept-Language': 'en',
        if (!kIsWeb) 'User-Agent': 'NamaPuducherryCabs/1.0',
      }).timeout(const Duration(seconds: 10));
      final name = (jsonDecode(res.body) as Map)['display_name'];
      if (name is String && name.isNotEmpty) return name;
    } catch (_) {}
    return 'Pinned location (${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)})';
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final name = await _nameFor(_center);
    if (mounted) Navigator.pop(context, Place(name, _center));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select on map')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: (camera, _) => _center = camera.center,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'in.nama.puducherry.customer',
              ),
            ],
          ),
          // Fixed centre pin: the map moves under it, so the pin's tip marks the pickup.
          const IgnorePointer(child: Icon(Icons.location_on, color: Colors.red, size: 44)),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(_busy ? 'Locating…' : 'Confirm pickup point'),
            ),
          ),
        ],
      ),
    );
  }
}
