// lib/chat_screens/group_creation_screen.dart
import 'package:flutter/material.dart';
import 'package:map/chat_screens/chat_screen.dart';
import 'package:map/data/chat_model.dart';
import 'package:map/services/supabse_messaging_service.dart';

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  State<GroupCreationScreen> createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<ChatUser> _searchResults = [];
  List<ChatUser> _selectedMembers = [];
  bool _isSearching = false;
  bool _isCreating = false;
  bool _isPrivateGroup = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await SupabaseMessagingService.searchUsers(query);
      // Filter out already selected members
      final filteredResults =
          results
              .where(
                (user) =>
                    !_selectedMembers.any((selected) => selected.id == user.id),
              )
              .toList();

      setState(() {
        _searchResults = filteredResults;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      _showError('Error searching users: $e');
    }
  }

  void _addMember(ChatUser user) {
    setState(() {
      _selectedMembers.add(user);
      _searchResults.removeWhere((u) => u.id == user.id);
    });
  }

  void _removeMember(ChatUser user) {
    setState(() {
      _selectedMembers.removeWhere((u) => u.id == user.id);
    });
    // Re-run search to potentially add the user back to search results
    if (_searchController.text.isNotEmpty) {
      _searchUsers(_searchController.text);
    }
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      _showError('Please enter a group name');
      return;
    }

    if (_selectedMembers.isEmpty) {
      _showError('Please add at least one member to the group');
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final chatId = await SupabaseMessagingService.createGroupChat(
        groupName: groupName,
        description:
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        members: _selectedMembers,
        isPrivate: _isPrivateGroup,
      );

      if (mounted) {
        // Navigate to the created group chat
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chatId: chatId, isGroup: true),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isCreating = false;
      });
      _showError('Error creating group: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Group Info Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Group Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),

                // Group Name Input
                TextField(
                  controller: _groupNameController,
                  decoration: InputDecoration(
                    labelText: 'Group Name *',
                    hintText: 'Enter group name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    prefixIcon: const Icon(Icons.group),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Group Description Input
                TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'What\'s this group about?',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    prefixIcon: const Icon(Icons.description),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),

                // Privacy Toggle
                Row(
                  children: [
                    Icon(
                      _isPrivateGroup ? Icons.lock : Icons.public,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isPrivateGroup ? 'Private Group' : 'Public Group',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    Switch(
                      value: _isPrivateGroup,
                      onChanged: (value) {
                        setState(() {
                          _isPrivateGroup = value;
                        });
                      },
                      activeColor: Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isPrivateGroup
                      ? 'Only invited members can join this group'
                      : 'Anyone can search and join this group',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // Selected Members Section
          if (_selectedMembers.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Members (${_selectedMembers.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        _selectedMembers.map((member) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Colors.blue,
                              backgroundImage:
                                  member.avatarUrl != null
                                      ? NetworkImage(member.avatarUrl!)
                                      : null,
                              child:
                                  member.avatarUrl == null
                                      ? Text(
                                        member.displayName
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
                            label: Text(member.displayName),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () => _removeMember(member),
                            backgroundColor: Colors.white,
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),

          // Add Members Section
          Expanded(
            child: Column(
              children: [
                // Search Input
                Container(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search users to add...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: const BorderSide(
                          color: Colors.blue,
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon:
                          _isSearching
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                              : null,
                    ),
                    onChanged: _searchUsers,
                  ),
                ),

                // Search Results
                Expanded(child: _buildSearchResults()),
              ],
            ),
          ),

          // Create Button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: 2,
                ),
                child:
                    _isCreating
                        ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Creating Group...'),
                          ],
                        )
                        : const Text(
                          'Create Group',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Search for users to add',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Type at least 2 characters to start searching',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue,
              backgroundImage:
                  user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child:
                  user.avatarUrl == null
                      ? Text(
                        user.displayName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      : null,
            ),
            title: Text(
              user.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${user.username}'),
                if (user.isOnline)
                  Text(
                    'Online',
                    style: TextStyle(
                      color: Colors.green[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else if (user.lastSeen != null)
                  Text(
                    user.onlineStatus,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () => _addMember(user),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                minimumSize: const Size(60, 36),
              ),
              child: const Text('Add'),
            ),
          ),
        );
      },
    );
  }
}
