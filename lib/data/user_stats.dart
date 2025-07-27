import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

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

  /// Calculate distance between two coordinates using Haversine formula
  static double _calculateDistance(
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

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// Find a nearby place within the specified radius
  static Future<Map<String, dynamic>?> findNearbyPlace({
    required double latitude,
    required double longitude,
    required String address,
    double radiusMeters = 50.0,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      print(
        '🔍 findNearbyPlace: Searching for places near $latitude, $longitude',
      );

      // Get all places with the same address for this user
      final response = await _client
          .from('user_places')
          .select('*')
          .eq('user_id', user.id)
          .eq('address', address);

      print('📍 Found ${response.length} places with matching address');

      // Check distance for each place with the same address
      for (final place in response) {
        final double placeLatitude = place['latitude'].toDouble();
        final double placeLongitude = place['longitude'].toDouble();

        final double distance = _calculateDistance(
          latitude,
          longitude,
          placeLatitude,
          placeLongitude,
        );

        print(
          '📏 Distance to ${place['place_name']}: ${distance.toStringAsFixed(1)}m',
        );

        if (distance <= radiusMeters) {
          print('🎯 Found nearby place within ${distance.toStringAsFixed(1)}m');
          return place;
        }
      }

      print('📍 No nearby places found within ${radiusMeters}m radius');
      return null;
    } catch (e) {
      print('❌ Error finding nearby place: $e');
      return null;
    }
  }

  /// Update visit count for an existing place
  static Future<bool> updatePlaceVisitCount(String placeId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // First get the current visit count
      final currentPlace =
          await _client
              .from('user_places')
              .select('visit_count')
              .eq('id', placeId)
              .eq('user_id', user.id)
              .single();

      final currentVisitCount = currentPlace['visit_count'] as int;

      // Update with incremented visit count
      final response = await _client
          .from('user_places')
          .update({
            'visit_count': currentVisitCount + 1,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId)
          .eq('user_id', user.id);

      print(
        '✅ Updated visit count to ${currentVisitCount + 1} for place $placeId',
      );
      return true;
    } catch (e) {
      print('❌ Error updating place visit count: $e');
      return false;
    }
  }

  // Updated method to save a new place with duplicate detection
  static Future<void> savePlace({
    required String placeName,
    required double latitude,
    required double longitude,
    String? address,
    String placeType = 'saved',
    double radiusMeters = 50.0,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    print('💾 savePlace: Starting to save place');
    print('📍 Coordinates: $latitude, $longitude');
    print('📝 Address: $address');

    try {
      // Check for nearby places first
      if (address != null) {
        final nearbyPlace = await findNearbyPlace(
          latitude: latitude,
          longitude: longitude,
          address: address,
          radiusMeters: radiusMeters,
        );

        if (nearbyPlace != null) {
          // Update existing place visit count
          print('📍 Found nearby place, updating visit count...');
          final success = await updatePlaceVisitCount(nearbyPlace['id']);

          if (success) {
            print('✅ Successfully updated visit count for existing place');
            return;
          } else {
            print('⚠️ Failed to update visit count, will save as new place');
          }
        }
      }

      // If no nearby place found or address is null, save as new place
      print('💾 Saving as new place...');
      await _client.from('user_places').insert({
        'user_id': user.id,
        'place_name': placeName,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'place_type': placeType,
        'visit_count': 1, // Initialize with 1 visit
      });

      print('✅ New place saved successfully');
    } catch (e) {
      print('❌ Error in savePlace: $e');
      rethrow;
    }
  }

  /// Alternative method using coordinate rounding for duplicate detection
  static Future<Map<String, dynamic>?> findPlaceByRoundedCoordinates({
    required double latitude,
    required double longitude,
    required String address,
    int decimalPlaces = 4, // ~11 meters accuracy
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final double roundedLat = roundCoordinate(latitude, decimalPlaces);
      final double roundedLon = roundCoordinate(longitude, decimalPlaces);

      print(
        '🔍 Looking for place with rounded coordinates: $roundedLat, $roundedLon',
      );

      // Since Supabase doesn't support ROUND function directly in queries,
      // we'll get all places with the same address and check manually
      final response = await _client
          .from('user_places')
          .select('*')
          .eq('user_id', user.id)
          .eq('address', address);

      for (final place in response) {
        final placeRoundedLat = roundCoordinate(
          place['latitude'].toDouble(),
          decimalPlaces,
        );
        final placeRoundedLon = roundCoordinate(
          place['longitude'].toDouble(),
          decimalPlaces,
        );

        if (placeRoundedLat == roundedLat && placeRoundedLon == roundedLon) {
          print('🎯 Found place with matching rounded coordinates');
          return place;
        }
      }

      return null;
    } catch (e) {
      print('❌ Error finding place by rounded coordinates: $e');
      return null;
    }
  }

  /// Round coordinates to reduce precision
  static double roundCoordinate(double coordinate, int decimalPlaces) {
    double multiplier = pow(10, decimalPlaces).toDouble();
    return (coordinate * multiplier).round() / multiplier;
  }

  /// Cleanup existing duplicates (run this once to clean your database)
  static Future<int> mergeDuplicatePlaces({double radiusMeters = 50.0}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      print('🔄 Starting duplicate cleanup process...');

      // Get all places for the user
      final allPlaces = await _client
          .from('user_places')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: true); // Older places first

      print('📊 Found ${allPlaces.length} total places to analyze');

      // Group by address for efficiency
      Map<String, List<Map<String, dynamic>>> placesByAddress = {};
      for (final place in allPlaces) {
        final address = place['address'] as String? ?? 'no_address';
        placesByAddress.putIfAbsent(address, () => []).add(place);
      }

      int mergedCount = 0;
      List<String> idsToDelete = [];

      // Process each address group
      for (final addressGroup in placesByAddress.values) {
        if (addressGroup.length <= 1) continue;

        print('🔍 Processing ${addressGroup.length} places for address group');

        List<String> processedIds = [];

        for (int i = 0; i < addressGroup.length; i++) {
          final place1 = addressGroup[i];
          if (processedIds.contains(place1['id'])) continue;

          List<Map<String, dynamic>> duplicates = [place1];

          for (int j = i + 1; j < addressGroup.length; j++) {
            final place2 = addressGroup[j];
            if (processedIds.contains(place2['id'])) continue;

            final distance = _calculateDistance(
              place1['latitude'].toDouble(),
              place1['longitude'].toDouble(),
              place2['latitude'].toDouble(),
              place2['longitude'].toDouble(),
            );

            if (distance <= radiusMeters) {
              duplicates.add(place2);
              processedIds.add(place2['id']);
            }
          }

          if (duplicates.length > 1) {
            print(
              '🔧 Found ${duplicates.length} duplicates for: ${place1['place_name']}',
            );

            // Calculate total visit count
            int totalVisits = duplicates.fold<int>(
              0,
              (sum, place) => sum + (place['visit_count'] as int? ?? 1),
            );

            // Update the first (oldest) place with total visit count
            await _client
                .from('user_places')
                .update({
                  'visit_count': totalVisits,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', place1['id']);

            // Mark other duplicates for deletion
            for (int k = 1; k < duplicates.length; k++) {
              idsToDelete.add(duplicates[k]['id']);
            }

            mergedCount += duplicates.length - 1;
            print(
              '✅ Will merge ${duplicates.length} places with total visits: $totalVisits',
            );
          }

          processedIds.add(place1['id']);
        }
      }

      // Delete duplicate places in batches
      if (idsToDelete.isNotEmpty) {
        print('🗑️ Deleting ${idsToDelete.length} duplicate places...');

        // Alternative approach: Delete one by one if batch deletion doesn't work
        for (final id in idsToDelete) {
          try {
            await _client.from('user_places').delete().eq('id', id);
          } catch (e) {
            print('⚠️ Failed to delete place $id: $e');
          }
        }

        /* 
        // Batch deletion approach (use this if inFilter works in your version)
        const batchSize = 100;
        for (int i = 0; i < idsToDelete.length; i += batchSize) {
          final batch = idsToDelete.skip(i).take(batchSize).toList();
          await _client
              .from('user_places')
              .delete()
              .inFilter('id', batch);
        }
        */
      }

      print('✅ Cleanup complete: Merged $mergedCount duplicate places');
      return mergedCount;
    } catch (e) {
      print('❌ Error merging duplicate places: $e');
      return 0;
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
      visitCount: json['visit_count'] ?? 1,
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
