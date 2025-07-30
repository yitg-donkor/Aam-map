// lib/services/messaging_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:map/data/chat_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagingService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Search users by username
  static Future<List<ChatUser>> searchUsers(String query) async {
    if (query.length < 2) return [];

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('users')
          .select('id, username, department, class, avatar_url')
          .neq('id', currentUserId)
          .ilike('username', '%$query%')
          .limit(10);

      return (response as List).map((userData) {
        return ChatUser(
          id: userData['id'],
          username: userData['username'],
          email: '${userData['username']}@example.com', // Placeholder email
          name: userData['username'], // Using username as name
          avatarUrl: userData['avatar_url'],
          isOnline: false, // Default offline status
          lastSeen: null,
          createdAt: null,
        );
      }).toList();
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Create or get existing direct conversation
  static Future<String> createDirectConversation(ChatUser otherUser) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Check if conversation already exists - using your existing Chat structure
      final existingConversations =
          await _firestore
              .collection('chats')
              .where('participants', arrayContains: currentUserId)
              .get();

      for (var doc in existingConversations.docs) {
        final chat = Chat.fromFirestore(doc);
        if (chat.participants.contains(otherUser.id) &&
            chat.participants.length == 2) {
          return doc.id;
        }
      }

      // Create new conversation using your existing Chat structure
      final chatRef = _firestore.collection('chats').doc();
      await chatRef.set({
        'participants': [currentUserId, otherUser.id],
        'last_message': null,
        'last_message_time': null,
        'last_sender_id': null,
        'created_at': FieldValue.serverTimestamp(),
      });

      return chatRef.id;
    } catch (e) {
      print('Error creating direct conversation: $e');
      throw e;
    }
  }

  // Create group chat
  static Future<String> createGroupChat({
    required String groupName,
    String? description,
    required List<ChatUser> members,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Create group in Supabase
      final groupResponse =
          await _supabase
              .from('groups')
              .insert({
                'name': groupName,
                'description': description,
                'created_by': currentUserId,
              })
              .select()
              .single();

      final groupId = groupResponse['id'];

      // Add members to group
      final memberInserts = [
        {'group_id': groupId, 'user_id': currentUserId, 'role': 'admin'},
        ...members.map(
          (member) => {
            'group_id': groupId,
            'user_id': member.id,
            'role': 'member',
          },
        ),
      ];

      await _supabase.from('group_members').insert(memberInserts);

      // Create conversation in Firestore using your existing Chat structure
      final allParticipants = [currentUserId, ...members.map((m) => m.id)];
      final chatRef = _firestore.collection('chats').doc();

      await chatRef.set({
        'participants': allParticipants,
        'last_message': null,
        'last_message_time': null,
        'last_sender_id': null,
        'created_at': FieldValue.serverTimestamp(),
        // Add group-specific metadata
        'is_group': true,
        'group_name': groupName,
        'group_description': description,
        'group_admin_ids': [currentUserId],
        'supabase_group_id': groupId,
      });

      return chatRef.id;
    } catch (e) {
      print('Error creating group chat: $e');
      throw e;
    }
  }
}
