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
  MapboxMap? _mapboxMap;
  geo.Position? _currentPosition;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _suggestions = [];
  final TextEditingController _searchNavigationController =
      TextEditingController();

  PointAnnotationManager? pointAnnotationManager;
  PolylineAnnotationManager? polylineAnnotationManager;

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
    _searchController.dispose();
    _searchNavigationController.dispose();
    super.dispose();
  }

  // Add this method to handle searching based on the query
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$accessToken',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _suggestions = data['features'] ?? [];
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error searching location: $e')));
      }
    }
  }

  Future<void> _searchLocationTonavigate(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$accessToken',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _suggestions = data['features'] ?? [];
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error searching location: $e')));
      }
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
      final routes = data['routes'];
      if (routes != null && routes.isNotEmpty) {
        final route = routes[0]['geometry']['coordinates'];
        List<Position> routePoints = [];
        for (var coordinate in route) {
          routePoints.add(Position(coordinate[0], coordinate[1]));
        }
        return routePoints;
      } else {
        throw Exception('No routes found');
      }
    } else {
      throw Exception('Failed to load route: ${response.statusCode}');
    }
  }

  // create polyline on the map - fixed to use PolylineAnnotationManager
  Future<void> drawRoute(List<Position> routePoints) async {
    if (polylineAnnotationManager == null) return;

    // Clear existing polylines first
    await polylineAnnotationManager!.deleteAll();

    // Create polyline annotation options
    final polylineAnnotationOptions = PolylineAnnotationOptions(
      geometry: LineString(coordinates: routePoints),
      lineColor: Colors.blue.value, // Convert Color to int
      lineWidth: 5.0,
    );

    // Create the polyline on the map
    await polylineAnnotationManager!.create(polylineAnnotationOptions);
  }

  // Method to draw route from current location to destination
  Future<void> _drawRouteFromCurrentToDestination(
    double destLat,
    double destLng,
  ) async {
    if (_currentPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current location not available')),
        );
      }
      return;
    }

    if (pointAnnotationManager == null || polylineAnnotationManager == null) {
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
      await pointAnnotationManager!.deleteAll();

      // Start point marker
      await pointAnnotationManager!.create(
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
      await pointAnnotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(destLng, destLat)),
          textField: "Destination",
          textSize: 12.0,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to draw route: $e')));
      }
    }
  }

  // Handle selection of a suggestion and fly the camera to that location
  Future<void> _onSuggestionSelected(dynamic suggestion) async {
    if (_mapboxMap == null || pointAnnotationManager == null) return;

    final coordinates = suggestion['geometry']['coordinates'];
    final latitude = coordinates[1];
    final longitude = coordinates[0];

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 1000),
    );

    // Clear previous annotations
    await pointAnnotationManager!.deleteAll();

    // Clear suggestions after selection
    setState(() {
      _suggestions = [];
      _searchController.text = suggestion['place_name'] ?? '';
    });
  }

  Future<void> _naviagteToLocation(dynamic suggestion) async {
    if (_mapboxMap == null || pointAnnotationManager == null) return;

    final coordinates = suggestion['geometry']['coordinates'];
    final latitude = coordinates[1];
    final longitude = coordinates[0];

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 1000),
    );

    // Clear previous annotations
    await pointAnnotationManager!.deleteAll();

    // Add marker for the selected suggestion
    final pointAnnotationOptions = PointAnnotationOptions(
      geometry: Point(coordinates: Position(longitude, latitude)),
      textField: suggestion['place_name'] ?? '',
      textSize: 12.0,
    );
    await pointAnnotationManager!.create(pointAnnotationOptions);

    // Draw route from current location to selected destination
    if (_currentPosition != null) {
      await _drawRouteFromCurrentToDestination(latitude, longitude);
    }

    // Clear suggestions after selection and close bottom sheet
    setState(() {
      _suggestions = [];
      _searchNavigationController.text = suggestion['place_name'] ?? '';
    });

    if (mounted) {
      Navigator.of(context).pop(); // Close the bottom sheet
    }
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
        if (_mapboxMap != null) {
          _mapboxMap!.flyTo(
            CameraOptions(
              center: Point(
                coordinates: Position(position.longitude, position.latitude),
              ),
              zoom: 15.0,
            ),
            MapAnimationOptions(duration: 300),
          );
        }
      });
    }
  }

  // Request location permission if not granted
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
      }
      return false;
    }

    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        return false;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied'),
          ),
        );
      }
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
        await _mapboxMap!.flyTo(
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

  // navigate user selected location
  Future<void> _navigateTo(BuildContext context) async {
    _searchController.clear();
    _suggestions = []; // Clear previous suggestions
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.25,
              maxChildSize: 0.9,
              expand: false,
              builder:
                  (_, controller) => Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16.0),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 8, bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Fixed header section that doesn't scroll
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            children: [
                              const Text(
                                'Get Direction To A Location',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16.0),
                              TextField(
                                controller: _searchNavigationController,
                                onChanged: _searchLocationTonavigate,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: "Search location",
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.white,
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchNavigationController.clear();
                                      setState(() {
                                        _suggestions = [];
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8.0),
                            ],
                          ),
                        ),
                        // Scrollable content area
                        Expanded(
                          child:
                              _suggestions.isNotEmpty &&
                                      _searchNavigationController
                                          .text
                                          .isNotEmpty
                                  ? ListView.builder(
                                    controller: controller,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                    ),
                                    itemCount: _suggestions.length,
                                    itemBuilder: (context, index) {
                                      final suggestion = _suggestions[index];
                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 8.0,
                                        ),
                                        child: ListTile(
                                          leading: const Icon(
                                            Icons.location_on,
                                            color: Colors.blue,
                                          ),
                                          title: Text(
                                            suggestion['place_name'] ??
                                                'Unknown location',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            suggestion['properties']?['address'] ??
                                                '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          onTap:
                                              () => _naviagteToLocation(
                                                suggestion,
                                              ),
                                        ),
                                      );
                                    },
                                  )
                                  : Container(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search_outlined,
                                          size: 40,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _searchNavigationController
                                                  .text
                                                  .isEmpty
                                              ? 'Start typing to search for locations'
                                              : 'No locations found',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[600],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
    );
  }

  // Set up the Mapbox map and annotation manager
  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    pointAnnotationManager =
        await _mapboxMap!.annotations.createPointAnnotationManager();

    // Create polyline annotation manager
    polylineAnnotationManager =
        await _mapboxMap!.annotations.createPolylineAnnotationManager();

    await _mapboxMap!.location.updateSettings(
      LocationComponentSettings(
        enabled: true, // Enable the location component
        pulsingEnabled: true, // Enable pulsing effect for location puck
        showAccuracyRing: true, // Show accuracy ring around the location
        locationPuck: LocationPuck(
          locationPuck2D:
              DefaultLocationPuck2D(), // Fixed: Use DefaultLocationPuck2D
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
            Positioned(
              right: 16,
              bottom: 80,
              child: FloatingActionButton(
                onPressed: () => _navigateTo(context),
                child: const Icon(Icons.navigation_outlined),
              ),
            ),
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              bottom: 200, // Leave space for FABs
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _searchLocation,
                      decoration: InputDecoration(
                        hintText: "Search location",
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(100)),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
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
                  if (_suggestions.isNotEmpty &&
                      _searchController.text.isNotEmpty)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16.0),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(167, 255, 255, 255),
                          borderRadius: BorderRadius.circular(8.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListView.builder(
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return Container(
                              decoration: BoxDecoration(
                                border:
                                    index < _suggestions.length - 1
                                        ? Border(
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        )
                                        : null,
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.location_on,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                title: Text(
                                  suggestion['place_name'] ??
                                      'Unknown location',
                                  style: const TextStyle(fontSize: 14),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                dense: true,
                                onTap: () => _onSuggestionSelected(suggestion),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
