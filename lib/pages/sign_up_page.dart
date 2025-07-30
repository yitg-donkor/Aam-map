import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:map/profile_page_routes/profile_setup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isFacebookLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Fixed redirect URLs for different platforms
  String get _redirectUrl {
    if (kIsWeb) {
      final uri = Uri.base;
      return '${uri.origin}/auth/callback';
    } else {
      return 'com.example.mapapp://login-callback/';
    }
  }

  final SupabaseClient supabase = Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      debugPrint('🔄 Attempting sign up for: $email');

      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      debugPrint('✅ Sign up response received');
      debugPrint('   - User: ${response.user?.email}');
      debugPrint('   - Session: ${response.session != null}');

      if (mounted) {
        if (response.user != null && response.session == null) {
          // Email confirmation required
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please check your email for confirmation link!'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        } else if (response.user != null) {
          // Account created and logged in - navigate to profile setup
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account created! Please complete your profile.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfileSetupScreen()),
          );
        }
      }
    } on AuthException catch (error) {
      debugPrint('❌ Auth error during sign up: ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${error.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      debugPrint('❌ Unexpected error during sign up: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error occurred'),
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

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      debugPrint('🔄 Starting Google OAuth...');
      debugPrint('   - Redirect URL: $_redirectUrl');

      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      debugPrint('✅ Google OAuth initiated');

      // Note: For OAuth, the actual navigation to profile setup should be handled
      // in your AuthWrapper or main authentication flow listener since the
      // OAuth callback happens outside this widget
    } on AuthException catch (error) {
      debugPrint('❌ Google OAuth error: ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in error: ${error.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      debugPrint('❌ Unexpected error during Google OAuth: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error during Google sign-in'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() {
      _isFacebookLoading = true;
    });

    try {
      debugPrint('🔄 Starting Facebook OAuth...');
      debugPrint('   - Redirect URL: $_redirectUrl');

      await supabase.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      debugPrint('✅ Facebook OAuth initiated');

      // Note: For OAuth, the actual navigation to profile setup should be handled
      // in your AuthWrapper or main authentication flow listener since the
      // OAuth callback happens outside this widget
    } on AuthException catch (error) {
      debugPrint('❌ Facebook OAuth error: ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Facebook sign-in error: ${error.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      debugPrint('❌ Unexpected error during Facebook OAuth: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error during Facebook sign-in'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFacebookLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 30),
                  Text(
                    'Create Account',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sign up to get started',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 30),

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}',
                      ).hasMatch(value)) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Confirm Password Field
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    obscureText: _obscureConfirmPassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 24),

                  // Sign Up Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signUp,
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
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                    ),
                  ),
                  SizedBox(height: 32),

                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[300])),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Or continue with',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey[300])),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Google Sign Up Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 1,
                      ),
                      onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                      child:
                          _isGoogleLoading
                              ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.grey[600],
                                  strokeWidth: 2,
                                ),
                              )
                              : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FaIcon(
                                    FontAwesomeIcons.google,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Continue with Google',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ),
                  SizedBox(height: 12),

                  // Facebook Sign Up Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1877F2),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed:
                          _isFacebookLoading ? null : _signInWithFacebook,
                      child:
                          _isFacebookLoading
                              ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                              : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FaIcon(FontAwesomeIcons.facebook, size: 18),
                                  SizedBox(width: 12),
                                  Text(
                                    'Continue with Facebook',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ),
                  SizedBox(height: 32),

                  // Sign In Link
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed:
                        _isLoading
                            ? null
                            : () {
                              Navigator.pop(context);
                            },
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 16),
                        children: [
                          TextSpan(
                            text: "Already have an account? ",
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          TextSpan(
                            text: "Sign in",
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
