// lib/pages/chats_page.dart
import 'package:flutter/material.dart';
import 'package:map/chat_screens/chat_screen.dart';
import 'package:map/chat_screens/user_screen.dart';
import 'package:map/data/chat_model.dart';
import 'package:map/services/supabse_messaging_service.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage>
    with AutomaticKeepAliveClientMixin {
  final Map<String, ChatUser> _users = {};
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Pre-load user data if needed
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  // Safe navigation helper to prevent crashes
  void _navigateToUserSearch() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const UserSearchScreen(),
          // Add this to help with memory management
          settings: const RouteSettings(name: '/user-search'),
        ),
      );
      // Refresh the page when returning
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Navigation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening search: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
            onPressed: _navigateToUserSearch,
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
            child:
                _isLoading
                    ? _buildLoadingState()
                    : _error != null
                    ? _buildErrorState(_error!)
                    : StreamBuilder<List<Chat>>(
                      stream: SupabaseMessagingService.getUserChatsStream(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _buildErrorState(snapshot.error.toString());
                        }

                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return _buildLoadingState();
                        }

                        final chats = snapshot.data ?? [];

                        if (chats.isEmpty) {
                          return _buildEmptyState();
                        }

                        return RefreshIndicator(
                          onRefresh: () async {
                            // Trigger a rebuild by getting fresh data
                            if (mounted) setState(() {});
                          },
                          child: ListView.builder(
                            // Add key to help with widget recycling
                            key: const PageStorageKey('chats_list'),
                            itemCount: chats.length,
                            itemBuilder: (context, index) {
                              final chat = chats[index];
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
        onPressed: _navigateToUserSearch,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.chat, color: Colors.white),
        tooltip: 'New Chat',
      ),
    );
  }

  Widget _buildOnlineStatusBar() {
    final currentUserId = SupabaseMessagingService.currentUserId;
    if (currentUserId == null) return const SizedBox.shrink();

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
            onPressed: _loadInitialData,
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
            onPressed: _navigateToUserSearch,
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
    final currentUserId = SupabaseMessagingService.currentUserId;
    if (currentUserId == null) return const SizedBox.shrink();

    final otherUserId = chat.getOtherParticipantId(currentUserId);
    if (otherUserId == null) return const SizedBox.shrink();

    return FutureBuilder<ChatUser?>(
      future: _getOrLoadUser(otherUserId),
      builder: (context, userSnapshot) {
        final otherUser = userSnapshot.data;

        if (userSnapshot.connectionState == ConnectionState.waiting &&
            otherUser == null) {
          return _buildChatTileLoading();
        }

        final bool hasUnreadMessages = _hasUnreadMessages(chat, currentUserId);

        return Container(
          // Add key for better widget management
          key: ValueKey('chat_${chat.id}'),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            // Simplified shadow to reduce rendering complexity
            border: Border.all(color: Colors.grey.shade200, width: 0.5),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Stack(
              children: [
                // Simplified Hero animation to reduce crashes
                CircleAvatar(
                  key: ValueKey('avatar_${otherUser?.id ?? otherUserId}'),
                  radius: 28,
                  backgroundColor: Colors.blue,
                  child:
                      otherUser?.avatarUrl != null
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.network(
                              otherUser!.avatarUrl!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Text(
                                  (otherUser.displayName)
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                );
                              },
                              loadingBuilder: (
                                context,
                                child,
                                loadingProgress,
                              ) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                          : Text(
                            (otherUser?.displayName ?? 'U')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
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
                    chat.isGroup
                        ? chat.displayName
                        : (otherUser?.displayName ?? 'Unknown User'),
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
                if (chat.isGroup)
                  Text(
                    '${chat.participants.length} members',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  )
                else if (otherUser?.isOnline == true)
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
                    otherUser!.onlineStatus,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
              ],
            ),
            onTap: () async {
              try {
                // Mark messages as read when opening chat
                SupabaseMessagingService.markMessagesAsRead(chat.id);

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => ChatScreen(
                          chatId: chat.id,
                          otherUser: otherUser,
                          isGroup: chat.isGroup,
                        ),
                    settings: RouteSettings(name: '/chat/${chat.id}'),
                  ),
                );

                // Refresh when returning from chat
                if (mounted) {
                  setState(() {});
                }
              } catch (e) {
                print('Chat navigation error: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error opening chat: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildChatTileLoading() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: Colors.grey[300],
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        title: Container(
          height: 16,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        subtitle: Container(
          height: 12,
          width: 150,
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Future<ChatUser?> _getOrLoadUser(String userId) async {
    if (_users.containsKey(userId)) {
      return _users[userId];
    }

    try {
      final user = await SupabaseMessagingService.getUserById(userId);
      if (user != null && mounted) {
        _users[userId] = user;
      }
      return user;
    } catch (e) {
      print('Error loading user $userId: $e');
      return null;
    }
  }

  bool _hasUnreadMessages(Chat chat, String currentUserId) {
    // Simple check - you might want to implement a more sophisticated unread message tracking
    return chat.lastSenderId != null &&
        chat.lastSenderId != currentUserId &&
        chat.lastMessage != null;
  }
}
