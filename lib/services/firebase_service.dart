// lib/services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:map/data/chat_model.dart';
import 'package:map/services/auth_bridge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Initialize Firebase
  static Future<void> initialize() async {
    await Firebase.initializeApp();
    await AuthBridgeService.initialize();
  }

  // Get current user from AuthBridgeService
  static String? get currentUserId => AuthBridgeService.currentUserId;
  static bool get isAuthenticated => AuthBridgeService.isAuthenticated;

  // Get current Supabase user (use specific import to avoid conflicts)
  static supabase.User? get currentUser =>
      AuthBridgeService.currentSupabaseUser;

  // Test Firebase connection
  static Future<bool> testFirebaseConnection() async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        print('❌ No user authenticated');
        return false;
      }

      // Try to read from Firestore
      final doc = await _firestore.collection('users').doc(userId).get();
      print('✅ Firebase connection test successful');
      print('   - User document exists: ${doc.exists}');
      print('   - User ID: $userId');

      return true;
    } catch (e) {
      print('❌ Firebase connection test failed: $e');
      return false;
    }
  }

  // Get unread message count for a user
  static Stream<int> getUnreadMessageCount() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .snapshots()
        .asyncMap((chatSnapshot) async {
          int totalUnread = 0;

          for (var chatDoc in chatSnapshot.docs) {
            final chat = Chat.fromFirestore(chatDoc);

            // Skip if current user sent the last message
            if (chat.lastSenderId == userId) continue;

            // Count unread messages in this chat
            final unreadSnapshot =
                await _firestore
                    .collection('chats')
                    .doc(chatDoc.id)
                    .collection('messages')
                    .where('sender_id', isNotEqualTo: userId)
                    .where('read_by', whereNotIn: [userId])
                    .get();

            totalUnread += unreadSnapshot.docs.length;
          }

          return totalUnread;
        });
  }

  // Update user profile information
  static Future<void> updateUserProfile({
    String? name,
    String? avatarUrl,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      final updates = <String, dynamic>{
        'last_seen': FieldValue.serverTimestamp(),
      };

      if (name != null) updates['name'] = name;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _firestore.collection('users').doc(userId).update(updates);
      print('✅ User profile updated successfully');
    } catch (e) {
      print('❌ Error updating user profile: $e');
      rethrow;
    }
  }

  // Update user online status
  static Future<void> updateOnlineStatus(bool isOnline) async {
    await AuthBridgeService.updateOnlineStatus(isOnline);
  }

  // Send a message
  static Future<void> sendMessage({
    required String chatId,
    required String message,
    String? imageUrl,
  }) async {
    final userId = currentUserId;
    final supabaseUser = AuthBridgeService.currentSupabaseUser;
    if (userId == null || supabaseUser == null) return;

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
            'sender_id': userId,
            'sender_email': supabaseUser.email,
            'sender_name':
                supabaseUser.userMetadata?['name'] ??
                supabaseUser.email?.split('@')[0],
            'message': message,
            'image_url': imageUrl,
            'timestamp': FieldValue.serverTimestamp(),
            'read_by': [userId], // Mark as read by sender
          });

      // Update chat's last message
      await _firestore.collection('chats').doc(chatId).set({
        'last_message': message.isNotEmpty ? message : '📷 Image',
        'last_message_time': FieldValue.serverTimestamp(),
        'last_sender_id': userId,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  // Create or get a chat between two users
  static Future<String> createOrGetChat(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    // Generate consistent chat ID
    final List<String> userIds = [userId, otherUserId];
    userIds.sort();
    final chatId = userIds.join('_');

    try {
      // Check if chat exists
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();

      if (!chatDoc.exists) {
        // Create new chat
        await _firestore.collection('chats').doc(chatId).set({
          'participants': userIds,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': userId,
        });
      }

      return chatId;
    } catch (e) {
      print('Error creating/getting chat: $e');
      rethrow;
    }
  }

  // Get messages stream for a chat
  static Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Get user's chats stream
  static Stream<QuerySnapshot> getUserChatsStream() {
    final userId = currentUserId;
    if (userId == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .orderBy('last_message_time', descending: true)
        .snapshots();
  }

  // Get all users (for finding people to chat with)
  static Stream<QuerySnapshot> getUsersStream() {
    return _firestore.collection('users').orderBy('name').snapshots();
  }

  // Mark messages as read
  static Future<void> markMessagesAsRead(String chatId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      final unreadMessages =
          await _firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('read_by', whereNotIn: [userId])
              .get();

      final batch = _firestore.batch();

      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'read_by': FieldValue.arrayUnion([userId]),
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Search users
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final snapshot =
          await _firestore
              .collection('users')
              .where('name', isGreaterThanOrEqualTo: query)
              .where('name', isLessThanOrEqualTo: query + '\uf8ff')
              .limit(20)
              .get();

      return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Delete a message
  static Future<void> deleteMessage(String chatId, String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      print('Error deleting message: $e');
      rethrow;
    }
  }
}
