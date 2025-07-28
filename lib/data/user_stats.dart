// ignore_for_file: avoid_print

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
    try {
      final response = await _client
          .from('user_places')
          .select('id')
          .eq('user_id', userId);

      return response.length;
    } catch (e) {
      print('Error getting places count: $e');
      return 0;
    }
  }

  static Future<int> _getRoutesCount(String userId) async {
    try {
      final response = await _client
          .from('user_routes')
          .select('id')
          .eq('user_id', userId);

      return response.length;
    } catch (e) {
      print('Error getting routes count: $e');
      return 0;
    }
  }

  static Future<double> _getTotalDistance(String userId) async {
    try {
      final response =
          await _client
              .from('user_stats')
              .select('total_distance_km')
              .eq('user_id', userId)
              .maybeSingle();

      if (response != null && response['total_distance_km'] != null) {
        return response['total_distance_km'].toDouble();
      }

      // If no user_stats record exists, create one
      await _createUserStatsRecord(userId);
      return 0.0;
    } catch (e) {
      print('❌ Error getting total distance: $e');
      return 0.0;
    }
  }

  /// Create initial user stats record
  static Future<void> _createUserStatsRecord(String userId) async {
    try {
      await _client.from('user_stats').insert({
        'user_id': userId,
        'total_distance_km': 0.0,
        'total_places': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // If record already exists (race condition), ignore the error
      if (e.toString().contains('duplicate key value')) {
        print('ℹ️ User stats record already exists, continuing...');
      } else {
        rethrow;
      }
    }
  }

  /// Update user total distance with proper upsert handling
  static Future<void> updateUserTotalDistance(double totalDistanceKm) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (totalDistanceKm < 0) {
        throw ArgumentError('Total distance cannot be negative');
      }

      // First, try to update existing record
      final updateResponse = await _client.from('user_stats').upsert({
        'user_id': user.id,
        'total_distance_km': totalDistanceKm,
        'updated_at': DateTime.now().toIso8601String(),
        // Include created_at for new records
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id'); // Add this line

      // If no rows were affected, the record doesn't exist, so create it
      if (updateResponse == null || updateResponse.isEmpty) {
        try {
          await _client.from('user_stats').insert({
            'user_id': user.id,
            'total_distance_km': totalDistanceKm,
            'total_places': 0,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (insertError) {
          // If insert fails due to race condition, try update again
          if (insertError.toString().contains('duplicate key value')) {
            await _client
                .from('user_stats')
                .update({
                  'total_distance_km': totalDistanceKm,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('user_id', user.id);
          } else {
            rethrow;
          }
        }
      }

      print(
        '💾 Updated total distance: ${totalDistanceKm.toStringAsFixed(2)} km',
      );
    } catch (e) {
      print('❌ Error updating total distance: $e');
      rethrow;
    }
  }

  /// Alternative method using proper upsert with onConflict
  static Future<void> updateUserTotalDistanceUpsert(
    double totalDistanceKm,
  ) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (totalDistanceKm < 0) {
        throw ArgumentError('Total distance cannot be negative');
      }

      // Use upsert with proper conflict resolution
      await _client.from('user_stats').upsert({
        'user_id': user.id,
        'total_distance_km': totalDistanceKm,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id'); // Specify the conflict column

      print(
        '💾 Updated total distance: ${totalDistanceKm.toStringAsFixed(2)} km',
      );
    } catch (e) {
      print('❌ Error updating total distance: $e');
      rethrow;
    }
  }

  static Future<void> resetUserTotalDistance() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await _client
          .from('user_stats')
          .update({
            'total_distance_km': 0.0,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);

      print('🔄 Total distance reset to 0');
    } catch (e) {
      print('❌ Error resetting total distance: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getDistanceStats() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final response =
          await _client
              .from('user_stats')
              .select('total_distance_km, updated_at')
              .eq('user_id', user.id)
              .maybeSingle();

      if (response != null) {
        final totalDistance = response['total_distance_km']?.toDouble() ?? 0.0;
        final lastUpdated =
            response['updated_at'] != null
                ? DateTime.parse(response['updated_at'])
                : DateTime.now();

        return {
          'total_distance_km': totalDistance,
          'total_distance_formatted': formatDistance(totalDistance),
          'last_updated': lastUpdated,
          'tracking_active':
              DateTime.now().difference(lastUpdated).inMinutes < 5,
        };
      }

      return {
        'total_distance_km': 0.0,
        'total_distance_formatted': '0 m',
        'last_updated': DateTime.now(),
        'tracking_active': false,
      };
    } catch (e) {
      print('❌ Error getting distance stats: $e');
      return {
        'total_distance_km': 0.0,
        'total_distance_formatted': '0 m',
        'last_updated': DateTime.now(),
        'tracking_active': false,
      };
    }
  }

  static Future<void> _updatePlacesCount(String userId) async {
    try {
      final placesCount = await _getPlacesCount(userId);

      // Use the same update strategy to avoid conflicts
      final updateResponse = await _client
          .from('user_stats')
          .update({
            'total_places': placesCount,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId);

      // If no record exists, create one
      if (updateResponse.isEmpty) {
        try {
          await _client.from('user_stats').insert({
            'user_id': userId,
            'total_distance_km': 0.0,
            'total_places': placesCount,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (insertError) {
          // Handle race condition
          if (insertError.toString().contains('duplicate key value')) {
            await _client
                .from('user_stats')
                .update({
                  'total_places': placesCount,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('user_id', userId);
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      print('❌ Error updating places count: $e');
    }
  }

  /// Calculate distance between two coordinates using Haversine formula
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // Validate coordinates
    if (!_isValidLatitude(lat1) ||
        !_isValidLatitude(lat2) ||
        !_isValidLongitude(lon1) ||
        !_isValidLongitude(lon2)) {
      throw ArgumentError('Invalid coordinates provided');
    }

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

  static bool _isValidLatitude(double latitude) {
    return latitude >= -90.0 && latitude <= 90.0;
  }

  static bool _isValidLongitude(double longitude) {
    return longitude >= -180.0 && longitude <= 180.0;
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

      if (radiusMeters <= 0) {
        throw ArgumentError('Radius must be positive');
      }

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

        final double distance = calculateDistance(
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

  /// Update visit count for an existing place with optimistic concurrency
  static Future<bool> updatePlaceVisitCount(String placeId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (placeId.isEmpty) {
        throw ArgumentError('Place ID cannot be empty');
      }

      // Use a single query to increment visit count atomically
      final response = await _client.rpc(
        'increment_place_visit',
        params: {'place_id': placeId, 'user_id': user.id},
      );

      if (response == null || response == 0) {
        print('❌ Place not found or not owned by user');
        return false;
      }

      print('✅ Updated visit count for place $placeId');
      return true;
    } catch (e) {
      // Fallback to the original method if RPC doesn't exist
      return await _updatePlaceVisitCountFallback(placeId);
    }
  }

  /// Fallback method for updating visit count
  static Future<bool> _updatePlaceVisitCountFallback(String placeId) async {
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
              .maybeSingle();

      if (currentPlace == null) {
        print('❌ Place not found or not owned by user');
        return false;
      }

      final currentVisitCount = currentPlace['visit_count'] as int? ?? 0;

      // Update with incremented visit count
      await _client
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
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Validate inputs
      if (placeName.trim().isEmpty) {
        throw ArgumentError('Place name cannot be empty');
      }
      if (!_isValidLatitude(latitude) || !_isValidLongitude(longitude)) {
        throw ArgumentError('Invalid coordinates');
      }
      if (radiusMeters <= 0) {
        throw ArgumentError('Radius must be positive');
      }

      print('💾 savePlace: Starting to save place');
      print('📍 Coordinates: $latitude, $longitude');
      print('📝 Address: $address');

      bool isNewPlace = true;

      // Check for nearby places first
      if (address != null && address.trim().isNotEmpty) {
        final nearbyPlace = await findNearbyPlace(
          latitude: latitude,
          longitude: longitude,
          address: address.trim(),
          radiusMeters: radiusMeters,
        );

        if (nearbyPlace != null) {
          // Update existing place visit count
          print('📍 Found nearby place, updating visit count...');
          final success = await updatePlaceVisitCount(nearbyPlace['id']);

          if (success) {
            print('✅ Successfully updated visit count for existing place');
            isNewPlace = false;
          } else {
            print('⚠️ Failed to update visit count, will save as new place');
          }
        }
      }

      if (isNewPlace) {
        // If no nearby place found or address is null, save as new place
        print('💾 Saving as new place...');
        await _client.from('user_places').insert({
          'user_id': user.id,
          'place_name': placeName.trim(),
          'latitude': latitude,
          'longitude': longitude,
          'address': address?.trim(),
          'place_type': placeType,
          'visit_count': 1, // Initialize with 1 visit
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        print('✅ New place saved successfully');

        // Update places count in user_stats
        await _updatePlacesCount(user.id);
      }
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

      if (decimalPlaces < 1 || decimalPlaces > 10) {
        throw ArgumentError('Decimal places must be between 1 and 10');
      }

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
    if (decimalPlaces < 0) return coordinate;
    double multiplier = pow(10, decimalPlaces).toDouble();
    return (coordinate * multiplier).round() / multiplier;
  }

  /// Cleanup existing duplicates (run this once to clean your database)
  static Future<int> mergeDuplicatePlaces({double radiusMeters = 50.0}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (radiusMeters <= 0) {
        throw ArgumentError('Radius must be positive');
      }

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

        Set<String> processedIds = {};

        for (int i = 0; i < addressGroup.length; i++) {
          final place1 = addressGroup[i];
          if (processedIds.contains(place1['id'])) continue;

          List<Map<String, dynamic>> duplicates = [place1];

          for (int j = i + 1; j < addressGroup.length; j++) {
            final place2 = addressGroup[j];
            if (processedIds.contains(place2['id'])) continue;

            final distance = calculateDistance(
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

      // Delete duplicate places in batches for better performance
      if (idsToDelete.isNotEmpty) {
        print('🗑️ Deleting ${idsToDelete.length} duplicate places...');

        // Delete in batches of 10 to avoid timeouts
        const batchSize = 10;
        int deletedCount = 0;

        for (int i = 0; i < idsToDelete.length; i += batchSize) {
          final batch = idsToDelete.skip(i).take(batchSize).toList();

          try {
            await _client.from('user_places').delete().inFilter('id', batch);
            deletedCount += batch.length;
          } catch (e) {
            print('⚠️ Failed to delete batch: $e');
            // Try individual deletes for this batch
            for (final id in batch) {
              try {
                await _client.from('user_places').delete().eq('id', id);
                deletedCount++;
              } catch (individualError) {
                print('⚠️ Failed to delete place $id: $individualError');
              }
            }
          }
        }

        print('✅ Successfully deleted $deletedCount duplicate places');

        // Update places count after cleanup
        await _updatePlacesCount(user.id);
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
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Validate coordinates
      if (!_isValidLatitude(startLatitude) ||
          !_isValidLatitude(endLatitude) ||
          !_isValidLongitude(startLongitude) ||
          !_isValidLongitude(endLongitude)) {
        throw ArgumentError('Invalid coordinates');
      }

      // Validate optional parameters
      if (distanceKm != null && distanceKm < 0) {
        throw ArgumentError('Distance cannot be negative');
      }
      if (durationMinutes != null && durationMinutes < 0) {
        throw ArgumentError('Duration cannot be negative');
      }

      await _client.from('user_routes').insert({
        'user_id': user.id,
        'start_latitude': startLatitude,
        'start_longitude': startLongitude,
        'end_latitude': endLatitude,
        'end_longitude': endLongitude,
        'start_address': startAddress?.trim(),
        'end_address': endAddress?.trim(),
        'distance_km': distanceKm,
        'duration_minutes': durationMinutes,
        'route_type': routeType,
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Route saved successfully');
    } catch (e) {
      print('❌ Error saving route: $e');
      rethrow;
    }
  }

  // Method to get recent places
  static Future<List<UserPlace>> getRecentPlaces({int limit = 10}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (limit <= 0) {
        throw ArgumentError('Limit must be positive');
      }

      final response = await _client
          .from('user_places')
          .select('*')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false)
          .limit(limit);

      return response.map((place) => UserPlace.fromJson(place)).toList();
    } catch (e) {
      print('❌ Error getting recent places: $e');
      return [];
    }
  }

  // Method to get recent routes
  static Future<List<UserRoute>> getRecentRoutes({int limit = 10}) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (limit <= 0) {
        throw ArgumentError('Limit must be positive');
      }

      final response = await _client
          .from('user_routes')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit);

      return response.map((route) => UserRoute.fromJson(route)).toList();
    } catch (e) {
      print('❌ Error getting recent routes: $e');
      return [];
    }
  }

  // Method to format distance for display
  static String formatDistance(double distanceKm) {
    if (distanceKm < 0) return '0 m';

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
  final DateTime? updatedAt;

  UserPlace({
    required this.id,
    required this.placeName,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.placeType,
    required this.visitCount,
    required this.createdAt,
    this.updatedAt,
  });

  factory UserPlace.fromJson(Map<String, dynamic> json) {
    return UserPlace(
      id: json['id'] ?? '',
      placeName: json['place_name'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      address: json['address'],
      placeType: json['place_type'] ?? 'saved',
      visitCount: json['visit_count'] ?? 1,
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      updatedAt:
          json['updated_at'] != null
              ? DateTime.parse(json['updated_at'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'place_name': placeName,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'place_type': placeType,
      'visit_count': visitCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
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
      id: json['id'] ?? '',
      startLatitude: (json['start_latitude'] ?? 0.0).toDouble(),
      startLongitude: (json['start_longitude'] ?? 0.0).toDouble(),
      endLatitude: (json['end_latitude'] ?? 0.0).toDouble(),
      endLongitude: (json['end_longitude'] ?? 0.0).toDouble(),
      startAddress: json['start_address'],
      endAddress: json['end_address'],
      distanceKm: json['distance_km']?.toDouble(),
      durationMinutes: json['duration_minutes'],
      routeType: json['route_type'] ?? 'navigation',
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'start_latitude': startLatitude,
      'start_longitude': startLongitude,
      'end_latitude': endLatitude,
      'end_longitude': endLongitude,
      'start_address': startAddress,
      'end_address': endAddress,
      'distance_km': distanceKm,
      'duration_minutes': durationMinutes,
      'route_type': routeType,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get formattedDistance =>
      distanceKm != null
          ? UserStatsService.formatDistance(distanceKm!)
          : 'Unknown';
}
