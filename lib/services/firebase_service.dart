// lib/services/firebase_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:map/data/chat_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final supabase.SupabaseClient _supabase =
      supabase.Supabase.instance.client;

  // Initialize Firebase only
  static Future<void> initialize() async {
    await Firebase.initializeApp();
    print('✅ Firebase initialized (Firestore only)');
  }

  // Get current user from Supabase directly
  static supabase.User? get currentUser => _supabase.auth.currentUser;
  static String? get currentUserId => currentUser?.id;
  static bool get isAuthenticated => currentUser != null;

  // Test Firestore connection
  static Future<bool> testFirebaseConnection() async {
    try {
      final user = currentUser;
      if (user == null) {
        print('❌ No user authenticated');
        return false;
      }

      // Try to read from Firestore (this will work with permissive rules)
      final doc = await _firestore.collection('users').doc(user.id).get();
      print('✅ Firestore connection test successful');
      print('   - User document exists: ${doc.exists}');
      print('   - User ID: ${user.id}');
      print('   - User email: ${user.email}');

      return true;
    } catch (e) {
      print('❌ Firestore connection test failed: $e');
      return false;
    }
  }

  // Sync user to Firestore (called manually)
  static Future<void> syncUserToFirebase() async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.id).set({
        'id': user.id,
        'email': user.email,
        'name':
            user.userMetadata?['name'] ?? user.email?.split('@')[0] ?? 'User',
        'avatar_url': user.userMetadata?['avatar_url'],
        'last_seen': FieldValue.serverTimestamp(),
        'is_online': true,
        'created_at': user.createdAt,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ User synced to Firestore: ${user.email}');
    } catch (e) {
      print('❌ Error syncing user to Firestore: $e');
      rethrow;
    }
  }

  // Update user online status
  static Future<void> updateOnlineStatus(bool isOnline) async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.id).update({
        'is_online': isOnline,
        'last_seen': FieldValue.serverTimestamp(),
      });
      print('✅ Updated online status: $isOnline for ${user.email}');
    } catch (e) {
      print('❌ Error updating online status: $e');
    }
  }

  // Get unread message count for a user
  static Stream<int> getUnreadMessageCount() {
    final user = currentUser;
    if (user == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: user.id)
        .snapshots()
        .asyncMap((chatSnapshot) async {
          int totalUnread = 0;

          for (var chatDoc in chatSnapshot.docs) {
            final chat = Chat.fromFirestore(chatDoc);

            // Skip if current user sent the last message
            if (chat.lastSenderId == user.id) continue;

            // Count unread messages in this chat
            final unreadSnapshot =
                await _firestore
                    .collection('chats')
                    .doc(chatDoc.id)
                    .collection('messages')
                    .where('sender_id', isNotEqualTo: user.id)
                    .where('read_by', whereNotIn: [user.id])
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
    final user = currentUser;
    if (user == null) return;

    try {
      final updates = <String, dynamic>{
        'last_seen': FieldValue.serverTimestamp(),
      };

      if (name != null) updates['name'] = name;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _firestore.collection('users').doc(user.id).update(updates);
      print('✅ User profile updated successfully');
    } catch (e) {
      print('❌ Error updating user profile: $e');
      rethrow;
    }
  }

  // Send a message
  static Future<void> sendMessage({
    required String chatId,
    required String message,
    String? imageUrl,
  }) async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
            'sender_id': user.id,
            'sender_email': user.email,
            'sender_name':
                user.userMetadata?['name'] ??
                user.email?.split('@')[0] ??
                'User',
            'message': message,
            'image_url': imageUrl,
            'timestamp': FieldValue.serverTimestamp(),
            'read_by': [user.id], // Mark as read by sender
          });

      // Update chat's last message
      await _firestore.collection('chats').doc(chatId).set({
        'last_message': message.isNotEmpty ? message : '📷 Image',
        'last_message_time': FieldValue.serverTimestamp(),
        'last_sender_id': user.id,
      }, SetOptions(merge: true));

      print('✅ Message sent successfully');
    } catch (e) {
      print('❌ Error sending message: $e');
      rethrow;
    }
  }

  // Create or get a chat between two users
  static Future<String> createOrGetChat(String otherUserId) async {
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Generate consistent chat ID
    final List<String> userIds = [user.id, otherUserId];
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
          'created_by': user.id,
        });
        print('✅ New chat created: $chatId');
      } else {
        print('✅ Existing chat found: $chatId');
      }

      return chatId;
    } catch (e) {
      print('❌ Error creating/getting chat: $e');
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
    final user = currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: user.id)
        .orderBy('last_message_time', descending: true)
        .snapshots();
  }

  // Get all users (for finding people to chat with)
  static Stream<QuerySnapshot> getUsersStream() {
    return _firestore.collection('users').orderBy('name').snapshots();
  }

  // Mark messages as read
  static Future<void> markMessagesAsRead(String chatId) async {
    final user = currentUser;
    if (user == null) return;

    try {
      final unreadMessages =
          await _firestore
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('read_by', whereNotIn: [user.id])
              .get();

      final batch = _firestore.batch();

      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'read_by': FieldValue.arrayUnion([user.id]),
        });
      }

      await batch.commit();
      print('✅ Messages marked as read');
    } catch (e) {
      print('❌ Error marking messages as read: $e');
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
      print('❌ Error searching users: $e');
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
      print('✅ Message deleted');
    } catch (e) {
      print('❌ Error deleting message: $e');
      rethrow;
    }
  }
}
