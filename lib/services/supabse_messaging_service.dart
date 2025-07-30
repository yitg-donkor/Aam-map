// lib/services/supabase_messaging_service.dart
import 'dart:io';
import 'package:map/data/chat_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseMessagingService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Get current user ID
  static String? get currentUserId => _supabase.auth.currentUser?.id;

  // Get current user info
  static Future<ChatUser?> getCurrentUser() async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final response =
          await _supabase.from('users').select('*').eq('id', userId).single();

      return ChatUser.fromSupabase(response);
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }

  // Search users by username
  static Future<List<ChatUser>> searchUsers(String query) async {
    if (query.length < 2) return [];

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('users')
          .select('*')
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

  // Get user by ID
  static Future<ChatUser?> getUserById(String userId) async {
    try {
      final response =
          await _supabase.from('users').select('*').eq('id', userId).single();

      return ChatUser.fromSupabase(response);
    } catch (e) {
      print('Error getting user by ID: $e');
      return null;
    }
  }

  // Get multiple users by IDs
  static Future<Map<String, ChatUser>> getUsersByIds(
    List<String> userIds,
  ) async {
    try {
      if (userIds.isEmpty) return {};

      final response = await _supabase
          .from('users')
          .select('*')
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
      final existingChats = await _supabase
          .from('chats')
          .select('*')
          .contains('participants', [currentUserId])
          .eq('is_group', false);

      for (final chatData in existingChats) {
        final chat = Chat.fromSupabase(chatData);
        if (chat.participants.contains(otherUser.id) &&
            chat.participants.length == 2) {
          return chat.id;
        }
      }

      // Create new conversation
      final response =
          await _supabase
              .from('chats')
              .insert({
                'participants': [currentUserId, otherUser.id],
                'is_group': false,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .select()
              .single();

      return response['id'];
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

      // Create group in groups table first
      final groupResponse =
          await _supabase
              .from('groups')
              .insert({
                'name': groupName,
                'description': description,
                'created_by': currentUserId,
                'created_at': DateTime.now().toIso8601String(),
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

      // Create chat
      final allParticipants = [currentUserId, ...members.map((m) => m.id)];
      final chatResponse =
          await _supabase
              .from('chats')
              .insert({
                'participants': allParticipants,
                'is_group': true,
                'group_name': groupName,
                'group_description': description,
                'group_admin_ids': [currentUserId],
                'group_id': groupId,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .select()
              .single();

      return chatResponse['id'];
    } catch (e) {
      print('Error creating group chat: $e');
      throw e;
    }
  }

  // Get user's chats
  static Future<List<Chat>> getUserChats() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('chats')
          .select('*')
          .contains('participants', [currentUserId])
          .order('updated_at', ascending: false);

      return (response as List).map((chatData) {
        return Chat.fromSupabase(chatData);
      }).toList();
    } catch (e) {
      print('Error getting user chats: $e');
      return [];
    }
  }

  // Get chat by ID
  static Future<Chat?> getChatById(String chatId) async {
    try {
      final response =
          await _supabase.from('chats').select('*').eq('id', chatId).single();

      return Chat.fromSupabase(response);
    } catch (e) {
      print('Error getting chat by ID: $e');
      return null;
    }
  }

  // Real-time stream for user's chats
  static Stream<List<Chat>> getUserChatsStream() {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return Stream.value([]);

    return _supabase.from('chats').stream(primaryKey: ['id']).map((data) {
      // Filter chats where current user is a participant
      final filteredChats =
          data.where((json) {
            final participants = List<String>.from(json['participants'] ?? []);
            return participants.contains(currentUserId);
          }).toList();

      // Sort by updated_at descending
      filteredChats.sort((a, b) {
        final aUpdated =
            DateTime.tryParse(a['updated_at'] ?? '') ?? DateTime.now();
        final bUpdated =
            DateTime.tryParse(b['updated_at'] ?? '') ?? DateTime.now();
        return bUpdated.compareTo(aUpdated);
      });

      return filteredChats.map((json) => Chat.fromSupabase(json)).toList();
    });
  }

  // Send message
  static Future<ChatMessage> sendMessage({
    required String chatId,
    required String message,
    String? imageUrl,
  }) async {
    try {
      final currentUser = await getCurrentUser();
      if (currentUser == null) throw Exception('User not authenticated');

      final response =
          await _supabase
              .from('messages')
              .insert({
                'chat_id': chatId,
                'sender_id': currentUser.id,
                'sender_email': currentUser.email,
                'sender_name': currentUser.displayName,
                'message': message,
                'image_url': imageUrl,
                'read_by': [currentUser.id], // Mark as read by sender
                'created_at': DateTime.now().toIso8601String(),
              })
              .select()
              .single();

      // Update chat's updated_at timestamp
      await _supabase
          .from('chats')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', chatId);

      return ChatMessage.fromSupabase(response);
    } catch (e) {
      print('Error sending message: $e');
      throw e;
    }
  }

  // Get messages for a chat
  static Future<List<ChatMessage>> getMessages(
    String chatId, {
    int limit = 50,
  }) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List).map((messageData) {
        return ChatMessage.fromSupabase(messageData);
      }).toList();
    } catch (e) {
      print('Error getting messages: $e');
      return [];
    }
  }

  // Real-time stream for messages in a chat
  static Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return _supabase.from('messages').stream(primaryKey: ['id']).map((data) {
      // Filter messages for this chat
      final filteredMessages =
          data.where((json) => json['chat_id'] == chatId).toList();

      // Sort by created_at descending (newest first)
      filteredMessages.sort((a, b) {
        final aCreated =
            DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
        final bCreated =
            DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
        return bCreated.compareTo(aCreated);
      });

      return filteredMessages
          .map((json) => ChatMessage.fromSupabase(json))
          .toList();
    });
  }

  // Mark messages as read
  static Future<void> markMessagesAsRead(String chatId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get unread messages
      final unreadMessages = await _supabase
          .from('messages')
          .select('id, read_by')
          .eq('chat_id', chatId)
          .not(
            'read_by',
            'cs',
            '{$currentUserId}',
          ); // Messages not read by current user

      // Update read_by array for each message
      for (final messageData in unreadMessages) {
        final readBy = List<String>.from(messageData['read_by'] ?? []);
        if (!readBy.contains(currentUserId)) {
          readBy.add(currentUserId);

          await _supabase
              .from('messages')
              .update({'read_by': readBy})
              .eq('id', messageData['id']);
        }
      }

      // Also insert into message_reads table for better tracking
      final messageReads =
          unreadMessages
              .map(
                (msg) => {
                  'message_id': msg['id'],
                  'user_id': currentUserId,
                  'read_at': DateTime.now().toIso8601String(),
                },
              )
              .toList();

      if (messageReads.isNotEmpty) {
        await _supabase
            .from('message_reads')
            .upsert(messageReads, onConflict: 'message_id,user_id');
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Delete message
  static Future<void> deleteMessage(String messageId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Get the message to check ownership
      final message = await getMessageById(messageId);
      if (message == null) throw Exception('Message not found');

      if (message.senderId != currentUserId) {
        throw Exception('You can only delete your own messages');
      }

      await _supabase.from('messages').delete().eq('id', messageId);
    } catch (e) {
      print('Error deleting message: $e');
      throw e;
    }
  }

  // Update message
  static Future<void> updateMessage(String messageId, String newMessage) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Get the message to check ownership
      final message = await getMessageById(messageId);
      if (message == null) throw Exception('Message not found');

      if (message.senderId != currentUserId) {
        throw Exception('You can only edit your own messages');
      }

      await _supabase
          .from('messages')
          .update({
            'message': newMessage,
            'updated_at': DateTime.now().toIso8601String(),
            'is_edited': true,
          })
          .eq('id', messageId);
    } catch (e) {
      print('Error updating message: $e');
      throw e;
    }
  }

  // Leave group chat
  static Future<void> leaveGroupChat(String chatId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      // Get current chat
      final chat = await getChatById(chatId);
      if (chat == null || !chat.isGroup) return;

      // Remove user from participants
      final updatedParticipants =
          chat.participants.where((id) => id != currentUserId).toList();
      final updatedAdmins =
          chat.groupAdminIds.where((id) => id != currentUserId).toList();

      // If this was the last admin, promote someone else or delete the group
      if (chat.groupAdminIds.contains(currentUserId) &&
          updatedAdmins.isEmpty &&
          updatedParticipants.isNotEmpty) {
        updatedAdmins.add(updatedParticipants.first);
      }

      await _supabase
          .from('chats')
          .update({
            'participants': updatedParticipants,
            'group_admin_ids': updatedAdmins,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', chatId);

      // Remove from group_members if exists
      if (chat.groupId != null) {
        await _supabase
            .from('group_members')
            .delete()
            .eq('group_id', chat.groupId!)
            .eq('user_id', currentUserId);
      }
    } catch (e) {
      print('Error leaving group chat: $e');
      throw e;
    }
  }

  // Add member to group chat
  static Future<void> addMemberToGroupChat(String chatId, String userId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Get current chat
      final chat = await getChatById(chatId);
      if (chat == null || !chat.isGroup) {
        throw Exception('Chat not found or not a group chat');
      }

      // Check if current user is admin
      if (!chat.groupAdminIds.contains(currentUserId)) {
        throw Exception('Only admins can add members');
      }

      // Check if user is already a member
      if (chat.participants.contains(userId)) {
        throw Exception('User is already a member');
      }

      // Add user to participants
      final updatedParticipants = [...chat.participants, userId];

      await _supabase
          .from('chats')
          .update({
            'participants': updatedParticipants,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', chatId);

      // Add to group_members if group exists
      if (chat.groupId != null) {
        await _supabase.from('group_members').insert({
          'group_id': chat.groupId!,
          'user_id': userId,
          'role': 'member',
          'joined_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Error adding member to group chat: $e');
      throw e;
    }
  }

  // Remove member from group chat
  static Future<void> removeMemberFromGroupChat(
    String chatId,
    String userId,
  ) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Get current chat
      final chat = await getChatById(chatId);
      if (chat == null || !chat.isGroup) {
        throw Exception('Chat not found or not a group chat');
      }

      // Check if current user is admin
      if (!chat.groupAdminIds.contains(currentUserId)) {
        throw Exception('Only admins can remove members');
      }

      // Cannot remove yourself as admin (use leaveGroupChat instead)
      if (userId == currentUserId) {
        throw Exception('Use leaveGroupChat to remove yourself');
      }

      // Remove user from participants
      final updatedParticipants =
          chat.participants.where((id) => id != userId).toList();
      final updatedAdmins =
          chat.groupAdminIds.where((id) => id != userId).toList();

      await _supabase
          .from('chats')
          .update({
            'participants': updatedParticipants,
            'group_admin_ids': updatedAdmins,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', chatId);

      // Remove from group_members if exists
      if (chat.groupId != null) {
        await _supabase
            .from('group_members')
            .delete()
            .eq('group_id', chat.groupId!)
            .eq('user_id', userId);
      }
    } catch (e) {
      print('Error removing member from group chat: $e');
      throw e;
    }
  }

  // Promote member to admin
  static Future<void> promoteMemberToAdmin(String chatId, String userId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Get current chat
      final chat = await getChatById(chatId);
      if (chat == null || !chat.isGroup) {
        throw Exception('Chat not found or not a group chat');
      }

      // Check if current user is admin
      if (!chat.groupAdminIds.contains(currentUserId)) {
        throw Exception('Only admins can promote members');
      }

      // Check if user is a member
      if (!chat.participants.contains(userId)) {
        throw Exception('User is not a member of this group');
      }

      // Check if user is already an admin
      if (chat.groupAdminIds.contains(userId)) {
        throw Exception('User is already an admin');
      }

      // Add to admin list
      final updatedAdmins = [...chat.groupAdminIds, userId];

      await _supabase
          .from('chats')
          .update({
            'group_admin_ids': updatedAdmins,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', chatId);

      // Update role in group_members if exists
      if (chat.groupId != null) {
        await _supabase
            .from('group_members')
            .update({'role': 'admin'})
            .eq('group_id', chat.groupId!)
            .eq('user_id', userId);
      }
    } catch (e) {
      print('Error promoting member to admin: $e');
      throw e;
    }
  }

  // Update user online status
  static Future<void> updateUserOnlineStatus(bool isOnline) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      await _supabase
          .from('users')
          .update({
            'is_online': isOnline,
            'last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', currentUserId);
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  // Get unread message count for a chat
  static Future<int> getUnreadMessageCount(String chatId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 0;

      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('chat_id', chatId)
          .not('read_by', 'cs', '{$currentUserId}')
          .neq('sender_id', currentUserId); // Don't count own messages

      return response.length;
    } catch (e) {
      print('Error getting unread message count: $e');
      return 0;
    }
  }

  // Get total unread message count for user
  static Future<int> getTotalUnreadCount() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 0;

      // Get user's chats
      final chats = await getUserChats();
      int totalUnread = 0;

      for (final chat in chats) {
        final unreadCount = await getUnreadMessageCount(chat.id);
        totalUnread += unreadCount;
      }

      return totalUnread;
    } catch (e) {
      print('Error getting total unread count: $e');
      return 0;
    }
  }

  // Search messages in a chat
  static Future<List<ChatMessage>> searchMessages(
    String chatId,
    String query,
  ) async {
    try {
      if (query.length < 2) return [];

      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('chat_id', chatId)
          .ilike('message', '%$query%')
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List).map((messageData) {
        return ChatMessage.fromSupabase(messageData);
      }).toList();
    } catch (e) {
      print('Error searching messages: $e');
      return [];
    }
  }

  // Get message by ID
  static Future<ChatMessage?> getMessageById(String messageId) async {
    try {
      final response =
          await _supabase
              .from('messages')
              .select('*')
              .eq('id', messageId)
              .single();

      return ChatMessage.fromSupabase(response);
    } catch (e) {
      print('Error getting message by ID: $e');
      return null;
    }
  }

  // Upload image for message
  static Future<String?> uploadMessageImage(
    String filePath,
    String fileName,
  ) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      final String path =
          'messages/$currentUserId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      await _supabase.storage
          .from('message-images')
          .upload(path, File(filePath));

      final String publicUrl = _supabase.storage
          .from('message-images')
          .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      print('Error uploading message image: $e');
      return null;
    }
  }

  // Delete image from storage
  static Future<void> deleteMessageImage(String imageUrl) async {
    try {
      // Extract path from URL
      final uri = Uri.parse(imageUrl);
      final path = uri.pathSegments
          .skip(4)
          .join('/'); // Skip /storage/v1/object/public/message-images/

      await _supabase.storage.from('message-images').remove([path]);
    } catch (e) {
      print('Error deleting message image: $e');
    }
  }

  // Stream for real-time user presence updates
  static Stream<List<ChatUser>> getUserPresenceStream(List<String> userIds) {
    if (userIds.isEmpty) return Stream.value([]);

    return _supabase.from('users').stream(primaryKey: ['id']).map((data) {
      // Filter users by the provided user IDs
      final filteredUsers =
          data.where((json) => userIds.contains(json['id'])).toList();
      return filteredUsers.map((json) => ChatUser.fromSupabase(json)).toList();
    });
  }

  // Subscribe to real-time updates for a specific chat
  static RealtimeChannel subscribeToChatUpdates(
    String chatId, {
    Function(ChatMessage)? onMessageReceived,
    Function(ChatMessage)? onMessageUpdated,
    Function(String)? onMessageDeleted,
  }) {
    final channel = _supabase.channel('chat_$chatId');

    if (onMessageReceived != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'chat_id',
          value: chatId,
        ),
        callback: (payload) {
          final message = ChatMessage.fromSupabase(payload.newRecord);
          onMessageReceived(message);
        },
      );
    }

    if (onMessageUpdated != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'chat_id',
          value: chatId,
        ),
        callback: (payload) {
          final message = ChatMessage.fromSupabase(payload.newRecord);
          onMessageUpdated(message);
        },
      );
    }

    if (onMessageDeleted != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'chat_id',
          value: chatId,
        ),
        callback: (payload) {
          final messageId = payload.oldRecord['id'] as String;
          onMessageDeleted(messageId);
        },
      );
    }

    channel.subscribe();
    return channel;
  }

  // Subscribe to chat list updates
  static RealtimeChannel subscribeToUserChatsUpdates({
    Function(Chat)? onChatUpdated,
    Function(Chat)? onChatCreated,
    Function(String)? onChatDeleted,
  }) {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) throw Exception('User not authenticated');

    final channel = _supabase.channel('user_chats_$currentUserId');

    if (onChatCreated != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chats',
        callback: (payload) {
          final chat = Chat.fromSupabase(payload.newRecord);
          if (chat.participants.contains(currentUserId)) {
            onChatCreated(chat);
          }
        },
      );
    }

    if (onChatUpdated != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chats',
        callback: (payload) {
          final chat = Chat.fromSupabase(payload.newRecord);
          if (chat.participants.contains(currentUserId)) {
            onChatUpdated(chat);
          }
        },
      );
    }

    if (onChatDeleted != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'chats',
        callback: (payload) {
          final chatId = payload.oldRecord['id'] as String;
          onChatDeleted(chatId);
        },
      );
    }

    channel.subscribe();
    return channel;
  }

  // Unsubscribe from real-time updates
  static Future<void> unsubscribeFromUpdates(RealtimeChannel channel) async {
    await channel.unsubscribe();
  }

  // Initialize user in database (call this after authentication)
  static Future<void> initializeUser({
    required String username,
    required String email,
    String? name,
    String? avatarUrl,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      await _supabase.from('users').upsert({
        'id': currentUserId,
        'username': username,
        'email': email,
        'name': name ?? username,
        'avatar_url': avatarUrl,
        'is_online': true,
        'last_seen': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error initializing user: $e');
      throw e;
    }
  }

  // Update user profile
  static Future<void> updateUserProfile({
    String? username,
    String? name,
    String? avatarUrl,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      final updates = <String, dynamic>{};
      if (username != null) updates['username'] = username;
      if (name != null) updates['name'] = name;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      if (updates.isNotEmpty) {
        updates['updated_at'] = DateTime.now().toIso8601String();
        await _supabase.from('users').update(updates).eq('id', currentUserId);
      }
    } catch (e) {
      print('Error updating user profile: $e');
      throw e;
    }
  }

  // Delete chat (only for group admins or direct chat participants)
  static Future<void> deleteChat(String chatId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      final chat = await getChatById(chatId);
      if (chat == null) throw Exception('Chat not found');

      // Check permissions
      if (chat.isGroup) {
        if (!chat.groupAdminIds.contains(currentUserId)) {
          throw Exception('Only group admins can delete group chats');
        }
      } else {
        if (!chat.participants.contains(currentUserId)) {
          throw Exception('You can only delete chats you are part of');
        }
      }

      // Delete all messages in the chat first
      await _supabase.from('messages').delete().eq('chat_id', chatId);

      // Delete message reads
      await _supabase
          .from('message_reads')
          .delete()
          .inFilter('message_id', await _getMessageIds(chatId));

      // If it's a group chat, delete group-related data
      if (chat.isGroup && chat.groupId != null) {
        await _supabase
            .from('group_members')
            .delete()
            .eq('group_id', chat.groupId!);

        await _supabase.from('groups').delete().eq('id', chat.groupId!);
      }

      // Finally delete the chat
      await _supabase.from('chats').delete().eq('id', chatId);
    } catch (e) {
      print('Error deleting chat: $e');
      throw e;
    }
  }

  // Helper method to get message IDs for a chat
  static Future<List<String>> _getMessageIds(String chatId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('chat_id', chatId);

      return (response as List).map((msg) => msg['id'] as String).toList();
    } catch (e) {
      print('Error getting message IDs: $e');
      return [];
    }
  }

  // Update group chat info (name, description)
  static Future<void> updateGroupChatInfo({
    required String chatId,
    String? groupName,
    String? description,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      final chat = await getChatById(chatId);
      if (chat == null || !chat.isGroup) {
        throw Exception('Chat not found or not a group chat');
      }

      if (!chat.groupAdminIds.contains(currentUserId)) {
        throw Exception('Only admins can update group info');
      }

      final updates = <String, dynamic>{};
      if (groupName != null) updates['group_name'] = groupName;
      if (description != null) updates['group_description'] = description;

      if (updates.isNotEmpty) {
        updates['updated_at'] = DateTime.now().toIso8601String();
        await _supabase.from('chats').update(updates).eq('id', chatId);

        // Also update the groups table if it exists
        if (chat.groupId != null) {
          final groupUpdates = <String, dynamic>{};
          if (groupName != null) groupUpdates['name'] = groupName;
          if (description != null) groupUpdates['description'] = description;

          if (groupUpdates.isNotEmpty) {
            groupUpdates['updated_at'] = DateTime.now().toIso8601String();
            await _supabase
                .from('groups')
                .update(groupUpdates)
                .eq('id', chat.groupId!);
          }
        }
      }
    } catch (e) {
      print('Error updating group chat info: $e');
      throw e;
    }
  }

  // Get chat statistics
  static Future<Map<String, dynamic>> getChatStatistics(String chatId) async {
    try {
      final messageCountResponse = await _supabase
          .from('messages')
          .select('id')
          .eq('chat_id', chatId);

      final messageCount = messageCountResponse.length;

      final participantsResponse =
          await _supabase
              .from('chats')
              .select('participants')
              .eq('id', chatId)
              .single();

      final participantCount =
          (participantsResponse['participants'] as List).length;

      // Get first message date
      final firstMessageResponse = await _supabase
          .from('messages')
          .select('created_at')
          .eq('chat_id', chatId)
          .order('created_at', ascending: true)
          .limit(1);

      final firstMessageDate =
          firstMessageResponse.isNotEmpty
              ? firstMessageResponse.first['created_at']
              : null;

      return {
        'messageCount': messageCount,
        'participantCount': participantCount,
        'firstMessageDate': firstMessageDate,
      };
    } catch (e) {
      print('Error getting chat statistics: $e');
      return {
        'messageCount': 0,
        'participantCount': 0,
        'firstMessageDate': null,
      };
    }
  }

  // Block/Unblock user (for direct messages)
  static Future<void> blockUser(String userId, bool block) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      if (block) {
        // Add to blocked users
        await _supabase.from('blocked_users').upsert({
          'blocker_id': currentUserId,
          'blocked_id': userId,
          'blocked_at': DateTime.now().toIso8601String(),
        });
      } else {
        // Remove from blocked users
        await _supabase
            .from('blocked_users')
            .delete()
            .eq('blocker_id', currentUserId)
            .eq('blocked_id', userId);
      }
    } catch (e) {
      print('Error ${block ? 'blocking' : 'unblocking'} user: $e');
      throw e;
    }
  }

  // Get blocked users
  static Future<List<String>> getBlockedUsers() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', currentUserId);

      return (response as List)
          .map((item) => item['blocked_id'] as String)
          .toList();
    } catch (e) {
      print('Error getting blocked users: $e');
      return [];
    }
  }

  // Check if user is blocked
  static Future<bool> isUserBlocked(String userId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final response = await _supabase
          .from('blocked_users')
          .select('id')
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', userId)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      print('Error checking if user is blocked: $e');
      return false;
    }
  }

  // Report message
  static Future<void> reportMessage({
    required String messageId,
    required String reason,
    String? additionalInfo,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      await _supabase.from('message_reports').insert({
        'message_id': messageId,
        'reporter_id': currentUserId,
        'reason': reason,
        'additional_info': additionalInfo,
        'reported_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error reporting message: $e');
      throw e;
    }
  }

  // Get message reactions
  static Future<Map<String, List<String>>> getMessageReactions(
    String messageId,
  ) async {
    try {
      final response = await _supabase
          .from('message_reactions')
          .select('emoji, user_id')
          .eq('message_id', messageId);

      final Map<String, List<String>> reactions = {};
      for (final reactionData in response) {
        final emoji = reactionData['emoji'] as String;
        final userId = reactionData['user_id'] as String;

        if (!reactions.containsKey(emoji)) {
          reactions[emoji] = [];
        }
        reactions[emoji]!.add(userId);
      }

      return reactions;
    } catch (e) {
      print('Error getting message reactions: $e');
      return {};
    }
  }

  // Add/Remove message reaction
  static Future<void> toggleMessageReaction(
    String messageId,
    String emoji,
  ) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Check if reaction already exists
      final existing = await _supabase
          .from('message_reactions')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', currentUserId)
          .eq('emoji', emoji)
          .limit(1);

      if (existing.isNotEmpty) {
        // Remove reaction
        await _supabase
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', currentUserId)
            .eq('emoji', emoji);
      } else {
        // Add reaction
        await _supabase.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': currentUserId,
          'emoji': emoji,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Error toggling message reaction: $e');
      throw e;
    }
  }

  // Mute/Unmute chat notifications
  static Future<void> muteChat(String chatId, bool mute) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      if (mute) {
        await _supabase.from('muted_chats').upsert({
          'user_id': currentUserId,
          'chat_id': chatId,
          'muted_at': DateTime.now().toIso8601String(),
        });
      } else {
        await _supabase
            .from('muted_chats')
            .delete()
            .eq('user_id', currentUserId)
            .eq('chat_id', chatId);
      }
    } catch (e) {
      print('Error ${mute ? 'muting' : 'unmuting'} chat: $e');
      throw e;
    }
  }

  // Check if chat is muted
  static Future<bool> isChatMuted(String chatId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      final response = await _supabase
          .from('muted_chats')
          .select('id')
          .eq('user_id', currentUserId)
          .eq('chat_id', chatId)
          .limit(1);

      return response.isNotEmpty;
    } catch (e) {
      print('Error checking if chat is muted: $e');
      return false;
    }
  }

  // Get muted chats
  static Future<List<String>> getMutedChats() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('muted_chats')
          .select('chat_id')
          .eq('user_id', currentUserId);

      return (response as List)
          .map((item) => item['chat_id'] as String)
          .toList();
    } catch (e) {
      print('Error getting muted chats: $e');
      return [];
    }
  }

  // Clean up resources when user logs out
  static Future<void> cleanup() async {
    try {
      await updateUserOnlineStatus(false);
      // Additional cleanup can be added here
    } catch (e) {
      print('Error during cleanup: $e');
    }
  }
}
