import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;

class Mainscreen extends StatefulWidget {
  const Mainscreen({super.key});

  @override
  State<Mainscreen> createState() => _MainscreenState();
}

class _MainscreenState extends State<Mainscreen> {
  late MapboxMap _mapboxMap;
  geo.Position? _currentPosition;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _customSuggestions = [
    {'name': 'Library', 'latitude': 6.8030, 'longitude': -1.0860},
    {'name': 'Cafeteria', 'latitude': 6.8050, 'longitude': -1.0840},
    {'name': 'Sports Complex', 'latitude': 6.8040, 'longitude': -1.0880},
  ];

  late PointAnnotationManager pointAnnotationManager;

  StreamSubscription? userpositionStream;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));
    _initializeLocation();
  }

  @override
  void dispose() {
    userpositionStream?.cancel();
    super.dispose();
  }

  // Handle selection of a suggestion and fly the camera to that location
  Future<void> _onSuggestionSelected(Map<String, dynamic> suggestion) async {
    final latitude = suggestion['latitude'];
    final longitude = suggestion['longitude'];

    _mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 1000),
    );

    // Optionally, add a marker for the selected suggestion
    final pointAnnotationOptions = PointAnnotationOptions(
      geometry: Point(coordinates: Position(longitude, latitude)),
      textField: suggestion['name'],
      textSize: 12.0,
    );
    await pointAnnotationManager.create(pointAnnotationOptions);

    // Clear the search input and suggestions
    setState(() {
      _searchController.text = suggestion['name'];
    });
  }

  // Initialize location services and set up location listener
  Future<void> _initializeLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (hasPermission) {
      userpositionStream = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        setState(() => _currentPosition = position);
        _mapboxMap.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(position.longitude, position.latitude),
            ),
            zoom: 15.0,
          ),
          MapAnimationOptions(duration: 300),
        );
      });
    }
  }

  // Request location permission if not granted
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled')),
      );
      return false;
    }

    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return false;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return false;
    }

    return true;
  }

  // Move the map camera to the user's current location
  Future<void> _getCurrentPosition({bool moveCamera = true}) async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      geo.Position position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      setState(() => _currentPosition = position);

      if (moveCamera && _mapboxMap != null) {
        await _mapboxMap.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(
                _currentPosition!.longitude,
                _currentPosition!.latitude,
              ),
            ),
            zoom: 15.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // Set up the Mapbox map and annotation manager
  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    pointAnnotationManager =
        await _mapboxMap.annotations.createPointAnnotationManager();

    await _getCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            MapWidget(
              key: const ValueKey("mapWidget"),
              onMapCreated: _onMapCreated,
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () => _getCurrentPosition(moveCamera: true),
                child: const Icon(Icons.my_location),
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search location",
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          // Optionally handle the search here
                        },
                      ),
                    ),
                  ),
                ),
                // Display custom suggestions below the search field
                Expanded(
                  child: ListView.builder(
                    itemCount: _customSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _customSuggestions[index];
                      return ListTile(
                        title: Text(suggestion['name']),
                        onTap: () => _onSuggestionSelected(suggestion),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
