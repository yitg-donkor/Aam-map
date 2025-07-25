import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  String? _profilePictureUrl;
  int? _selectedLevel;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _dobController.dispose();
    _departmentController.dispose();
    _levelController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response =
            await Supabase.instance.client
                .from('profiles')
                .select()
                .eq('id', user.id)
                .single();

        final profile = response;
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
          _profilePictureUrl = profile['profile_picture'];
        });
      }
    } catch (error) {
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
      }
    }
  }

  Future<void> _updateProfile() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profileData = {
          'id': user.id,
          'username': _usernameController.text.trim(),
          'date_of_birth': _dobController.text.trim(),
          'level': _selectedLevel,
          'department': _departmentController.text.trim(),
          'class': _classController.text.trim(),
          'profile_picture': _profilePictureUrl,
          'updated_at': DateTime.now().toIso8601String(),
        };

        await Supabase.instance.client.from('profiles').upsert(profileData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
        }
      }
    } catch (error) {
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
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _isLoading = true;
        });

        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          throw Exception('User not authenticated');
        }

        // Create a unique filename
        final fileExtension = pickedFile.path.split('.').last.toLowerCase();
        final fileName =
            '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
        final filePath = 'profile_pictures/$fileName';

        // Upload the image to Supabase Storage
        final fileBytes = await pickedFile.readAsBytes();
        await Supabase.instance.client.storage
            .from('profile_pictures')
            .uploadBinary(filePath, fileBytes);

        // Get the public URL
        final imageUrl = Supabase.instance.client.storage
            .from('profile_pictures')
            .getPublicUrl(filePath);

        setState(() {
          _profilePictureUrl = imageUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image uploaded successfully')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(
        const Duration(days: 6570),
      ), // ~18 years ago
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _dobController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile Settings"), elevation: 0),
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
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey[300],
                              backgroundImage:
                                  _profilePictureUrl != null
                                      ? NetworkImage(_profilePictureUrl!)
                                      : null,
                              child:
                                  _profilePictureUrl == null
                                      ? const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.grey,
                                      )
                                      : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).primaryColor,
                                    shape: BoxShape.circle,
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
                          if (value == null || value.trim().isEmpty) {
                            return "Please enter a username";
                          }
                          if (value.trim().length < 3) {
                            return "Username must be at least 3 characters";
                          }
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
                        onTap: _selectDate,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Please select your date of birth";
                          }
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
                          if (value == null || value.trim().isEmpty) {
                            return "Please enter your department";
                          }
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
                          if (value == null) {
                            return "Please select your level";
                          }
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
                          if (value == null || value.trim().isEmpty) {
                            return "Please enter your class";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed:
                            _isLoading
                                ? null
                                : () {
                                  if (_formKey.currentState?.validate() ??
                                      false) {
                                    _updateProfile();
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
