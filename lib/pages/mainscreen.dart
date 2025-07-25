import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:map/pages/chats_page.dart';
import 'package:map/pages/profile_page.dart';
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
  // Navigation
  int _currentIndex = 0;

  // Map related
  MapboxMap? _mapboxMap;
  geo.Position? _currentPosition;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _searchNavigationController =
      TextEditingController();
  List<dynamic> _suggestions = [];

  PointAnnotationManager? pointAnnotationManager;
  PolylineAnnotationManager? polylineAnnotationManager;
  StreamSubscription? userpositionStream;

  bool _isMapReady = false;
  bool _areCustomImagesLoaded = false;

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

  // Load custom images into map style
  Future<void> _addCustomImageToStyle({
    required String imageId,
    required String assetPath,
    double scale = 1.0,
  }) async {
    if (_mapboxMap?.style == null) {
      print("Map style not ready for image: $imageId");
      return;
    }

    try {
      final ByteData bytes = await rootBundle.load(assetPath);
      final Uint8List imageData = bytes.buffer.asUint8List();

      // Decode the image to get actual dimensions
      final ui.Image decodedImage = await decodeImageFromList(imageData);

      final mbxImage = MbxImage(
        width: decodedImage.width,
        height: decodedImage.height,
        data: imageData,
      );

      await _mapboxMap!.style.addStyleImage(
        imageId,
        scale,
        mbxImage,
        false,
        [],
        [],
        null,
      );

      print(
        "✅ Custom image '$imageId' loaded successfully (${decodedImage.width}x${decodedImage.height})",
      );
      decodedImage.dispose();
    } catch (e) {
      print("❌ Error loading image '$imageId': $e");
    }
  }

  // Load all custom images
  Future<void> _loadAllCustomImages() async {
    try {
      await Future.wait([
        _addCustomImageToStyle(
          imageId: "custom-marker",
          assetPath: "assets/icons/marker1.png",
        ),
        _addCustomImageToStyle(
          imageId: "destination-marker",
          assetPath: "assets/icons/destination_marker.png",
        ),
        _addCustomImageToStyle(
          imageId: "current-location-marker",
          assetPath: "assets/icons/current_location_marker.png",
        ),
      ]);

      _areCustomImagesLoaded = true;
      print("✅ All custom images loaded successfully");
    } catch (e) {
      print("❌ Error loading some custom images: $e");
      _areCustomImagesLoaded = false;
    }
  }

  // Search for locations using Mapbox Geocoding API
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
        _showErrorSnackBar('Search error: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Error searching location: $e');
    }
  }

  // Search for navigation destinations
  Future<void> _searchLocationToNavigate(String query) async {
    await _searchLocation(query);
  }

  // Get route from start to end coordinates
  Future<List<Position>> _getRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/walking/$startLng,$startLat;$endLng,$endLat?geometries=geojson&access_token=$accessToken',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'];

        if (routes != null && routes.isNotEmpty) {
          final routeCoordinates = routes[0]['geometry']['coordinates'];
          List<Position> routePoints = [];

          for (var coordinate in routeCoordinates) {
            routePoints.add(Position(coordinate[0], coordinate[1]));
          }

          return routePoints;
        } else {
          throw Exception('No routes found');
        }
      } else {
        throw Exception('Failed to load route: ${response.statusCode}');
      }
    } catch (e) {
      print('Route error: $e');
      rethrow;
    }
  }

  // Draw route polyline on the map
  Future<void> _drawRoute(List<Position> routePoints) async {
    if (polylineAnnotationManager == null) {
      print("Polyline annotation manager not ready");
      return;
    }

    try {
      await polylineAnnotationManager!.deleteAll();

      final polylineAnnotationOptions = PolylineAnnotationOptions(
        geometry: LineString(coordinates: routePoints),
        lineColor: Colors.blue.value,
        lineWidth: 5.0,
      );

      await polylineAnnotationManager!.create(polylineAnnotationOptions);
      print("✅ Route drawn successfully");
    } catch (e) {
      print("❌ Error drawing route: $e");
    }
  }

  // Draw route from current location to destination
  Future<void> _drawRouteFromCurrentToDestination(
    double destLat,
    double destLng,
  ) async {
    if (_currentPosition == null) {
      _showErrorSnackBar('Current location not available');
      return;
    }

    if (!_isMapReady) {
      _showErrorSnackBar('Map not ready');
      return;
    }

    try {
      final routePoints = await _getRoute(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        destLat,
        destLng,
      );

      await _drawRoute(routePoints);
      await pointAnnotationManager!.deleteAll();

      await _createMarker(
        longitude: _currentPosition!.longitude,
        latitude: _currentPosition!.latitude,
        title: "Start",
        iconImage: _areCustomImagesLoaded ? "current-location-marker" : null,
      );

      await _createMarker(
        longitude: destLng,
        latitude: destLat,
        title: "Destination",
        iconImage: _areCustomImagesLoaded ? "destination-marker" : null,
      );
    } catch (e) {
      _showErrorSnackBar('Failed to draw route: $e');
    }
  }

  // Helper method to create markers
  Future<void> _createMarker({
    required double longitude,
    required double latitude,
    required String title,
    String? iconImage,
  }) async {
    if (pointAnnotationManager == null) return;

    try {
      final pointAnnotationOptions = PointAnnotationOptions(
        geometry: Point(coordinates: Position(longitude, latitude)),
        iconImage: iconImage,
        iconSize: 1.0,
        textField: title,
        textSize: 12.0,
        textColor: Colors.black.value,
        textOffset: [0.0, -2.5],
      );

      final annotation = await pointAnnotationManager!.create(
        pointAnnotationOptions,
      );
      print("✅ Marker created: $title (${annotation.id})");
    } catch (e) {
      print("❌ Error creating marker '$title': $e");
    }
  }

  // Handle location search suggestion selection
  Future<void> _onSuggestionSelected(dynamic suggestion) async {
    if (!_isMapReady) {
      print("Map not ready for suggestion selection");
      return;
    }

    final coordinates = suggestion['geometry']['coordinates'];
    final longitude = coordinates[0];
    final latitude = coordinates[1];
    final placeName = suggestion['place_name'] ?? 'Unknown location';

    print("📍 Selected location: $placeName at [$longitude, $latitude]");

    try {
      await pointAnnotationManager!.deleteAll();

      await _createMarker(
        longitude: longitude,
        latitude: latitude,
        title: placeName,
        iconImage: _areCustomImagesLoaded ? "custom-marker" : null,
      );

      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(longitude, latitude)),
          zoom: 15.0,
        ),
        MapAnimationOptions(duration: 1000),
      );

      setState(() {
        _suggestions = [];
        _searchController.text = placeName;
      });
    } catch (e) {
      print("❌ Error handling suggestion selection: $e");
      _showErrorSnackBar('Error selecting location');
    }
  }

  // Handle navigation to selected location
  Future<void> _navigateToLocation(dynamic suggestion) async {
    if (!_isMapReady) return;

    final coordinates = suggestion['geometry']['coordinates'];
    final longitude = coordinates[0];
    final latitude = coordinates[1];
    final placeName = suggestion['place_name'] ?? 'Unknown location';

    try {
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(longitude, latitude)),
          zoom: 15.0,
        ),
        MapAnimationOptions(duration: 1000),
      );

      await _drawRouteFromCurrentToDestination(latitude, longitude);

      setState(() {
        _suggestions = [];
        _searchNavigationController.text = placeName;
      });

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("❌ Error in navigation: $e");
      _showErrorSnackBar('Navigation error: $e');
    }
  }

  // Initialize location services
  Future<void> _initializeLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      setState(() => _currentPosition = position);

      userpositionStream = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        setState(() => _currentPosition = position);

        if (_mapboxMap != null && _isMapReady) {
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

      print("✅ Location initialized successfully");
    } catch (e) {
      print("❌ Error initializing location: $e");
    }
  }

  // Handle location permissions
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorSnackBar('Location services are disabled');
      return false;
    }

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        _showErrorSnackBar('Location permissions are denied');
        return false;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      _showErrorSnackBar('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  // Get current position and optionally move camera
  Future<void> _getCurrentPosition({bool moveCamera = true}) async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      setState(() => _currentPosition = position);

      if (moveCamera && _mapboxMap != null && _isMapReady) {
        await _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(position.longitude, position.latitude),
            ),
            zoom: 15.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
    }
  }

  // Show navigation bottom sheet
  Future<void> _showNavigationBottomSheet() async {
    _searchNavigationController.clear();
    setState(() => _suggestions = []);

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

                        // Header section
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
                                onChanged: _searchLocationToNavigate,
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
                                      setState(() => _suggestions = []);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8.0),
                            ],
                          ),
                        ),

                        // Scrollable suggestions
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
                                              () => _navigateToLocation(
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

  // Initialize map and annotation managers
  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    print("🗺️ Map widget created, initializing...");
    _mapboxMap = mapboxMap;

    try {
      await _mapboxMap!.loadStyleURI(MapboxStyles.MAPBOX_STREETS);
      print("✅ Map style loaded");

      await Future.delayed(const Duration(milliseconds: 500));
      await _loadAllCustomImages();

      pointAnnotationManager =
          await _mapboxMap!.annotations.createPointAnnotationManager();
      polylineAnnotationManager =
          await _mapboxMap!.annotations.createPolylineAnnotationManager();

      print("✅ Annotation managers created");

      await _mapboxMap!.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          showAccuracyRing: true,
          locationPuck: LocationPuck(locationPuck2D: DefaultLocationPuck2D()),
        ),
      );

      if (_currentPosition != null) {
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

      _isMapReady = true;
      print("✅ Map fully initialized and ready");
    } catch (e) {
      print("❌ Error initializing map: $e");
      _showErrorSnackBar('Error initializing map: $e');
    }
  }

  // Helper method to show error messages
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // Build map page
  Widget _buildMapPage() {
    return Stack(
      children: [
        // Map widget
        MapWidget(
          key: const ValueKey("mapWidget"),
          onMapCreated: _onMapCreated,
        ),

        // Current location button
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: "currentLocationBtn",
            onPressed: () => _getCurrentPosition(moveCamera: true),
            tooltip: 'Go to current location',
            child: const Icon(Icons.my_location),
          ),
        ),

        // Navigation button
        Positioned(
          right: 16,
          bottom: 80,
          child: FloatingActionButton(
            heroTag: "navigationBtn",
            onPressed: _showNavigationBottomSheet,
            tooltip: 'Navigate to location',
            child: const Icon(Icons.navigation_outlined),
          ),
        ),

        // Search interface
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          bottom: 200,
          child: Column(
            children: [
              // Search field
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
                        setState(() => _suggestions = []);
                      },
                    ),
                  ),
                ),
              ),

              // Search suggestions
              if (_suggestions.isNotEmpty && _searchController.text.isNotEmpty)
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
                              suggestion['place_name'] ?? 'Unknown location',
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
    );
  }

  // Get list of pages
  List<Widget> get _pages => [
    _buildMapPage(),
    const ChatsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      bottomNavigationBar: CurvedNavigationBar(
        index: _currentIndex,
        height: 60.0,
        items: const <Widget>[
          Icon(Icons.map, size: 30),
          Icon(Icons.search, size: 30),
          Icon(Icons.person, size: 30),
        ],
        color: Colors.blue,
        buttonBackgroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        animationCurve: Curves.easeInOut,
        animationDuration: const Duration(milliseconds: 300),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
