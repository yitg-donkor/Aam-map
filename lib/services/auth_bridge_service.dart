// lib/services/auth_bridge_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthBridgeService {
  static final firebase_auth.FirebaseAuth _firebaseAuth =
      firebase_auth.FirebaseAuth.instance;
  static final supabase.SupabaseClient _supabase =
      supabase.Supabase.instance.client;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static StreamSubscription<supabase.AuthState>? _authSubscription;
  static bool _isInitialized = false;
  static String? _lastSyncedUserId;

  // Get current Supabase user
  static supabase.User? get currentSupabaseUser => _supabase.auth.currentUser;

  // Get current Firebase user
  static firebase_auth.User? get currentFirebaseUser =>
      _firebaseAuth.currentUser;

  /// Initialize the auth bridge - call this when your app starts
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🔄 Initializing Auth Bridge...');

      // Listen to Supabase auth changes
      _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        final user = data.session?.user;

        debugPrint('🔔 Auth Bridge: Supabase auth changed - $event');

        if (event == supabase.AuthChangeEvent.signedIn && user != null) {
          _signInToFirebase(user);
        } else if (event == supabase.AuthChangeEvent.signedOut) {
          _signOutFromFirebase();
        } else if (event == supabase.AuthChangeEvent.userUpdated &&
            user != null) {
          _syncUserToFirestore(user);
        }
      });

      // If user is already signed in to Supabase, sign them into Firebase
      final currentUser = currentSupabaseUser;
      if (currentUser != null) {
        debugPrint('🔍 Found existing Supabase user, syncing to Firebase...');
        await _signInToFirebase(currentUser);
      }

      _isInitialized = true;
      debugPrint('✅ Auth Bridge initialized successfully');
    } catch (e) {
      debugPrint('❌ Auth Bridge initialization failed: $e');
      rethrow;
    }
  }

  /// Clean up the auth bridge
  static Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    _isInitialized = false;
    _lastSyncedUserId = null;
    debugPrint('🧹 Auth Bridge disposed');
  }

  /// Sign in to Firebase using Supabase user data
  static Future<void> _signInToFirebase(supabase.User supabaseUser) async {
    try {
      debugPrint('🔄 Signing in to Firebase for user: ${supabaseUser.email}');

      // Check if already signed in to Firebase
      final currentFirebaseUser = _firebaseAuth.currentUser;
      if (currentFirebaseUser != null) {
        debugPrint('✅ Already signed in to Firebase');
        await _syncUserToFirestore(supabaseUser);
        return;
      }

      // Sign in anonymously to Firebase (this gives us Firebase Auth context)
      final credential = await _firebaseAuth.signInAnonymously();
      debugPrint('✅ Firebase anonymous sign-in successful');

      // Sync user data to Firestore
      await _syncUserToFirestore(supabaseUser);

      debugPrint(
        '✅ Firebase auth bridge setup complete for: ${supabaseUser.email}',
      );
    } catch (e) {
      debugPrint('❌ Error signing in to Firebase: $e');
      // Don't rethrow - allow app to continue even if Firebase auth fails
    }
  }

  /// Sign out from Firebase
  static Future<void> _signOutFromFirebase() async {
    try {
      // Update offline status before signing out
      final supabaseUser = currentSupabaseUser;
      if (supabaseUser != null) {
        await _updateOfflineStatus(supabaseUser.id);
      }

      await _firebaseAuth.signOut();
      _lastSyncedUserId = null;
      debugPrint('✅ Signed out from Firebase');
    } catch (e) {
      debugPrint('❌ Error signing out from Firebase: $e');
    }
  }

  /// Sync Supabase user data to Firestore
  static Future<void> _syncUserToFirestore(supabase.User supabaseUser) async {
    try {
      // Avoid unnecessary syncs
      if (_lastSyncedUserId == supabaseUser.id) {
        debugPrint('⏭️ User already synced, skipping...');
        return;
      }

      debugPrint('🔄 Syncing user to Firestore: ${supabaseUser.email}');

      // Use Supabase user ID as the document ID in Firestore
      await _firestore.collection('users').doc(supabaseUser.id).set({
        'id': supabaseUser.id,
        'email': supabaseUser.email,
        'name':
            supabaseUser.userMetadata?['name'] ??
            supabaseUser.email?.split('@')[0] ??
            'User',
        'avatar_url': supabaseUser.userMetadata?['avatar_url'],
        'last_seen': FieldValue.serverTimestamp(),
        'is_online': true,
        'created_at': supabaseUser.createdAt,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _lastSyncedUserId = supabaseUser.id;
      debugPrint('✅ User synced to Firestore: ${supabaseUser.email}');
    } catch (e) {
      debugPrint('❌ Error syncing user to Firestore: $e');
      // Don't rethrow - allow app to continue
    }
  }

  /// Update user online status
  static Future<void> updateOnlineStatus(bool isOnline) async {
    final supabaseUser = currentSupabaseUser;
    if (supabaseUser == null) {
      debugPrint('⚠️ Cannot update online status - no authenticated user');
      return;
    }

    try {
      await _firestore.collection('users').doc(supabaseUser.id).update({
        'is_online': isOnline,
        'last_seen': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '✅ Updated online status: $isOnline for ${supabaseUser.email}',
      );
    } catch (e) {
      debugPrint('❌ Error updating online status: $e');
    }
  }

  /// Update offline status specifically
  static Future<void> _updateOfflineStatus(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'is_online': false,
        'last_seen': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Updated offline status for user: $userId');
    } catch (e) {
      debugPrint('❌ Error updating offline status: $e');
    }
  }

  /// Check if user is properly authenticated
  static bool get isAuthenticated {
    final supabaseUser = currentSupabaseUser;
    final firebaseUser = currentFirebaseUser;
    final isAuth = supabaseUser != null && firebaseUser != null;

    if (!isAuth) {
      debugPrint('⚠️ Authentication check failed:');
      debugPrint('   - Supabase user: ${supabaseUser?.email ?? "null"}');
      debugPrint('   - Firebase user: ${firebaseUser?.uid ?? "null"}');
    }

    return isAuth;
  }

  /// Get current user ID (using Supabase ID)
  static String? get currentUserId => currentSupabaseUser?.id;

  /// Test the auth bridge connection
  static Future<bool> testConnection() async {
    try {
      final supabaseUser = currentSupabaseUser;
      if (supabaseUser == null) {
        debugPrint('❌ Auth Bridge Test: No Supabase user');
        return false;
      }

      final firebaseUser = currentFirebaseUser;
      if (firebaseUser == null) {
        debugPrint('❌ Auth Bridge Test: No Firebase user');
        return false;
      }

      // Test Firestore access
      final doc =
          await _firestore.collection('users').doc(supabaseUser.id).get();

      debugPrint('✅ Auth Bridge Test Results:');
      debugPrint('   - Supabase User: ${supabaseUser.email}');
      debugPrint('   - Firebase User: ${firebaseUser.uid}');
      debugPrint('   - Firestore Doc Exists: ${doc.exists}');
      debugPrint('   - Is Authenticated: $isAuthenticated');

      return true;
    } catch (e) {
      debugPrint('❌ Auth Bridge Test Failed: $e');
      return false;
    }
  }

  /// Force sync current user (useful for troubleshooting)
  static Future<void> forceSyncUser() async {
    final user = currentSupabaseUser;
    if (user != null) {
      _lastSyncedUserId = null; // Reset to force sync
      await _syncUserToFirestore(user);
    }
  }
}
