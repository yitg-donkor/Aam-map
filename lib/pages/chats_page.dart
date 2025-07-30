// lib/pages/chats_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:map/chat_screens/chat_screen.dart';
import 'package:map/chat_screens/user_screen.dart';
import 'package:map/data/chat_model.dart';

import '../services/firebase_service.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage>
    with AutomaticKeepAliveClientMixin {
  final Map<String, ChatUser> _users = {};

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UsersScreen()),
              );
            },
            tooltip: 'Start new chat',
          ),
        ],
      ),
      body: Column(
        children: [
          // Online status indicator
          _buildOnlineStatusBar(),

          // Chat list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getUserChatsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }

                final chatDocs = snapshot.data?.docs ?? [];

                if (chatDocs.isEmpty) {
                  return _buildEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    // Trigger a rebuild by getting a new stream
                    setState(() {});
                  },
                  child: ListView.builder(
                    itemCount: chatDocs.length,
                    itemBuilder: (context, index) {
                      final chat = Chat.fromFirestore(chatDocs[index]);
                      return _buildChatTile(chat);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UsersScreen()),
          );
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.chat, color: Colors.white),
        tooltip: 'New Chat',
      ),
    );
  }

  Widget _buildOnlineStatusBar() {
    final currentUser = FirebaseService.currentUserId;
    if (currentUser == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'You\'re online',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading your chats...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Error loading chats',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {}); // Trigger rebuild
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a conversation with your friends',
            style: TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UsersScreen()),
              );
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Find People to Chat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(Chat chat) {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return const SizedBox.shrink();

    final otherUserId = chat.getOtherParticipantId(currentUserId);

    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('users')
              .doc(otherUserId)
              .snapshots(),
      builder: (context, userSnapshot) {
        ChatUser? otherUser;
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          otherUser = ChatUser.fromFirestore(userSnapshot.data!);
          _users[otherUserId] = otherUser;
        } else {
          otherUser = _users[otherUserId];
        }

        final bool hasUnreadMessages =
            chat.lastSenderId != currentUserId && chat.lastMessage != null;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Stack(
              children: [
                Hero(
                  tag: 'avatar_${otherUser?.id}',
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.blue,
                    backgroundImage:
                        otherUser?.avatarUrl != null
                            ? NetworkImage(otherUser!.avatarUrl!)
                            : null,
                    child:
                        otherUser?.avatarUrl == null
                            ? Text(
                              otherUser?.displayName
                                      .substring(0, 1)
                                      .toUpperCase() ??
                                  '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                            : null,
                  ),
                ),
                if (otherUser?.isOnline == true)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    otherUser?.displayName ?? 'Unknown User',
                    style: TextStyle(
                      fontWeight:
                          hasUnreadMessages ? FontWeight.bold : FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (hasUnreadMessages)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (chat.lastSenderId == currentUserId) ...[
                    Icon(Icons.done_all, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      chat.lastMessage ?? 'No messages yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight:
                            hasUnreadMessages
                                ? FontWeight.w500
                                : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat.lastMessageTimeString,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasUnreadMessages ? Colors.blue : Colors.grey[500],
                    fontWeight:
                        hasUnreadMessages ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                if (otherUser?.isOnline == true)
                  Text(
                    'Online',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (otherUser?.lastSeen != null)
                  Text(
                    'Last seen ${_getLastSeenText(otherUser!.lastSeen!)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
              ],
            ),
            onTap: () {
              // Mark messages as read when opening chat
              FirebaseService.markMessagesAsRead(chat.id);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          ChatScreen(chatId: chat.id, otherUser: otherUser),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _getLastSeenText(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';

    return '${lastSeen.day}/${lastSeen.month}';
  }
}
