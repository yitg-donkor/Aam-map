// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:map/data/user_stats.dart';
import 'package:map/pages/chats_page.dart';
import 'package:map/pages/friends_page.dart';
import 'package:map/pages/game_page.dart';
import 'package:map/pages/profile_page.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'dart:io';

class Mainscreen extends StatefulWidget {
  const Mainscreen({super.key});

  @override
  State<Mainscreen> createState() => _MainscreenState();
}

class _MainscreenState extends State<Mainscreen> with WidgetsBindingObserver {
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
  StreamSubscription<geo.Position>? userpositionStream;

  bool _isMapReady = false;
  bool _areCustomImagesLoaded = false;
  geo.Position? _lastTrackedPosition;
  double _totalDistanceTraveled = 0.0;
  StreamSubscription<geo.Position>? _distanceTrackingStream;
  bool _isTrackingDistance = false;
  Timer? _distanceUpdateTimer;

  // Distance tracking constants
  static const double _minimumDistanceThreshold = 5.0; // meters
  static const int _distanceUpdateIntervalSeconds = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupResources();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pauseLocationTracking();
        break;
      case AppLifecycleState.resumed:
        _resumeLocationTracking();
        break;
      case AppLifecycleState.detached:
        _cleanupResources();
        break;
      default:
        break;
    }
  }

  Future<void> _initializeApp() async {
    try {
      MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));
      await _loadUserTotalDistance();
      await _initializeLocation();
      await _startDistanceTracking();
    } catch (e) {
      _handleError('Failed to initialize app', e);
    }
  }

  void _cleanupResources() {
    userpositionStream?.cancel();
    _distanceTrackingStream?.cancel();
    _distanceUpdateTimer?.cancel();
    _searchController.dispose();
    _searchNavigationController.dispose();
  }

  void _pauseLocationTracking() {
    if (_isTrackingDistance) {
      _stopDistanceTracking();
    }
  }

  void _resumeLocationTracking() {
    if (!_isTrackingDistance) {
      _startDistanceTracking();
    }
  }

  // Load user total distance traveled
  Future<void> _loadUserTotalDistance() async {
    try {
      final stats = await UserStatsService.getUserStats();
      if (mounted) {
        setState(() {
          _totalDistanceTraveled = stats.distance;
        });
      }
      print(
        '📊 Loaded total distance: ${_totalDistanceTraveled.toStringAsFixed(2)} km',
      );
    } catch (e) {
      _handleError('Error loading total distance', e);
    }
  }

  // Start real-time distance tracking
  Future<void> _startDistanceTracking() async {
    if (_isTrackingDistance) return;

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      setState(() {
        _isTrackingDistance = true;
      });

      // Get initial position
      final initialPosition = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _lastTrackedPosition = initialPosition;

      print(
        '🎯 Started distance tracking from: ${initialPosition.latitude}, ${initialPosition.longitude}',
      );

      // Start listening to position changes for distance tracking
      _distanceTrackingStream = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          distanceFilter: 3, // Update every 3 meters
          timeLimit: Duration(seconds: 10),
        ),
      ).listen(
        _onPositionUpdate,
        onError: (error) {
          _handleError('Distance tracking error', error);
        },
      );

      // Start periodic database updates
      _startPeriodicDistanceUpdates();
    } catch (e) {
      _handleError('Error starting distance tracking', e);
      if (mounted) {
        setState(() {
          _isTrackingDistance = false;
        });
      }
    }
  }

  void _onPositionUpdate(geo.Position newPosition) {
    if (!mounted) return;

    if (_lastTrackedPosition == null) {
      _lastTrackedPosition = newPosition;
      setState(() => _currentPosition = newPosition);
      return;
    }

    final distance = _calculateDistance(
      _lastTrackedPosition!.latitude,
      _lastTrackedPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );

    if (distance >= _minimumDistanceThreshold) {
      final distanceKm = distance / 1000.0; // Convert to kilometers
      setState(() {
        _totalDistanceTraveled += distanceKm;
        _lastTrackedPosition = newPosition;
      });
      print(
        '🚶 Distance update: +${distanceKm.toStringAsFixed(3)} km (Total: ${_totalDistanceTraveled.toStringAsFixed(2)} km)',
      );
    }

    setState(() => _currentPosition = newPosition);

    if (_mapboxMap != null && _isMapReady) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(newPosition.longitude, newPosition.latitude),
          ),
          zoom: 15.0,
        ),
        MapAnimationOptions(duration: 300),
      );
    }
  }

  void _startPeriodicDistanceUpdates() {
    _distanceUpdateTimer = Timer.periodic(
      const Duration(seconds: _distanceUpdateIntervalSeconds),
      (timer) async {
        if (_isTrackingDistance && _totalDistanceTraveled > 0 && mounted) {
          await _saveDistanceToDatabase();
        }
      },
    );
  }

  Future<void> _saveDistanceToDatabase() async {
    try {
      await UserStatsService.updateUserTotalDistance(_totalDistanceTraveled);
      print(
        '💾 Distance saved to database: ${_totalDistanceTraveled.toStringAsFixed(2)} km',
      );
    } catch (e) {
      _handleError('Error saving distance to database', e);
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // Earth's radius in meters

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // Distance in meters
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  Future<void> _stopDistanceTracking() async {
    if (!_isTrackingDistance) return;

    setState(() {
      _isTrackingDistance = false;
    });

    _distanceTrackingStream?.cancel();
    _distanceUpdateTimer?.cancel();

    // Save final distance to database
    await _saveDistanceToDatabase();

    print(
      '⏹️ Distance tracking stopped. Total: ${_totalDistanceTraveled.toStringAsFixed(2)} km',
    );
  }

  void _resumeDistanceTracking() {
    if (!_isTrackingDistance) {
      _startDistanceTracking();
    }
  }

  Future<void> _resetDistance() async {
    if (mounted) {
      setState(() {
        _totalDistanceTraveled = 0.0;
        _lastTrackedPosition = null;
      });
    }

    try {
      await UserStatsService.resetUserTotalDistance();
      print('🔄 Distance reset to 0');
    } catch (e) {
      _handleError('Error resetting distance', e);
    }
  }

  String get formattedTotalDistance {
    if (_totalDistanceTraveled < 1.0) {
      return '${(_totalDistanceTraveled * 1000).toInt()} m';
    } else if (_totalDistanceTraveled < 10.0) {
      return '${_totalDistanceTraveled.toStringAsFixed(1)} km';
    } else {
      return '${_totalDistanceTraveled.toStringAsFixed(0)} km';
    }
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
      _handleError("Error loading image '$imageId'", e);
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
      _handleError("Error loading some custom images", e);
      _areCustomImagesLoaded = false;
    }
  }

  // Search for locations using Mapbox Geocoding API
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = [];
        });
      }
      return;
    }

    final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (accessToken.isEmpty) {
      _showErrorSnackBar('Mapbox access token not configured');
      return;
    }

    final url = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?access_token=$accessToken',
    );

    try {
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Search request timed out',
                const Duration(seconds: 10),
              );
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _suggestions = data['features'] ?? [];
          });
        }
      } else {
        _showErrorSnackBar('Search error: ${response.statusCode}');
      }
    } catch (e) {
      _handleError('Error searching location', e);
    }
  }

  // Search for navigation destinations
  Future<void> _searchLocationToNavigate(String query) async {
    await _searchLocation(query);
  }

  // Enhanced saveplace function with duplicate detection
  Future<void> saveplace() async {
    print('💾 saveplace: Starting to save current location');

    try {
      // Check if current position is available
      if (_currentPosition == null) {
        print('📍 saveplace: Getting current position...');
        await _getCurrentPosition(moveCamera: false);

        if (_currentPosition == null) {
          throw Exception('Unable to get current location');
        }
      }

      print(
        '📍 saveplace: Current position - ${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
      );

      // Get place details with improved error handling
      print('🔍 saveplace: Getting place details...');
      Map<String, dynamic> placeDetails;

      try {
        placeDetails = await getPlaceDetails(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      } catch (e) {
        print(
          '⚠️ saveplace: Failed to get place details, using coordinates as fallback',
        );
        placeDetails = {
          'country': '',
          'region': '',
          'district': '',
          'locality': '',
          'postcode': '',
          'full_place_name':
              'Location at ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
        };
      }

      // Extract place name and formatted address
      final placeName = placeDetails['full_place_name'] as String;
      final formattedAddress = _buildFormattedAddress(placeDetails);

      print('📝 saveplace: Place details retrieved');
      print('   - Place Name: $placeName');
      print('   - Address: $formattedAddress');

      // Save using the updated UserStatsService with duplicate detection
      await UserStatsService.savePlace(
        placeName: placeName,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        address: formattedAddress.isNotEmpty ? formattedAddress : null,
        radiusMeters: 50.0, // 50 meter radius for duplicate detection
      );

      print('✅ saveplace: Location processed successfully!');

      // Show success message to user
      if (mounted) {
        _showSuccessSnackBar(
          'Location saved: ${placeName.length > 30 ? '${placeName.substring(0, 30)}...' : placeName}',
        );
      }
    } catch (e) {
      _handleError('Failed to save location', e);
    }
  }

  String _buildFormattedAddress(Map<String, dynamic> placeDetails) {
    List<String> addressParts = [];

    final locality = (placeDetails['locality'] as String?)?.trim() ?? '';
    final district = (placeDetails['district'] as String?)?.trim() ?? '';
    final region = (placeDetails['region'] as String?)?.trim() ?? '';
    final country = (placeDetails['country'] as String?)?.trim() ?? '';

    if (locality.isNotEmpty) addressParts.add(locality);
    if (district.isNotEmpty && district != locality) addressParts.add(district);
    if (region.isNotEmpty && region != district) addressParts.add(region);
    if (country.isNotEmpty) addressParts.add(country);

    return addressParts.isNotEmpty
        ? addressParts.join(', ')
        : 'Unknown Address';
  }

  // Enhanced getPlaceDetails function with better error handling
  Future<Map<String, dynamic>> getPlaceDetails(
    double latitude,
    double longitude,
  ) async {
    print(
      '🔍 getPlaceDetails: Getting detailed place info for $latitude, $longitude',
    );

    // Fallback data in case of API failure
    final fallbackData = {
      'country': '',
      'region': '',
      'district': '',
      'locality': '',
      'postcode': '',
      'full_place_name': 'Location at $latitude, $longitude',
    };

    try {
      final accessToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

      if (accessToken.isEmpty) {
        print(
          '⚠️ getPlaceDetails: Mapbox access token not found, using fallback',
        );
        return fallbackData;
      }

      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$longitude,$latitude.json'
          '?access_token=$accessToken'
          '&types=country,region,postcode,district,place,locality,neighborhood,address,poi';

      print('🌐 getPlaceDetails: Making API request...');

      final client = http.Client();

      try {
        final response = await client
            .get(Uri.parse(url))
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                print('⏰ getPlaceDetails: Request timed out after 15 seconds');
                throw TimeoutException(
                  'Mapbox API request timed out',
                  const Duration(seconds: 15),
                );
              },
            );

        if (response.statusCode == 200) {
          print('✅ getPlaceDetails: API response received');
          final data = jsonDecode(response.body);

          if (data['features'] != null && data['features'].isNotEmpty) {
            final feature = data['features'][0];
            final context = feature['context'] as List?;

            // Extract address components
            String country = '';
            String region = '';
            String district = '';
            String locality = '';
            String postcode = '';

            if (context != null) {
              for (var item in context) {
                final id = item['id'] as String;
                final text = item['text'] as String;

                if (id.startsWith('country')) {
                  country = text;
                } else if (id.startsWith('region')) {
                  region = text;
                } else if (id.startsWith('district')) {
                  district = text;
                } else if (id.startsWith('locality') ||
                    id.startsWith('place')) {
                  locality = text;
                } else if (id.startsWith('postcode')) {
                  postcode = text;
                }
              }
            }

            final result = {
              'country': country,
              'region': region,
              'district': district,
              'locality': locality,
              'postcode': postcode,
              'full_place_name':
                  feature['place_name'] ?? fallbackData['full_place_name'],
            };

            print('✅ getPlaceDetails: Successfully parsed place details');
            return result;
          } else {
            print(
              '⚠️ getPlaceDetails: No features in API response, using fallback',
            );
            return fallbackData;
          }
        } else if (response.statusCode == 429) {
          print(
            '⚠️ getPlaceDetails: Rate limit exceeded (429), using fallback',
          );
          return fallbackData;
        } else {
          print(
            '⚠️ getPlaceDetails: HTTP ${response.statusCode}, using fallback',
          );
          return fallbackData;
        }
      } finally {
        client.close();
      }
    } on TimeoutException catch (e) {
      print('⏰ getPlaceDetails: Timeout error - ${e.message}');
      return fallbackData;
    } on SocketException catch (e) {
      print('📶 getPlaceDetails: Network error - ${e.message}');
      return fallbackData;
    } on FormatException catch (e) {
      print('📄 getPlaceDetails: JSON parsing error - ${e.message}');
      return fallbackData;
    } catch (e) {
      print('❌ getPlaceDetails: Unexpected error - $e');
      return fallbackData;
    }
  }

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
      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException(
                'Route request timed out',
                const Duration(seconds: 15),
              );
            },
          );

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
      _handleError("Error drawing route", e);
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
      _handleError("Error creating marker '$title'", e);
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

      if (mounted) {
        setState(() {
          _suggestions = [];
          _searchController.text = placeName;
        });
      }
    } catch (e) {
      _handleError("Error handling suggestion selection", e);
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

      if (mounted) {
        setState(() {
          _suggestions = [];
          _searchNavigationController.text = placeName;
        });

        Navigator.of(context).pop();
      }
    } catch (e) {
      _handleError("Error in navigation", e);
    }
  }

  // Initialize location services
  Future<void> _initializeLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
        setState(() => _currentPosition = position);
      }

      userpositionStream = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        if (mounted) {
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
        }
      });

      print("✅ Location initialized successfully");
    } catch (e) {
      _handleError("Error initializing location", e);
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
        timeLimit: const Duration(seconds: 10),
      );

      if (mounted) {
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
      }
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
    }
  }

  // Show navigation bottom sheet
  Future<void> _showNavigationBottomSheet() async {
    _searchNavigationController.clear();
    if (mounted) {
      setState(() => _suggestions = []);
    }

    if (!mounted) return;

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
                                      if (mounted) {
                                        setState(() => _suggestions = []);
                                      }
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

      if (_currentPosition != null && mounted) {
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
      _handleError('Error initializing map', e);
    }
  }

  // Helper methods for error handling and user feedback
  void _handleError(String message, dynamic error) {
    print('❌ $message: $error');
    if (mounted) {
      _showErrorSnackBar('$message: $error');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildDistanceTrackingIndicator() {
    return Positioned(
      top: 100,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isTrackingDistance ? Colors.green : Colors.grey,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isTrackingDistance ? Icons.directions_run : Icons.pause,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              formattedTotalDistance,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build speed dial with optimized actions
  Widget _buildSpeedDial() {
    return SpeedDial(
      animatedIcon: AnimatedIcons.menu_close,
      animatedIconTheme: const IconThemeData(size: 24),
      animationDuration: const Duration(milliseconds: 300),
      animationCurve: Curves.easeInOut,
      overlayOpacity: 0.4,
      spaceBetweenChildren: 12,
      children: [
        SpeedDialChild(
          child: Icon(
            _isTrackingDistance ? Icons.pause : Icons.play_arrow,
            size: 24,
          ),
          backgroundColor: _isTrackingDistance ? Colors.orange : Colors.green,
          foregroundColor: Colors.white,
          label: _isTrackingDistance ? 'Pause Tracking' : 'Resume Tracking',
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
          labelBackgroundColor: Colors.black87,
          elevation: 6.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          onTap: () async {
            HapticFeedback.mediumImpact();
            if (_isTrackingDistance) {
              await _stopDistanceTracking();
            } else {
              _resumeDistanceTracking();
            }
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.my_location, size: 24),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          label: 'Current Location',
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
          labelBackgroundColor: Colors.black87,
          elevation: 6.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          onTap: () async {
            HapticFeedback.mediumImpact();
            await _getCurrentPosition(moveCamera: true);

            await Future.delayed(const Duration(milliseconds: 150));

            if (mounted) {
              _showSuccessSnackBar('Getting current location...');
            }
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.directions, size: 24),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          label: 'Get Directions',
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
          labelBackgroundColor: Colors.black87,
          elevation: 6.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          onTap: () async {
            HapticFeedback.mediumImpact();
            await _showNavigationBottomSheet();

            await Future.delayed(const Duration(milliseconds: 150));

            if (mounted) {
              _showSuccessSnackBar('Opening navigation...');
            }
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.favorite, size: 24),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          label: 'Add Favorite',
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
          labelBackgroundColor: Colors.black87,
          elevation: 6.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          onTap: () async {
            HapticFeedback.mediumImpact();
            await saveplace();

            await Future.delayed(const Duration(milliseconds: 150));
          },
        ),
      ],
    );
  }

  // Build map page with improved layout
  Widget _buildMapPage() {
    return Stack(
      children: [
        // Map widget
        MapWidget(
          key: const ValueKey("mapWidget"),
          onMapCreated: _onMapCreated,
        ),

        // Distance tracking indicator
        _buildDistanceTrackingIndicator(),

        // Speed dial
        Positioned(right: 16, bottom: 16, child: _buildSpeedDial()),

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
                        if (mounted) {
                          setState(() => _suggestions = []);
                        }
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
    const FriendsPage(),
    const GamePage(),
    const ChatsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _currentIndex, children: _pages),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: CurvedNavigationBar(
              index: _currentIndex,
              height: 60.0,
              items: const <Widget>[
                Icon(Icons.map_outlined, size: 30),
                Icon(Icons.people_alt_outlined, size: 30),
                Icon(Icons.gamepad_outlined, size: 30),
                Icon(Icons.chat_bubble_outline, size: 30),
                Icon(Icons.person, size: 30),
              ],
              color: Colors.white.withOpacity(0.8),
              buttonBackgroundColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              animationCurve: Curves.easeInOut,
              animationDuration: const Duration(milliseconds: 300),
              onTap: (index) {
                if (mounted) {
                  setState(() {
                    _currentIndex = index;
                  });
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
