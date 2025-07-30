// lib/chat_screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:map/data/chat_model.dart';
import 'package:map/services/supabse_messaging_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final ChatUser? otherUser;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.chatId,
    this.otherUser,
    this.isGroup = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late RealtimeChannel _realtimeChannel;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Chat? _currentChat;
  Map<String, ChatUser> _users = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    SupabaseMessagingService.unsubscribeFromUpdates(_realtimeChannel);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _markMessagesAsRead();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _initializeChat() async {
    try {
      // Load chat details
      _currentChat = await SupabaseMessagingService.getChatById(widget.chatId);

      // Load messages
      final messages = await SupabaseMessagingService.getMessages(
        widget.chatId,
      );

      // Load user data for participants
      if (_currentChat != null) {
        _users = await SupabaseMessagingService.getUsersByIds(
          _currentChat!.participants,
        );
      }

      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Mark messages as read
      _markMessagesAsRead();

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _setupRealtimeSubscription() {
    _realtimeChannel = SupabaseMessagingService.subscribeToChatUpdates(
      widget.chatId,
      onMessageReceived: (message) {
        setState(() {
          _messages.insert(0, message);
        });
        _scrollToBottom();
        _markMessagesAsRead();
      },
      onMessageUpdated: (message) {
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = message;
          }
        });
      },
      onMessageDeleted: (messageId) {
        setState(() {
          _messages.removeWhere((m) => m.id == messageId);
        });
      },
    );
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await SupabaseMessagingService.markMessagesAsRead(widget.chatId);
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      await SupabaseMessagingService.sendMessage(
        chatId: widget.chatId,
        message: messageText,
      );

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _getChatTitle() {
    if (widget.isGroup) {
      return _currentChat?.displayName ?? 'Group Chat';
    }
    return widget.otherUser?.displayName ?? 'Chat';
  }

  String _getChatSubtitle() {
    if (widget.isGroup) {
      final memberCount = _currentChat?.participants.length ?? 0;
      return '$memberCount members';
    }
    return widget.otherUser?.onlineStatus ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            if (!widget.isGroup && widget.otherUser != null) ...[
              Hero(
                tag: 'avatar_${widget.otherUser!.id}',
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  backgroundImage:
                      widget.otherUser!.avatarUrl != null
                          ? NetworkImage(widget.otherUser!.avatarUrl!)
                          : null,
                  child:
                      widget.otherUser!.avatarUrl == null
                          ? Text(
                            widget.otherUser!.displayName
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                          : null,
                ),
              ),
              const SizedBox(width: 12),
            ] else if (widget.isGroup) ...[
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: Icon(Icons.group, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getChatTitle(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _getChatSubtitle(),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: Show chat options menu
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(child: _buildMessagesList()),

          // Message input
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isGroup ? Icons.group : Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              widget.isGroup ? 'Start the conversation!' : 'Say hello!',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isGroup
                  ? 'Send a message to get the group conversation started'
                  : 'Send a message to start your conversation',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMyMessage =
            message.senderId == SupabaseMessagingService.currentUserId;
        final showSenderInfo = widget.isGroup && !isMyMessage;

        return _buildMessageBubble(message, isMyMessage, showSenderInfo);
      },
    );
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    bool isMyMessage,
    bool showSenderInfo,
  ) {
    final user = _users[message.senderId];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMyMessage && showSenderInfo) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              backgroundImage:
                  user?.avatarUrl != null
                      ? NetworkImage(user!.avatarUrl!)
                      : null,
              child:
                  user?.avatarUrl == null
                      ? Text(
                        (user?.displayName ?? message.senderName)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              margin: EdgeInsets.only(
                left: isMyMessage ? 50 : (showSenderInfo ? 0 : 24),
                right: isMyMessage ? 0 : 50,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMyMessage ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showSenderInfo) ...[
                    Text(
                      user?.displayName ?? message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message.message,
                    style: TextStyle(
                      color: isMyMessage ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.timeString,
                        style: TextStyle(
                          color:
                              isMyMessage ? Colors.white70 : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                      if (isMyMessage) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_all,
                          size: 14,
                          color:
                              message.readBy.length > 1
                                  ? Colors.white
                                  : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon:
                  _isSending
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                      : const Icon(Icons.send, color: Colors.white),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
