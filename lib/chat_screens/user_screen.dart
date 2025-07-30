// lib/screens/user_search_screen.dart
import 'package:flutter/material.dart';
import 'package:map/data/chat_model.dart';
import 'package:map/services/messaging_services.dart';
import 'package:rxdart/rxdart.dart';

import 'chat_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescriptionController =
      TextEditingController();

  final BehaviorSubject<String> _searchSubject = BehaviorSubject<String>();

  List<ChatUser> _searchResults = [];
  List<ChatUser> _selectedUsers = [];
  bool _isSearching = false;
  bool _isCreatingChat = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Setup debounced search
    _searchSubject
        .debounceTime(const Duration(milliseconds: 300))
        .distinct()
        .listen(_performSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    _searchSubject.close();
    _tabController.dispose();
    super.dispose();
  }

  void _performSearch(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await MessagingService.searchUsers(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search error: $e')));
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchSubject.add(value);
  }

  void _selectUser(ChatUser user) {
    if (_tabController.index == 1) {
      // Group mode
      setState(() {
        if (!_selectedUsers.any((u) => u.id == user.id)) {
          _selectedUsers.add(user);
        }
      });
    } else {
      // Direct message mode
      _startDirectMessage(user);
    }
  }

  void _removeSelectedUser(ChatUser user) {
    setState(() {
      _selectedUsers.removeWhere((u) => u.id == user.id);
    });
  }

  void _startDirectMessage(ChatUser user) async {
    setState(() => _isCreatingChat = true);

    try {
      final chatId = await MessagingService.createDirectConversation(user);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chatId: chatId, otherUser: user),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingChat = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting conversation: $e')),
        );
      }
    }
  }

  void _createGroupChat() async {
    if (_groupNameController.text.trim().isEmpty || _selectedUsers.isEmpty) {
      return;
    }

    setState(() => _isCreatingChat = true);

    try {
      final chatId = await MessagingService.createGroupChat(
        groupName: _groupNameController.text.trim(),
        description:
            _groupDescriptionController.text.trim().isEmpty
                ? null
                : _groupDescriptionController.text.trim(),
        members: _selectedUsers,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  chatId: chatId,
                  otherUser: null, // Group chat
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreatingChat = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating group: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        title: const Text('New Message'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          onTap: (index) {
            setState(() {
              _selectedUsers.clear();
              _searchController.clear();
              _searchResults.clear();
              _groupNameController.clear();
              _groupDescriptionController.clear();
            });
          },
          tabs: const [Tab(text: 'Direct Message'), Tab(text: 'Group Chat')],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search users by username...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),

          // Selected users (group mode)
          if (_tabController.index == 1 && _selectedUsers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selected Users:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        _selectedUsers
                            .map(
                              (user) => Chip(
                                avatar: CircleAvatar(
                                  backgroundImage:
                                      user.avatarUrl != null
                                          ? NetworkImage(user.avatarUrl!)
                                          : null,
                                  backgroundColor: Colors.blue,
                                  child:
                                      user.avatarUrl == null
                                          ? Text(
                                            user.displayName
                                                .substring(0, 1)
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          )
                                          : null,
                                ),
                                label: Text(user.displayName),
                                onDeleted: () => _removeSelectedUser(user),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // Group creation form
          if (_tabController.index == 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _groupNameController,
                    decoration: InputDecoration(
                      hintText: 'Group name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _groupDescriptionController,
                    decoration: InputDecoration(
                      hintText: 'Group description (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _groupNameController.text.trim().isNotEmpty &&
                                  _selectedUsers.isNotEmpty &&
                                  !_isCreatingChat
                              ? _createGroupChat
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child:
                          _isCreatingChat
                              ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                              : const Text('Create Group'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // Search results
          Expanded(
            child:
                _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _searchResults.isEmpty &&
                        _searchController.text.length >= 2
                    ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No users found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                    : _searchController.text.length < 2
                    ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Search for users to start messaging',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final user = _searchResults[index];
                        final isSelected = _selectedUsers.any(
                          (u) => u.id == user.id,
                        );

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                user.avatarUrl != null
                                    ? NetworkImage(user.avatarUrl!)
                                    : null,
                            backgroundColor: Colors.blue,
                            child:
                                user.avatarUrl == null
                                    ? Text(
                                      user.displayName
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    )
                                    : null,
                          ),
                          title: Text(user.displayName),
                          subtitle: Text('@${user.username}'),
                          trailing:
                              _tabController.index == 1 && isSelected
                                  ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  )
                                  : _tabController.index == 0
                                  ? const Icon(Icons.message_outlined)
                                  : null,
                          onTap:
                              _isCreatingChat ? null : () => _selectUser(user),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
