import 'package:flutter/material.dart';
import 'package:map/avatars.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _dobController = TextEditingController();
  final _levelController = TextEditingController();
  final _genderController = TextEditingController();
  final _departmentController = TextEditingController();

  bool _isLoading = false;
  String? _selectedDepartment;
  String? _selectedLevel;
  String? _selectedGender;
  DateTime? _selectedBirthDate;
  File? _profileImage;
  String? _profileImageUrl;
  String? selectedAvatar;
  String? _currentAvatarUrl;

  // Department options - you can customize these based on your institution
  final List<String> _departments = [
    'Computer Science',
    'Engineering',
    'Business Administration',
    'Medicine',
    'Law',
    'Arts & Sciences',
    'Education',
    'Economics',
    'Psychology',
    'Mathematics',
    'Physics',
    'Chemistry',
    'Biology',
    'English',
    'History',
    'Political Science',
    'Sociology',
    'Philosophy',
  ];

  // Level options from 100 to 500
  final List<String> _levels = ['100', '200', '300', '400', '500'];

  final List<String> _genders = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    //_loadExistingProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // Future<void> _loadExistingProfile() async {
  //   final user = supabase.auth.currentUser;
  //   if (user != null) {
  //     // Pre-fill email if available
  //     final userMetadata = user.userMetadata;
  //     if (userMetadata != null) {
  //       setState(() {
  //         _firstNameController.text = userMetadata['first_name'] ?? '';
  //         _lastNameController.text = userMetadata['last_name'] ?? '';
  //         _usernameController.text = userMetadata['username'] ?? '';
  //         _phoneController.text = userMetadata['phone'] ?? '';
  //         _bioController.text = userMetadata['bio'] ?? '';
  //         _selectedDepartment = userMetadata['department'];
  //         _selectedLevel = userMetadata['level'];
  //         _selectedGender = userMetadata['gender'];
  //         _profileImageUrl = userMetadata['profile_image_url'];

  //         // Parse birth date if available
  //         if (userMetadata['birth_date'] != null) {
  //           try {
  //             _selectedBirthDate = DateTime.parse(userMetadata['birth_date']);
  //           } catch (e) {
  //             debugPrint('Error parsing birth date: $e');
  //           }
  //         }
  //       });
  //     }
  //   }
  // }

  // ignore: unused_element
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _profileImage = File(image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ignore: unused_element
  Future<String?> _uploadProfileImage() async {
    if (_profileImage == null) return _profileImageUrl;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      final fileName =
          'profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await _profileImage!.readAsBytes();

      await supabase.storage.from('profiles').uploadBinary(fileName, bytes);

      final imageUrl = supabase.storage.from('profiles').getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedBirthDate) {
      setState(() {
        _selectedBirthDate = picked;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final avatarToSave = selectedAvatar ?? _currentAvatarUrl;
        final profileData = {
          'id': user.id,
          'username': _usernameController.text.trim(),
          'date_of_birth': _dobController.text.trim(),
          'level': _selectedLevel,
          'department': _departmentController.text.trim(),
          'class': _levelController.text.trim(),
          'avatar_url': avatarToSave, // This ensures we don't set null
          'updated_at': DateTime.now().toIso8601String(),
        };

        await Supabase.instance.client.from('users').upsert(profileData);
        print('✅ _updateProfile: Profile updated successfully in database');
        _currentAvatarUrl = avatarToSave;
      }

      // Upload profile image if selected
      //

      // Prepare user metadata
      final userData = {
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'bio': _bioController.text.trim(),
        'department': _selectedDepartment,
        'level': _selectedLevel,
        'gender': _selectedGender,
        'birth_date': _selectedBirthDate?.toIso8601String(),
        // 'profile_image_url': imageUrl,
        'profile_completed': true,
      };

      debugPrint('🔄 Updating user profile...');

      // Update user metadata
      await supabase.auth.updateUser(UserAttributes(data: userData));

      debugPrint('✅ Profile updated successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to main app - you should replace this with your main app screen
        // For now, we'll just pop back or you can navigate to your home screen
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home', // Replace with your home route
          (route) => false,
        );
      }
    } catch (error) {
      debugPrint('❌ Error saving profile: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _skipForNow() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Skip Profile Setup?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You can complete your profile later from settings. Are you sure you want to skip?',
            style: TextStyle(color: Colors.grey[600]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/home', // Replace with your home route
                  (route) => false,
                );
              },
              child: Text('Skip'),
            ),
          ],
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Complete Your Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _skipForNow,
            child: Text(
              'Skip',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress indicator
                  Container(
                    width: double.infinity,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.7, // 70% complete
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Step 2 of 2',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  SizedBox(height: 24),

                  Text(
                    'Let\'s get to know you better!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Fill in your details to complete your profile',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  SizedBox(height: 32),

                  // Profile Image Section
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _selectAvatar,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[100],
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 2,
                              ),
                            ),
                            child:
                                _profileImage != null
                                    ? ClipRRect(
                                      borderRadius: BorderRadius.circular(60),
                                      child: Image.file(
                                        _profileImage!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                    : _currentAvatarUrl != null
                                    ? ClipRRect(
                                      borderRadius: BorderRadius.circular(60),
                                      child: Image.network(
                                        _currentAvatarUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                    : Icon(
                                      Icons.camera_alt_outlined,
                                      size: 40,
                                      color: Colors.grey[400],
                                    ),
                          ),
                        ),
                        SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _selectAvatar,
                          icon: Icon(Icons.edit, size: 16),
                          label: Text(
                            _profileImage != null || _currentAvatarUrl != null
                                ? 'Change Photo'
                                : 'Add Photo',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 32),

                  // Personal Information Section
                  Text(
                    'Personal Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 16),

                  // First Name and Last Name Row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: InputDecoration(
                            labelText: 'First Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: InputDecoration(
                            labelText: 'Last Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Username Field
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.alternate_email),
                      filled: true,
                      fillColor: Colors.grey[50],
                      helperText: 'This will be your unique identifier',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a username';
                      }
                      if (value.length < 3) {
                        return 'Username must be at least 3 characters';
                      }
                      if (!RegExp(r'^[a-zA-Z0-9_]+').hasMatch(value)) {
                        return 'Username can only contain letters, numbers, and underscores';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Phone Number Field
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone Number (Optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.phone_outlined),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  SizedBox(height: 16),

                  // Gender and Birth Date Row
                  DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: InputDecoration(
                      labelText: 'Gender',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.person_outline),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    items:
                        _genders.map((String gender) {
                          return DropdownMenuItem<String>(
                            value: gender,
                            child: Text(gender),
                          );
                        }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedGender = newValue;
                        _genderController.text = newValue?.toString() ?? '';
                      });
                    },
                  ),
                  SizedBox(height: 12),
                  GestureDetector(
                    onTap: _selectBirthDate,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[50],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.grey[600],
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedBirthDate != null
                                  ? '${_selectedBirthDate!.day}/${_selectedBirthDate!.month}/${_selectedBirthDate!.year}'
                                  : 'Birth Date',
                              style: TextStyle(
                                color:
                                    _selectedBirthDate != null
                                        ? Colors.black87
                                        : Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Academic Information Section
                  Text(
                    'Academic Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 16),

                  // Department Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedDepartment,
                    decoration: InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.school_outlined),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    items:
                        _departments.map((String department) {
                          return DropdownMenuItem<String>(
                            value: department,
                            child: Text(department),
                          );
                        }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedDepartment = newValue;
                        _departmentController.text = newValue?.toString() ?? '';
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select your department';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Level Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedLevel,
                    decoration: InputDecoration(
                      labelText: 'Level',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.grade_outlined),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    items:
                        _levels.map((String level) {
                          return DropdownMenuItem<String>(
                            value: level,
                            child: Text('Level $level'),
                          );
                        }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedLevel = newValue;
                        _levelController.text = newValue?.toString() ?? '';
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select your level';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Bio Field
                  TextFormField(
                    controller: _bioController,
                    decoration: InputDecoration(
                      labelText: 'Bio (Optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.description_outlined),
                      filled: true,
                      fillColor: Colors.grey[50],
                      helperText: 'Tell us a bit about yourself',
                    ),
                    maxLines: 3,
                    maxLength: 500,
                  ),
                  SizedBox(height: 32),

                  // Complete Profile Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child:
                          _isLoading
                              ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                              : Text(
                                'Complete Profile',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
