// lib/chat_screens/enhanced_chat_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:map/data/chat_model.dart';
import 'package:map/services/supabse_messaging_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

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

// Add this class to your enhanced_chat_screen.dart file

class ImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String caption;

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.caption,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _showAppBar = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          _showAppBar
              ? AppBar(
                backgroundColor: Colors.black.withOpacity(0.7),
                foregroundColor: Colors.white,
                elevation: 0,
                title: const Text('Image'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () => _downloadImage(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () => _shareImage(),
                  ),
                ],
              )
              : null,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showAppBar = !_showAppBar;
          });
        },
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value:
                        loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                    color: Colors.white,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar:
          _showAppBar &&
                  widget.caption.isNotEmpty &&
                  widget.caption != '📷 Image'
              ? Container(
                color: Colors.black.withOpacity(0.7),
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  child: Text(
                    widget.caption,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
              : null,
    );
  }

  Future<void> _downloadImage() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              backgroundColor: Colors.black87,
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(width: 16),
                  Text('Downloading...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
      );

      final response = await http.get(Uri.parse(widget.imageUrl));

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = '${directory.path}/$fileName';

        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image saved to: $filePath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to download image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareImage() async {
    try {
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: widget.imageUrl));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image link copied to clipboard'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late RealtimeChannel _realtimeChannel;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  bool _showAttachmentMenu = false;
  Chat? _currentChat;
  Map<String, ChatUser> _users = {};
  final ImagePicker _imagePicker = ImagePicker();

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
      _showAttachmentMenu = false;
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

  // Enhanced attachment options with modern UI
  Future<void> _showAttachmentOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(25),
                topRight: Radius.circular(25),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      'Share Content',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose what you\'d like to share',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 30),

                    // Media options grid
                    Row(
                      children: [
                        Expanded(
                          child: _buildEnhancedAttachmentOption(
                            icon: Icons.camera_alt_rounded,
                            label: 'Camera',
                            subtitle: 'Take a photo',
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _pickImage(ImageSource.camera);
                            },
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildEnhancedAttachmentOption(
                            icon: Icons.photo_library_rounded,
                            label: 'Gallery',
                            subtitle: 'Choose photo',
                            gradient: const LinearGradient(
                              colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _pickImage(ImageSource.gallery);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // Document option - full width
                    _buildEnhancedAttachmentOption(
                      icon: Icons.description_rounded,
                      label: 'Document',
                      subtitle: 'Share files (PDF, DOC, XLS, etc.)',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFfa709a), Color(0xFFfee140)],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _pickDocument();
                      },
                      fullWidth: true,
                    ),

                    const SizedBox(height: 20),

                    // Cancel button
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildEnhancedAttachmentOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: fullWidth ? 32 : 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        await _uploadAndSendMedia(
          filePath: image.path,
          fileName: image.name,
          mediaType: MediaType.image,
        );
      }
    } catch (e) {
      _showError('Error picking image: $e');
    }
  }

  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'ppt',
          'pptx',
          'xls',
          'xlsx',
        ],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        await _uploadAndSendMedia(
          filePath: file.path!,
          fileName: file.name,
          mediaType: MediaType.document,
        );
      }
    } catch (e) {
      _showError('Error picking document: $e');
    }
  }

  Future<void> _uploadAndSendMedia({
    required String filePath,
    required String fileName,
    required MediaType mediaType,
  }) async {
    setState(() {
      _isUploading = true;
    });

    try {
      // Upload file to Supabase Storage
      String? mediaUrl;
      if (mediaType == MediaType.image) {
        mediaUrl = await SupabaseMessagingService.uploadMessageImage(
          filePath,
          fileName,
        );
      } else {
        mediaUrl = await SupabaseMessagingService.uploadMessageDocument(
          filePath,
          fileName,
        );
      }

      if (mediaUrl != null) {
        // Send message with media
        String messageText;
        if (mediaType == MediaType.image) {
          messageText = '📷 Image';
        } else {
          messageText =
              '📄 $fileName'; // This will be hidden by _shouldShowTextMessage
        }

        await SupabaseMessagingService.sendMessage(
          chatId: widget.chatId,
          message: messageText,
          imageUrl: mediaType == MediaType.image ? mediaUrl : null,
          documentUrl: mediaType == MediaType.document ? mediaUrl : null,
          documentName: mediaType == MediaType.document ? fileName : null,
        );

        _scrollToBottom();
      } else {
        _showError('Failed to upload file');
      }
    } catch (e) {
      _showError('Error uploading file: $e');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
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

  void _showGroupSettings() {
    if (!widget.isGroup || _currentChat == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupSettingsScreen(chat: _currentChat!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        title: GestureDetector(
          onTap: widget.isGroup ? _showGroupSettings : null,
          child: Row(
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showGroupSettings,
            ),
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

          // Enhanced upload progress indicator
          if (_isUploading) _buildUploadProgress(),

          // Enhanced message input
          _buildEnhancedMessageInput(),
        ],
      ),
    );
  }

  Widget _buildUploadProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Uploading media...',
            style: TextStyle(
              color: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            'Please wait',
            style: TextStyle(color: Colors.blue[600], fontSize: 12),
          ),
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isGroup
                    ? Icons.group_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isGroup ? 'Start the conversation!' : 'Say hello!',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                widget.isGroup
                    ? 'Send a message to get the group conversation started'
                    : 'Send a message to start your conversation',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<ChatMessage>>(
      stream: SupabaseMessagingService.getMessagesStream(widget.chatId),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _messages = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
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
      },
    );
  }

  IconData _getDocumentIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    bool isMyMessage,
    bool showSenderInfo,
  ) {
    final user = _users[message.senderId];

    // DEBUG: Print message info

    print('=== MESSAGE DEBUG ===');
    print('Message ID: ${message.id}');
    print('Message text: "${message.message}"');
    print('Image URL: ${message.imageUrl}');
    print('Document URL: ${message.documentUrl}');
    print('Document Name: ${message.documentName}');
    print(
      'Has image: ${message.imageUrl != null && message.imageUrl!.isNotEmpty}',
    );
    print(
      'Has document: ${message.documentUrl != null && message.documentUrl!.isNotEmpty}',
    );
    print('Should show text: ${_shouldShowTextMessage(message)}');
    print('==================');

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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
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

                  // ENHANCED: Clickable image messages
                  if (message.imageUrl != null &&
                      message.imageUrl!.isNotEmpty) ...[
                    GestureDetector(
                      onTap:
                          () => _openImage(message.imageUrl!, message.message),
                      onLongPress: () => _showImageOptions(message),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              Image.network(
                                message.imageUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (
                                  context,
                                  child,
                                  loadingProgress,
                                ) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    height: 200,
                                    width: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 100,
                                    width: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.broken_image),
                                  );
                                },
                              ),
                              // Add a subtle tap indicator
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (message.message.isNotEmpty &&
                        message.message != '📷 Image')
                      const SizedBox(height: 8),
                  ],

                  // ENHANCED: Clickable document messages
                  if (message.documentUrl != null &&
                      message.documentUrl!.isNotEmpty) ...[
                    Container(),
                    GestureDetector(
                      onTap: () {
                        print('Document tapped! URL: ${message.documentUrl}');
                        _openDocument(
                          message.documentUrl!,
                          message.documentName ?? 'Document',
                        );
                      },
                      onLongPress: () => _showDocumentOptions(message),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              isMyMessage
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isMyMessage
                                    ? Colors.white.withOpacity(0.3)
                                    : Colors.grey[300]!,
                          ),
                          // Add a subtle shadow to indicate it's interactive
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    isMyMessage
                                        ? Colors.white.withOpacity(0.3)
                                        : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getDocumentIcon(message.documentName ?? ''),
                                color:
                                    isMyMessage
                                        ? Colors.white
                                        : Colors.grey[700],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.documentName ?? 'Document',
                                    style: TextStyle(
                                      color:
                                          isMyMessage
                                              ? Colors.white
                                              : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.touch_app_rounded,
                                        size: 12,
                                        color:
                                            isMyMessage
                                                ? Colors.white70
                                                : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tap to open • ${_getFileSize(message.documentUrl)}',
                                        style: TextStyle(
                                          color:
                                              isMyMessage
                                                  ? Colors.white70
                                                  : Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.launch_rounded,
                              size: 16,
                              color:
                                  isMyMessage
                                      ? Colors.white70
                                      : Colors.grey[500],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (message.message.isNotEmpty &&
                        !message.message.startsWith('📄'))
                      const SizedBox(height: 8),
                  ],

                  // Text message - Show text even for documents if it's not a placeholder
                  if (_shouldShowTextMessage(message))
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

  void _openImage(String imageUrl, String caption) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                ImageViewerScreen(imageUrl: imageUrl, caption: caption),
      ),
    );
  }

  void _showImageOptions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                if (message.imageUrl != null &&
                    message.imageUrl!.isNotEmpty) ...[
                  ListTile(
                    leading: const Icon(Icons.zoom_in),
                    title: const Text('View Full Size'),
                    onTap: () {
                      Navigator.pop(context);
                      _openImage(message.imageUrl!, message.message);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Copy Image Link'),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: message.imageUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Image link copied')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Save Image'),
                    onTap: () {
                      Navigator.pop(context);
                      _downloadImage(
                        message.imageUrl!,
                        'image_${message.id}.jpg',
                      );
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _downloadImage(String url, String fileName) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Downloading image...'),
                ],
              ),
            ),
      );

      final response = await http.get(Uri.parse(url));

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';

        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Image saved to: $filePath')));
      } else {
        _showError('Failed to download image');
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showError('Error downloading image: $e');
    }
  }

  bool _shouldShowTextMessage(ChatMessage message) {
    if (message.message.isEmpty) return false;
    if (message.message == '📷 Image') return false;
    if (message.message.startsWith('📄 ') && message.documentUrl != null) {
      // Only hide if the message is exactly "📄 filename"
      final expectedMessage = '📄 ${message.documentName ?? 'Document'}';
      if (message.message == expectedMessage) {
        return false;
      }
    }
    return true;
  }

  Future<void> _openDocument(String url, String fileName) async {
    try {
      print('Attempting to open document URL: $url');

      if (url.isEmpty) {
        _showError('Document URL is empty');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Opening document...'),
                ],
              ),
            ),
      );

      final uri = Uri.parse(url);
      bool canLaunch = await canLaunchUrl(uri);

      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);

      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: download and open
        await _downloadAndOpenDocument(url, fileName);
      }
    } catch (e) {
      // Dismiss loading dialog if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      print('Error opening document: $e');
      _showError('Error opening document: $e');
    }
  }

  Future<void> _downloadAndOpenDocument(String url, String fileName) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Downloading document...'),
                ],
              ),
            ),
      );

      // Download the file
      final response = await http.get(Uri.parse(url));

      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        // Get the app's documents directory
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';

        // Write the file
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Try to open the downloaded file
        final result = await OpenFile.open(filePath);

        if (result.type != ResultType.done) {
          _showError('Cannot open this file type. File saved to: $filePath');
        }
      } else {
        _showError('Failed to download document');
      }
    } catch (e) {
      // Dismiss loading dialog if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showError('Error downloading document: $e');
    }
  }

  // Document message bubble (THIS SHOULD BE CLICKABLE)
  Widget _buildDocumentMessageBubble(ChatMessage message, bool isMyMessage) {
    return GestureDetector(
      onTap: () {
        print('Document tapped! URL: ${message.documentUrl}'); // Debug
        if (message.documentUrl != null && message.documentUrl!.isNotEmpty) {
          _openDocument(
            message.documentUrl!,
            message.documentName ?? 'Document',
          );
        } else {
          _showError('Document not available');
          print('Document URL is null or empty for message: ${message.id}');
        }
      },
      onLongPress: () {
        _showDocumentOptions(message);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMyMessage ? Colors.white.withOpacity(0.2) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isMyMessage ? Colors.white.withOpacity(0.3) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    isMyMessage
                        ? Colors.white.withOpacity(0.3)
                        : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getDocumentIcon(message.documentName ?? ''),
                color: isMyMessage ? Colors.white : Colors.grey[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.documentName ?? 'Document',
                    style: TextStyle(
                      color: isMyMessage ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to open • ${_getFileSize(message.documentUrl)}',
                    style: TextStyle(
                      color: isMyMessage ? Colors.white70 : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Add launch icon to make it clear it's clickable
            Icon(
              Icons.launch_rounded,
              size: 16,
              color: isMyMessage ? Colors.white70 : Colors.grey[500],
            ),
          ],
        ),
      ),
    );
  }

  String _getFileSize(String? url) {
    if (url == null || url.isEmpty) return '';

    // You can implement actual file size fetching here if needed
    // For now, just return a generic message
    return 'Document';
  }

  // FIFTH: Add document options menu
  void _showDocumentOptions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                if (message.documentUrl != null &&
                    message.documentUrl!.isNotEmpty) ...[
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open Document'),
                    onTap: () {
                      Navigator.pop(context);
                      _openDocument(
                        message.documentUrl!,
                        message.documentName ?? 'Document',
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Copy Document Link'),
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(
                        ClipboardData(text: message.documentUrl!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Document link copied')),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Download Document'),
                    onTap: () {
                      Navigator.pop(context);
                      _downloadAndOpenDocument(
                        message.documentUrl!,
                        message.documentName ?? 'Document',
                      );
                    },
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.error),
                    title: const Text('Document Not Available'),
                    subtitle: const Text('This document could not be loaded'),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildEnhancedMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Enhanced attachment button with animation
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _showAttachmentMenu ? Colors.blue : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.add_rounded,
                  color: _showAttachmentMenu ? Colors.white : Colors.grey[600],
                ),
                onPressed: () {
                  setState(() {
                    _showAttachmentMenu = !_showAttachmentMenu;
                  });
                  if (_showAttachmentMenu) {
                    _showAttachmentOptions();
                  }
                },
              ),
            ),

            const SizedBox(width: 8),

            // Enhanced text input
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(fontSize: 16),
                  onChanged: (text) {
                    setState(() {
                      // This will trigger rebuild to show/hide send button
                    });
                  },
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Enhanced send button with animation
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient:
                    _messageController.text.trim().isNotEmpty
                        ? const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        )
                        : null,
                color:
                    _messageController.text.trim().isEmpty
                        ? Colors.grey[300]
                        : null,
                shape: BoxShape.circle,
                boxShadow:
                    _messageController.text.trim().isNotEmpty
                        ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                        : null,
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
                        : Icon(
                          Icons.send_rounded,
                          color:
                              _messageController.text.trim().isNotEmpty
                                  ? Colors.white
                                  : Colors.grey[600],
                          size: 20,
                        ),
                onPressed:
                    _isSending || _messageController.text.trim().isEmpty
                        ? null
                        : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum MediaType { image, document }

// Enhanced Group Settings Screen
class GroupSettingsScreen extends StatelessWidget {
  final Chat chat;

  const GroupSettingsScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Group Settings'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.group_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    chat.displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${chat.participants.length} members',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Settings options
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildSettingsOption(
                    icon: Icons.people_rounded,
                    title: 'Members',
                    subtitle: 'View and manage group members',
                    onTap: () {
                      // TODO: Implement members management
                    },
                  ),
                  const Divider(height: 1),
                  _buildSettingsOption(
                    icon: Icons.photo_library_rounded,
                    title: 'Media & Files',
                    subtitle: 'View shared photos and documents',
                    onTap: () {
                      // TODO: Implement media gallery
                    },
                  ),
                  const Divider(height: 1),
                  _buildSettingsOption(
                    icon: Icons.notifications_rounded,
                    title: 'Notifications',
                    subtitle: 'Manage group notifications',
                    onTap: () {
                      // TODO: Implement notification settings
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Danger zone
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_rounded, color: Colors.red[600]),
                      const SizedBox(width: 8),
                      Text(
                        'Danger Zone',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'These actions cannot be undone',
                    style: TextStyle(color: Colors.red[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Implement leave group
                          },
                          icon: const Icon(Icons.exit_to_app_rounded),
                          label: const Text('Leave Group'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[700],
                            side: BorderSide(color: Colors.red[300]!),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.blue[600], size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    );
  }
}
