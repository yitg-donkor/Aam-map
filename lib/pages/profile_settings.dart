// ignore_for_file: avoid_print, use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:map/avatars.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileSettingsPage extends StatefulWidget {
  @override
  _ProfileSettingsPageState createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _dobController = TextEditingController();
  final _departmentController = TextEditingController();
  final _levelController = TextEditingController();
  final _classController = TextEditingController();
  final user = Supabase.instance.client.auth.currentUser;
  String? selectedAvatar;
  String? _currentAvatarUrl; // Keep track of current avatar

  int? _selectedLevel;
  bool _isLoading = false;

  @override
  void initState() {
    print('📱 ProfileSettingsPage: initState called');
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    print('📱 ProfileSettingsPage: dispose called');
    _usernameController.dispose();
    _dobController.dispose();
    _departmentController.dispose();
    _levelController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    print('🔄 _loadUserProfile: Starting to load user profile');
    try {
      setState(() {
        _isLoading = true;
      });
      print('🔄 _loadUserProfile: Set loading state to true');

      final user = Supabase.instance.client.auth.currentUser;
      print('👤 _loadUserProfile: Current user - ${user?.id ?? 'null'}');

      if (user != null) {
        print(
          '🔍 _loadUserProfile: Querying users table for user ID: ${user.id}',
        );

        final response =
            await Supabase.instance.client
                .from('users')
                .select()
                .eq('id', user.id)
                .single();

        print('📦 _loadUserProfile: Database response received');
        print('📊 _loadUserProfile: Profile data: $response');

        final profile = response;
        if (mounted) {
          setState(() {
            _usernameController.text = profile['username'] ?? '';
            _dobController.text = profile['date_of_birth'] ?? '';
            _departmentController.text = profile['department'] ?? '';
            _levelController.text = profile['level']?.toString() ?? '';
            _selectedLevel =
                profile['level'] != null
                    ? int.tryParse(profile['level'].toString())
                    : null;
            _classController.text = profile['class'] ?? '';

            // Handle avatar URL properly
            _currentAvatarUrl = profile['avatar_url'];
            selectedAvatar =
                profile['avatar_url']; // Prefill with current avatar
          });
        }

        print('✅ _loadUserProfile: Profile data populated:');
        print('   - Username: ${_usernameController.text}');
        print('   - DOB: ${_dobController.text}');
        print('   - Department: ${_departmentController.text}');
        print('   - Level: $_selectedLevel');
        print('   - Class: ${_classController.text}');
        print('   - Current Avatar URL: $_currentAvatarUrl');
        print('   - Selected Avatar: $selectedAvatar');
      } else {
        print('⚠️ _loadUserProfile: No authenticated user found');
      }
    } catch (error) {
      print('❌ _loadUserProfile: Error occurred - $error');
      print('📍 _loadUserProfile: Error type - ${error.runtimeType}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        print('🔄 _loadUserProfile: Set loading state to false');
      }
    }
  }

  Future<void> _updateProfile() async {
    print('💾 _updateProfile: Starting profile update');
    try {
      setState(() {
        _isLoading = true;
      });
      print('🔄 _updateProfile: Set loading state to true');

      final user = Supabase.instance.client.auth.currentUser;
      print('👤 _updateProfile: Current user - ${user?.id ?? 'null'}');

      if (user != null) {
        // Use selectedAvatar if it exists, otherwise keep current avatar
        final avatarToSave = selectedAvatar ?? _currentAvatarUrl;

        final profileData = {
          'id': user.id,
          'username': _usernameController.text.trim(),
          'date_of_birth': _dobController.text.trim(),
          'level': _selectedLevel,
          'department': _departmentController.text.trim(),
          'class': _classController.text.trim(),
          'avatar_url': avatarToSave, // This ensures we don't set null
          'updated_at': DateTime.now().toIso8601String(),
        };

        print('📤 _updateProfile: Sending profile data to database:');
        print('   - ID: ${profileData['id']}');
        print('   - Username: ${profileData['username']}');
        print('   - DOB: ${profileData['date_of_birth']}');
        print('   - Level: ${profileData['level']}');
        print('   - Department: ${profileData['department']}');
        print('   - Class: ${profileData['class']}');
        print('   - Avatar URL: ${profileData['avatar_url']}');
        print('   - Updated At: ${profileData['updated_at']}');

        await Supabase.instance.client.from('users').upsert(profileData);
        print('✅ _updateProfile: Profile updated successfully in database');

        // Update current avatar URL after successful save
        _currentAvatarUrl = avatarToSave;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
          // Go back to previous screen
          Navigator.of(context).pop();
        }
      } else {
        print('⚠️ _updateProfile: No authenticated user found');
      }
    } catch (error) {
      print('❌ _updateProfile: Error occurred - $error');
      print('📍 _updateProfile: Error type - ${error.runtimeType}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        print('🔄 _updateProfile: Set loading state to false');
      }
    }
  }

  Future<void> _selectAvatar() async {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (context) => Padding(
            padding: const EdgeInsets.all(16),
            child: DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Text(
                      'Select an Avatar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollController,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 1,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: preset_avatars.length,
                        itemBuilder: (context, index) {
                          final avatarUrl = preset_avatars[index];
                          final isSelected = selectedAvatar == avatarUrl;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedAvatar = avatarUrl;
                              });
                              print('🖼️ Avatar selected: $avatarUrl');
                              Navigator.pop(context);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    isSelected
                                        ? Border.all(
                                          color: Theme.of(context).primaryColor,
                                          width: 3,
                                        )
                                        : null,
                              ),
                              child: CircleAvatar(
                                radius:
                                    isSelected
                                        ? 47
                                        : 50, // Slightly smaller when selected to account for border
                                backgroundImage: NetworkImage(avatarUrl),
                                backgroundColor: Colors.grey[200],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
    );
  }

  Future<void> _selectDate() async {
    print('📅 _selectDate: Opening date picker');
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(
        const Duration(days: 6570),
      ), // ~18 years ago
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    print(
      '📅 _selectDate: Date picker result - ${picked?.toString() ?? 'null'}',
    );

    if (picked != null) {
      final formattedDate = "${picked.day}/${picked.month}/${picked.year}";
      setState(() {
        _dobController.text = formattedDate;
      });
      print('📅 _selectDate: Date set to: $formattedDate');
    } else {
      print('📅 _selectDate: No date selected by user');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 build: Building ProfileSettingsPage widget');
    print('🔄 build: Current loading state: $_isLoading');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile Settings"),
        elevation: 0,
        centerTitle: true,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey[300]!,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.grey[200],
                                backgroundImage:
                                    selectedAvatar != null &&
                                            selectedAvatar!.isNotEmpty
                                        ? NetworkImage(selectedAvatar!)
                                        : null,
                                child:
                                    selectedAvatar == null ||
                                            selectedAvatar!.isEmpty
                                        ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.grey,
                                        )
                                        : null,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () {
                                  print('📸 Camera button tapped');
                                  _selectAvatar();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: "Username",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          print('✅ Username validation: "$value"');
                          if (value == null || value.trim().isEmpty) {
                            print('❌ Username validation failed: empty');
                            return "Please enter a username";
                          }
                          if (value.trim().length < 3) {
                            print(
                              '❌ Username validation failed: too short (${value.trim().length} chars)',
                            );
                            return "Username must be at least 3 characters";
                          }
                          print('✅ Username validation passed');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _dobController,
                        decoration: const InputDecoration(
                          labelText: "Date of Birth",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        readOnly: true,
                        onTap: () {
                          print('📅 Date field tapped');
                          _selectDate();
                        },
                        validator: (value) {
                          print('✅ DOB validation: "$value"');
                          if (value == null || value.trim().isEmpty) {
                            print('❌ DOB validation failed: empty');
                            return "Please select your date of birth";
                          }
                          print('✅ DOB validation passed');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _departmentController,
                        decoration: const InputDecoration(
                          labelText: "Department",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        validator: (value) {
                          print('✅ Department validation: "$value"');
                          if (value == null || value.trim().isEmpty) {
                            print('❌ Department validation failed: empty');
                            return "Please enter your department";
                          }
                          print('✅ Department validation passed');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: _selectedLevel,
                        items: const [
                          DropdownMenuItem(
                            value: 100,
                            child: Text('100 Level'),
                          ),
                          DropdownMenuItem(
                            value: 200,
                            child: Text('200 Level'),
                          ),
                          DropdownMenuItem(
                            value: 300,
                            child: Text('300 Level'),
                          ),
                          DropdownMenuItem(
                            value: 400,
                            child: Text('400 Level'),
                          ),
                          DropdownMenuItem(
                            value: 500,
                            child: Text('500 Level'),
                          ),
                        ],
                        onChanged: (int? newValue) {
                          print('📊 Level dropdown changed: $newValue');
                          setState(() {
                            _selectedLevel = newValue;
                            _levelController.text = newValue?.toString() ?? '';
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: "Level",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.grade_outlined),
                        ),
                        validator: (value) {
                          print('✅ Level validation: $value');
                          if (value == null) {
                            print('❌ Level validation failed: not selected');
                            return "Please select your level";
                          }
                          print('✅ Level validation passed');
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _classController,
                        decoration: const InputDecoration(
                          labelText: "Class",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.class_outlined),
                        ),
                        validator: (value) {
                          print('✅ Class validation: "$value"');
                          if (value == null || value.trim().isEmpty) {
                            print('❌ Class validation failed: empty');
                            return "Please enter your class";
                          }
                          print('✅ Class validation passed');
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed:
                            _isLoading
                                ? null
                                : () {
                                  print('💾 Save button pressed');
                                  if (_formKey.currentState?.validate() ??
                                      false) {
                                    print(
                                      '✅ Form validation passed, updating profile',
                                    );
                                    _updateProfile();
                                  } else {
                                    print('❌ Form validation failed');
                                  }
                                },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text(
                                  "Save Changes",
                                  style: TextStyle(fontSize: 16),
                                ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
