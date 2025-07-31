// lib/models/chat_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatUser {
  final String id;
  final String username;
  final String email;
  final String name;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  ChatUser({
    required this.id,
    required this.username,
    required this.email,
    required this.name,
    this.avatarUrl,
    required this.isOnline,
    this.lastSeen,
    this.createdAt,
  });

  // For users fetched from Supabase
  factory ChatUser.fromSupabase(Map<String, dynamic> data) {
    return ChatUser(
      id: data['id'],
      username: data['username'] ?? '',
      email: data['email'] ?? '${data['username']}@example.com',
      name: data['name'] ?? data['display_name'] ?? data['username'] ?? '',
      avatarUrl: data['avatar_url'],
      isOnline: data['is_online'] ?? false,
      lastSeen: _parseDateTime(data['last_seen']),
      createdAt: _parseDateTime(data['created_at']),
    );
  }

  // For backward compatibility with Firebase
  factory ChatUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatUser(
      id: doc.id,
      username: data['username'] ?? data['email']?.split('@')[0] ?? '',
      email: data['email'] ?? '',
      name: data['name'] ?? data['display_name'] ?? '',
      avatarUrl: data['avatar_url'],
      isOnline: data['is_online'] ?? false,
      lastSeen: _parseDateTime(data['last_seen']),
      createdAt: _parseDateTime(data['created_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        print('Error parsing date: $dateValue - $e');
        return null;
      }
    }
    if (dateValue is DateTime) return dateValue;
    try {
      return dateValue.toDate(); // Firestore Timestamp
    } catch (e) {
      return null;
    }
  }

  String get displayName =>
      name.isNotEmpty
          ? name
          : (username.isNotEmpty ? username : email.split('@')[0]);

  String get onlineStatus {
    if (isOnline) return 'Online';
    if (lastSeen == null) return 'Last seen unknown';

    final now = DateTime.now();
    final difference = now.difference(lastSeen!);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';

    return 'Last seen ${lastSeen!.day}/${lastSeen!.month}';
  }

  Map<String, dynamic> toSupabase() {
    return {
      'username': username,
      'email': email,
      'name': name,
      'avatar_url': avatarUrl,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String senderEmail;
  final String senderName;
  final String message;
  final String? imageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> readBy;
  final bool isOptimistic; // New field for optimistic updates

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderEmail,
    required this.senderName,
    required this.message,
    this.imageUrl,
    this.createdAt,
    this.updatedAt,
    required this.readBy,
    this.isOptimistic = false, // Default to false
  });

  // For messages from Supabase
  factory ChatMessage.fromSupabase(Map<String, dynamic> data) {
    return ChatMessage(
      id: data['id'],
      chatId: data['chat_id'],
      senderId: data['sender_id'],
      senderEmail: data['sender_email'] ?? '',
      senderName: data['sender_name'] ?? '',
      message: data['message'] ?? '',
      imageUrl: data['image_url'],
      createdAt: _parseDateTime(data['created_at']),
      updatedAt: _parseDateTime(data['updated_at']),
      readBy: List<String>.from(data['read_by'] ?? []),
      isOptimistic: false, // Server messages are never optimistic
    );
  }

  // For backward compatibility with Firebase
  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      chatId: '', // Not stored in Firebase message
      senderId: data['sender_id'] ?? '',
      senderEmail: data['sender_email'] ?? '',
      senderName: data['sender_name'] ?? '',
      message: data['message'] ?? '',
      imageUrl: data['image_url'],
      createdAt: _parseDateTime(data['timestamp']),
      updatedAt: _parseDateTime(data['updated_at']),
      readBy: List<String>.from(data['read_by'] ?? []),
      isOptimistic: false, // Firebase messages are never optimistic
    );
  }

  static DateTime? _parseDateTime(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        return null;
      }
    }
    if (dateValue is DateTime) return dateValue;
    try {
      return dateValue.toDate(); // Firestore Timestamp
    } catch (e) {
      return null;
    }
  }

  bool isReadBy(String userId) => readBy.contains(userId);

  String get timeString {
    if (createdAt == null) return '';

    final now = DateTime.now();
    final messageTime = createdAt!;

    if (now.difference(messageTime).inDays == 0) {
      return '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(messageTime).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[messageTime.weekday - 1];
    } else {
      return '${messageTime.day}/${messageTime.month}';
    }
  }

  // Create a copy of the message with updated fields
  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderEmail,
    String? senderName,
    String? message,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? readBy,
    bool? isOptimistic,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderEmail: senderEmail ?? this.senderEmail,
      senderName: senderName ?? this.senderName,
      message: message ?? this.message,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      readBy: readBy ?? this.readBy,
      isOptimistic: isOptimistic ?? this.isOptimistic,
    );
  }

  Map<String, dynamic> toSupabase() {
    return {
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_email': senderEmail,
      'sender_name': senderName,
      'message': message,
      'image_url': imageUrl,
      'read_by': readBy,
      // Note: isOptimistic is not saved to database as it's UI-only
    };
  }
}

class Chat {
  final String id;
  final List<String> participants;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? lastSenderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isGroup;
  final String? groupName;
  final String? groupDescription;
  final List<String> groupAdminIds;
  final String? groupId;

  Chat({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.lastMessageTime,
    this.lastSenderId,
    this.createdAt,
    this.updatedAt,
    this.isGroup = false,
    this.groupName,
    this.groupDescription,
    this.groupAdminIds = const [],
    this.groupId,
  });

  // For chats from Supabase
  factory Chat.fromSupabase(Map<String, dynamic> data) {
    return Chat(
      id: data['id'],
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['last_message'],
      lastMessageTime:
          _parseDateTime(data['last_message_time']) ??
          _parseDateTime(data['last_message_at']),
      lastSenderId: data['last_sender_id'],
      createdAt: _parseDateTime(data['created_at']),
      updatedAt: _parseDateTime(data['updated_at']),
      isGroup: data['is_group'] ?? false,
      groupName: data['group_name'],
      groupDescription: data['group_description'],
      groupAdminIds: List<String>.from(data['group_admin_ids'] ?? []),
      groupId: data['group_id'],
    );
  }

  // For backward compatibility with Firebase
  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Chat(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['last_message'],
      lastMessageTime: _parseDateTime(data['last_message_time']),
      lastSenderId: data['last_sender_id'],
      createdAt: _parseDateTime(data['created_at']),
      updatedAt: _parseDateTime(data['updated_at']),
      isGroup: data['is_group'] ?? false,
      groupName: data['group_name'],
      groupDescription: data['group_description'],
      groupAdminIds: List<String>.from(data['group_admin_ids'] ?? []),
      groupId: data['supabase_group_id'],
    );
  }

  static DateTime? _parseDateTime(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        return null;
      }
    }
    if (dateValue is DateTime) return dateValue;
    try {
      return dateValue.toDate(); // Firestore Timestamp
    } catch (e) {
      return null;
    }
  }

  String? getOtherParticipantId(String currentUserId) {
    try {
      return participants.firstWhere((id) => id != currentUserId);
    } catch (e) {
      return participants.isNotEmpty ? participants.first : null;
    }
  }

  String get lastMessageTimeString {
    if (lastMessageTime == null) return '';

    final now = DateTime.now();
    final messageTime = lastMessageTime!;

    if (now.difference(messageTime).inMinutes < 1) return 'Just now';
    if (now.difference(messageTime).inMinutes < 60)
      return '${now.difference(messageTime).inMinutes}m';
    if (now.difference(messageTime).inHours < 24)
      return '${now.difference(messageTime).inHours}h';
    if (now.difference(messageTime).inDays < 7)
      return '${now.difference(messageTime).inDays}d';

    return '${messageTime.day}/${messageTime.month}';
  }

  String get displayName {
    if (isGroup) return groupName ?? 'Group Chat';
    return 'Direct Chat';
  }

  Map<String, dynamic> toSupabase() {
    return {
      'participants': participants,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'last_sender_id': lastSenderId,
      'is_group': isGroup,
      'group_name': groupName,
      'group_description': groupDescription,
      'group_admin_ids': groupAdminIds,
      'group_id': groupId,
    };
  }
}
