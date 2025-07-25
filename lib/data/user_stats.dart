import 'package:supabase_flutter/supabase_flutter.dart';

class UserStatsService {
  static final _client = Supabase.instance.client;

  // Model classes for the data
  static Future<UserStats> getUserStats() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get stats in parallel for better performance
      final results = await Future.wait([
        _getPlacesCount(user.id),
        _getRoutesCount(user.id),
        _getTotalDistance(user.id),
      ]);

      return UserStats(
        places: results[0] as int,
        routes: results[1] as int,
        distance: results[2] as double,
      );
    } catch (error) {
      print('Error getting user stats: $error');
      return UserStats(places: 0, routes: 0, distance: 0.0);
    }
  }

  static Future<int> _getPlacesCount(String userId) async {
    final response = await _client
        .from('user_places')
        .select('id')
        .eq('user_id', userId);

    return response.length;
  }

  static Future<int> _getRoutesCount(String userId) async {
    final response = await _client
        .from('user_routes')
        .select('id')
        .eq('user_id', userId);

    return response.length;
  }

  static Future<double> _getTotalDistance(String userId) async {
    final response = await _client
        .from('user_routes')
        .select('distance_km')
        .eq('user_id', userId);

    double totalDistance = 0.0;
    for (var route in response) {
      totalDistance += (route['distance_km'] as num?)?.toDouble() ?? 0.0;
    }

    return totalDistance;
  }

  // Method to save a new place
  static Future<void> savePlace({
    required String placeName,
    required double latitude,
    required double longitude,
    String? address,
    String placeType = 'saved',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Check if place already exists
    final existing =
        await _client
            .from('user_places')
            .select('id, visit_count')
            .eq('user_id', user.id)
            .eq('latitude', latitude)
            .eq('longitude', longitude)
            .maybeSingle();

    if (existing != null) {
      // Update visit count if place exists
      await _client
          .from('user_places')
          .update({
            'visit_count': (existing['visit_count'] as int) + 1,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existing['id']);
    } else {
      // Insert new place
      await _client.from('user_places').insert({
        'user_id': user.id,
        'place_name': placeName,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'place_type': placeType,
      });
    }
  }

  // Method to save a new route
  static Future<void> saveRoute({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    String? startAddress,
    String? endAddress,
    double? distanceKm,
    int? durationMinutes,
    String routeType = 'navigation',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _client.from('user_routes').insert({
      'user_id': user.id,
      'start_latitude': startLatitude,
      'start_longitude': startLongitude,
      'end_latitude': endLatitude,
      'end_longitude': endLongitude,
      'start_address': startAddress,
      'end_address': endAddress,
      'distance_km': distanceKm,
      'duration_minutes': durationMinutes,
      'route_type': routeType,
    });
  }

  // Method to get recent places
  static Future<List<UserPlace>> getRecentPlaces({int limit = 10}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final response = await _client
        .from('user_places')
        .select('*')
        .eq('user_id', user.id)
        .order('updated_at', ascending: false)
        .limit(limit);

    return response.map((place) => UserPlace.fromJson(place)).toList();
  }

  // Method to get recent routes
  static Future<List<UserRoute>> getRecentRoutes({int limit = 10}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final response = await _client
        .from('user_routes')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);

    return response.map((route) => UserRoute.fromJson(route)).toList();
  }

  // Method to format distance for display
  static String formatDistance(double distanceKm) {
    if (distanceKm < 1.0) {
      return '${(distanceKm * 1000).toInt()} m';
    } else if (distanceKm < 10.0) {
      return '${distanceKm.toStringAsFixed(1)} km';
    } else {
      return '${distanceKm.toStringAsFixed(0)} km';
    }
  }
}

// Model classes
class UserStats {
  final int places;
  final int routes;
  final double distance;

  UserStats({
    required this.places,
    required this.routes,
    required this.distance,
  });

  String get formattedDistance => UserStatsService.formatDistance(distance);
}

class UserPlace {
  final String id;
  final String placeName;
  final double latitude;
  final double longitude;
  final String? address;
  final String placeType;
  final int visitCount;
  final DateTime createdAt;

  UserPlace({
    required this.id,
    required this.placeName,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.placeType,
    required this.visitCount,
    required this.createdAt,
  });

  factory UserPlace.fromJson(Map<String, dynamic> json) {
    return UserPlace(
      id: json['id'],
      placeName: json['place_name'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      address: json['address'],
      placeType: json['place_type'],
      visitCount: json['visit_count'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class UserRoute {
  final String id;
  final double startLatitude;
  final double startLongitude;
  final double endLatitude;
  final double endLongitude;
  final String? startAddress;
  final String? endAddress;
  final double? distanceKm;
  final int? durationMinutes;
  final String routeType;
  final DateTime createdAt;

  UserRoute({
    required this.id,
    required this.startLatitude,
    required this.startLongitude,
    required this.endLatitude,
    required this.endLongitude,
    this.startAddress,
    this.endAddress,
    this.distanceKm,
    this.durationMinutes,
    required this.routeType,
    required this.createdAt,
  });

  factory UserRoute.fromJson(Map<String, dynamic> json) {
    return UserRoute(
      id: json['id'],
      startLatitude: json['start_latitude'].toDouble(),
      startLongitude: json['start_longitude'].toDouble(),
      endLatitude: json['end_latitude'].toDouble(),
      endLongitude: json['end_longitude'].toDouble(),
      startAddress: json['start_address'],
      endAddress: json['end_address'],
      distanceKm: json['distance_km']?.toDouble(),
      durationMinutes: json['duration_minutes'],
      routeType: json['route_type'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get formattedDistance =>
      distanceKm != null
          ? UserStatsService.formatDistance(distanceKm!)
          : 'Unknown';
}
