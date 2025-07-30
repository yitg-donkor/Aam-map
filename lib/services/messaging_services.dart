// lib/services/messaging_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:map/data/chat_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessagingService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Search users by username from Supabase
  static Future<List<ChatUser>> searchUsers(String query) async {
    if (query.length < 2) return [];

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('users')
          .select(
            'id, username, email, name, display_name, avatar_url, created_at',
          )
          .neq('id', currentUserId)
          .ilike('username', '%$query%')
          .limit(10);

      return (response as List).map((userData) {
        return ChatUser.fromSupabase(userData);
      }).toList();
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  // Get user details from Supabase by ID
  static Future<ChatUser?> getUserById(String userId) async {
    try {
      final response =
          await _supabase
              .from('users')
              .select(
                'id, username, email, name, display_name, avatar_url, created_at',
              )
              .eq('id', userId)
              .single();

      return ChatUser.fromSupabase(response);
    } catch (e) {
      print('Error getting user by ID: $e');
      return null;
    }
  }

  // Get multiple users from Supabase by IDs
  static Future<Map<String, ChatUser>> getUsersByIds(
    List<String> userIds,
  ) async {
    try {
      if (userIds.isEmpty) return {};

      final response = await _supabase
          .from('users')
          .select(
            'id, username, email, name, display_name, avatar_url, created_at',
          )
          .inFilter('id', userIds);

      final users = <String, ChatUser>{};
      for (final userData in response) {
        final user = ChatUser.fromSupabase(userData);
        users[user.id] = user;
      }
      return users;
    } catch (e) {
      print('Error getting users by IDs: $e');
      return {};
    }
  }

  // Create or get existing direct conversation
  static Future<String> createDirectConversation(ChatUser otherUser) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Check if conversation already exists
      final existingConversations =
          await _firestore
              .collection('chats')
              .where('participants', arrayContains: currentUserId)
              .where('is_group', isEqualTo: false)
              .get();

      for (var doc in existingConversations.docs) {
        final chat = Chat.fromFirestore(doc);
        if (chat.participants.contains(otherUser.id) &&
            chat.participants.length == 2) {
          return doc.id;
        }
      }

      // Create new conversation
      final chatRef = _firestore.collection('chats').doc();
      await chatRef.set({
        'participants': [currentUserId, otherUser.id],
        'last_message': null,
        'last_message_time': null,
        'last_sender_id': null,
        'created_at': FieldValue.serverTimestamp(),
        'is_group': false,
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

      // Create conversation in Firestore
      final allParticipants = [currentUserId, ...members.map((m) => m.id)];
      final chatRef = _firestore.collection('chats').doc();

      await chatRef.set({
        'participants': allParticipants,
        'last_message': null,
        'last_message_time': null,
        'last_sender_id': null,
        'created_at': FieldValue.serverTimestamp(),
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

  // Get chat participants with their user details
  static Future<List<ChatUser>> getChatParticipants(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return [];

      final chat = Chat.fromFirestore(chatDoc);
      final userMap = await getUsersByIds(chat.participants);

      return chat.participants
          .map((id) => userMap[id])
          .where((user) => user != null)
          .cast<ChatUser>()
          .toList();
    } catch (e) {
      print('Error getting chat participants: $e');
      return [];
    }
  }

  // Get chat with participant details
  static Future<ChatWithUsers?> getChatWithUsers(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        print('Chat document not found: $chatId');
        return null;
      }

      final chat = Chat.fromFirestore(chatDoc);
      print('Chat loaded: ${chat.id}, participants: ${chat.participants}');

      if (chat.participants.isEmpty) {
        print('Chat has no participants: $chatId');
        return ChatWithUsers(chat: chat, participants: []);
      }

      final userMap = await getUsersByIds(chat.participants);
      print('Users loaded: ${userMap.keys.toList()}');

      final participantsList =
          chat.participants
              .map((id) => userMap[id])
              .where((user) => user != null)
              .cast<ChatUser>()
              .toList();

      print(
        'Final participants: ${participantsList.map((p) => '${p.id}:${p.displayName}').toList()}',
      );

      return ChatWithUsers(chat: chat, participants: participantsList);
    } catch (e) {
      print('Error getting chat with users: $e');
      return null;
    }
  }
}

// Helper class to combine chat with user details
class ChatWithUsers {
  final Chat chat;
  final List<ChatUser> participants;

  ChatWithUsers({required this.chat, required this.participants});

  ChatUser? getOtherUser(String currentUserId) {
    if (chat.isGroup) return null;
    if (participants.isEmpty) return null;

    try {
      return participants.firstWhere((user) => user.id != currentUserId);
    } catch (e) {
      print(
        'Error getting other user: $e - participants: ${participants.map((p) => p.id).toList()}, currentUserId: $currentUserId',
      );
      return participants.isNotEmpty ? participants.first : null;
    }
  }

  String getDisplayName(String currentUserId) {
    if (chat.isGroup) {
      return chat.groupName ?? 'Group Chat';
    }
    final otherUser = getOtherUser(currentUserId);
    return otherUser?.displayName ?? 'Unknown User';
  }
}
