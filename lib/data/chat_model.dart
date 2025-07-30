// lib/models/chat_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatUser {
  final String id;
  final String email;
  final String name;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  ChatUser({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
    required this.isOnline,
    this.lastSeen,
    this.createdAt,
  });

  factory ChatUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatUser(
      id: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      avatarUrl: data['avatar_url'],
      isOnline: data['is_online'] ?? false,
      lastSeen: data['last_seen']?.toDate(),
      createdAt: data['created_at']?.toDate(),
    );
  }

  String get displayName => name.isNotEmpty ? name : email.split('@')[0];

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
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderEmail;
  final String senderName;
  final String message;
  final String? imageUrl;
  final DateTime? timestamp;
  final List<String> readBy;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderEmail,
    required this.senderName,
    required this.message,
    this.imageUrl,
    this.timestamp,
    required this.readBy,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['sender_id'] ?? '',
      senderEmail: data['sender_email'] ?? '',
      senderName: data['sender_name'] ?? '',
      message: data['message'] ?? '',
      imageUrl: data['image_url'],
      timestamp: data['timestamp']?.toDate(),
      readBy: List<String>.from(data['read_by'] ?? []),
    );
  }

  bool isReadBy(String userId) => readBy.contains(userId);

  String get timeString {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final messageTime = timestamp!;

    if (now.difference(messageTime).inDays == 0) {
      // Same day - show time
      return '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
    } else if (now.difference(messageTime).inDays < 7) {
      // Within a week - show day
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[messageTime.weekday - 1];
    } else {
      // Older - show date
      return '${messageTime.day}/${messageTime.month}';
    }
  }
}

class Chat {
  final String id;
  final List<String> participants;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? lastSenderId;
  final DateTime? createdAt;

  Chat({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.lastMessageTime,
    this.lastSenderId,
    this.createdAt,
  });

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Chat(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['last_message'],
      lastMessageTime: data['last_message_time']?.toDate(),
      lastSenderId: data['last_sender_id'],
      createdAt: data['created_at']?.toDate(),
    );
  }

  String getOtherParticipantId(String currentUserId) {
    return participants.firstWhere((id) => id != currentUserId);
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
}
