import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

class Mainscreen extends StatefulWidget {
  const Mainscreen({super.key});

  @override
  State<Mainscreen> createState() => _MainscreenState();
}

class _MainscreenState extends State<Mainscreen> {
  late MapboxMap _mapboxMap;
  geo.Position? _currentPosition;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _suggestions = [];

  late PointAnnotationManager pointAnnotationManager;
  late PolylineAnnotationManager polylineAnnotationManager;

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

  // Fetch location suggestions based on user input
  // Future<void> _getLocationSuggestions(String query) async {
  //   if (query.isEmpty || _searchController.text.isEmpty) {
  //     setState(() {
  //       _suggestions = [];
  //     });
  //     return;
  //   }

  //   final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
  //   final url = Uri.parse(
  //     'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$accessToken',
  //   );

  //   final response = await http.get(url);

  //   if (response.statusCode == 200) {
  //     final data = json.decode(response.body);
  //     setState(() {
  //       _suggestions = data['features'];
  //     });
  //   } else {
  //     ScaffoldMessenger.of(
  //       context,
  //     ).showSnackBar(SnackBar(content: Text('Error: ${response.statusCode}')));
  //   }
  // }

  // Add this method to handle searching based on the query
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty || _searchController.text.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$accessToken',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['features'].isNotEmpty) {
        setState(() {
          _suggestions = data['features'];
        });
        final feature = data['features'][0];
        final coordinates = feature['geometry']['coordinates'];
        final position = Position(coordinates[0], coordinates[1]);

        // Fly to the searched location

        // Optionally, add a marker for the searched location
        // final pointAnnotationOptions = PointAnnotationOptions(
        //   geometry: Point(coordinates: position),
        //   textField: feature['place_name'],
        //   textSize: 12.0,
        // );
        // await pointAnnotationManager.create(pointAnnotationOptions);

        // // Draw route from current location to searched destination
        // if (_currentPosition != null) {
        //   await _drawRouteFromCurrentToDestination(
        //     coordinates[1],
        //     coordinates[0],
        //   );
        // }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No results found')));
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${response.statusCode}')));
    }
  }

  // getting routes - fixed to return List<Position>
  Future<List<Position>> _getroute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/walking/$startLng,$startLat;$endLng,$endLat?geometries=geojson&access_token=$accessToken',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final route = data['routes'][0]['geometry']['coordinates'];
      List<Position> routePoints = [];
      for (var coordinate in route) {
        routePoints.add(Position(coordinate[0], coordinate[1]));
      }
      return routePoints;
    } else {
      throw Exception('Failed to load route: ${response.statusCode}');
    }
  }

  // create polyline on the map - fixed to use PolylineAnnotationManager
  Future<void> drawRoute(List<Position> routePoints) async {
    // Clear existing polylines first
    await polylineAnnotationManager.deleteAll();

    // Create polyline annotation options
    final polylineAnnotationOptions = PolylineAnnotationOptions(
      geometry: LineString(coordinates: routePoints),
      lineColor: Colors.blue.value, // Convert Color to int
      lineWidth: 5.0,
    );

    // Create the polyline on the map
    await polylineAnnotationManager.create(polylineAnnotationOptions);
  }

  // Method to draw route from current location to destination
  Future<void> _drawRouteFromCurrentToDestination(
    double destLat,
    double destLng,
  ) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current location not available')),
      );
      return;
    }

    try {
      // Get route points
      final routePoints = await _getroute(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        destLat,
        destLng,
      );

      // Draw the route on the map
      await drawRoute(routePoints);

      // Clear previous point annotations
      await pointAnnotationManager.deleteAll();

      // Start point marker
      await pointAnnotationManager.create(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(
              _currentPosition!.longitude,
              _currentPosition!.latitude,
            ),
          ),
          textField: "Start",
          textSize: 12.0,
        ),
      );

      // End point marker
      await pointAnnotationManager.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(destLng, destLat)),
          textField: "Destination",
          textSize: 12.0,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to draw route: $e')));
    }
  }

  // Handle selection of a suggestion and fly the camera to that location
  Future<void> _onSuggestionSelected(dynamic suggestion) async {
    final coordinates = suggestion['geometry']['coordinates'];
    final latitude = coordinates[1];
    final longitude = coordinates[0];

    _mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 1000),
    );

    // Clear previous annotations
    await pointAnnotationManager.deleteAll();

    // Add marker for the selected suggestion
    final pointAnnotationOptions = PointAnnotationOptions(
      geometry: Point(coordinates: Position(longitude, latitude)),
      textField: suggestion['place_name'],
      textSize: 12.0,
    );
    await pointAnnotationManager.create(pointAnnotationOptions);

    // Draw route from current location to selected destination
    if (_currentPosition != null) {
      await _drawRouteFromCurrentToDestination(latitude, longitude);
    }

    // Clear suggestions after selection
    setState(() {
      _suggestions = [];
      _searchController.text = suggestion['place_name'];
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
      // ignore: use_build_context_synchronously
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

    // Create polyline annotation manager
    polylineAnnotationManager =
        await _mapboxMap.annotations.createPolylineAnnotationManager();

    _mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true, // Enable the location component
        pulsingEnabled: true, // Enable pulsing effect for location puck
        showAccuracyRing: true, // Show accuracy ring around the location
        locationPuck: LocationPuck(
          locationPuck2D: LocationPuck2D(), // Default 2D puck style
        ),
      ),
    );

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
                    onChanged: _searchLocation,
                    decoration: InputDecoration(
                      hintText: "Search location",
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _suggestions = [];
                          });
                        },
                      ),
                    ),
                  ),
                ),
                // Display suggestions below the search field
                if (_suggestions.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: ListTile(
                              title: Text(suggestion['place_name']),
                              onTap: () => _onSuggestionSelected(suggestion),
                            ),
                          ),
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
