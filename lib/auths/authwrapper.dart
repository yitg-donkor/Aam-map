import 'dart:async';

import 'package:flutter/material.dart';
import 'package:map/pages/log_in_page.dart';
import 'package:map/pages/mainscreen.dart';
import 'package:map/services/firebase_service.dart';
import 'package:map/services/auth_bridge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isInitialized = false;
  supabase.Session? _session;
  String? _errorMessage;
  late final supabase.SupabaseClient _supabase;
  late final StreamSubscription<supabase.AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _supabase = supabase.Supabase.instance.client;
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();

    // Update offline status when app is closed
    if (_session != null && AuthBridgeService.isAuthenticated) {
      AuthBridgeService.updateOnlineStatus(false).catchError((error) {
        debugPrint('Error updating offline status: $error');
      });
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Handle app state changes for online/offline status
    if (_session != null && AuthBridgeService.isAuthenticated) {
      switch (state) {
        case AppLifecycleState.resumed:
          AuthBridgeService.updateOnlineStatus(true).catchError((error) {
            debugPrint('Error updating online status: $error');
          });
          break;
        case AppLifecycleState.paused:
        case AppLifecycleState.inactive:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          AuthBridgeService.updateOnlineStatus(false).catchError((error) {
            debugPrint('Error updating offline status: $error');
          });
          break;
      }
    }
  }

  Future<void> _initializeApp() async {
    try {
      debugPrint('🔄 Starting app initialization...');

      // Initialize Firebase and Auth Bridge
      try {
        await FirebaseService.initialize();
        debugPrint('✅ Firebase and Auth Bridge initialized');
        _isInitialized = true;
      } catch (firebaseError) {
        debugPrint(
          '❌ Firebase/Auth Bridge initialization failed: $firebaseError',
        );
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to initialize services: $firebaseError';
            _isLoading = false;
          });
        }
        return;
      }

      // Get initial session
      await _getInitialSession();

      // Setup auth listener
      _setupAuthListener();

      debugPrint('✅ App initialization complete');
    } catch (error) {
      debugPrint('❌ Error initializing app: $error');
      if (mounted) {
        setState(() {
          _errorMessage = 'Initialization failed: $error';
          _session = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getInitialSession() async {
    try {
      final session = _supabase.auth.currentSession;

      debugPrint(
        '🔍 Initial session check: ${session?.user?.email ?? "No session found"}',
      );

      if (session != null) {
        debugPrint('📋 Session details:');
        debugPrint('   - User ID: ${session.user.id}');
        debugPrint('   - Email: ${session.user.email}');
        debugPrint('   - Expires at: ${session.expiresAt}');
        debugPrint(
          '   - Access token exists: ${session.accessToken.isNotEmpty}',
        );

        // Wait for auth bridge to complete if user is signed in
        await _waitForAuthBridge();
      }

      if (mounted) {
        setState(() {
          _session = session;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (error) {
      debugPrint('❌ Error getting initial session: $error');
      if (mounted) {
        setState(() {
          _session = null;
          _isLoading = false;
          _errorMessage = 'Session error: $error';
        });
      }
    }
  }

  Future<void> _waitForAuthBridge() async {
    // Wait up to 5 seconds for the auth bridge to complete
    const maxWaitTime = Duration(seconds: 5);
    const checkInterval = Duration(milliseconds: 100);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      if (AuthBridgeService.isAuthenticated) {
        debugPrint('✅ Auth bridge authentication completed');
        return;
      }
      await Future.delayed(checkInterval);
    }

    debugPrint('⚠️ Auth bridge authentication timed out, but continuing...');
  }

  void _setupAuthListener() {
    debugPrint('🎧 Setting up auth state listener...');

    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (data) async {
        final supabase.AuthChangeEvent event = data.event;
        final supabase.Session? session = data.session;

        debugPrint('🔔 Auth state changed: $event');
        debugPrint('   User: ${session?.user?.email ?? "No user"}');
        debugPrint('   Session exists: ${session != null}');
        debugPrint('   Widget mounted: $mounted');

        if (mounted) {
          debugPrint('🔄 Updating state with new session...');
          setState(() {
            _session = session;
            _errorMessage = null;
          });
          debugPrint(
            '✅ State updated. Current session: ${_session != null ? "EXISTS" : "NULL"}',
          );
        }

        // Handle specific auth events
        switch (event) {
          case supabase.AuthChangeEvent.signedIn:
            debugPrint('✅ User signed in: ${session?.user?.email}');
            if (session != null && mounted) {
              // Wait for auth bridge before showing success
              await _waitForAuthBridge();

              if (AuthBridgeService.isAuthenticated) {
                _showSnackBar('Welcome! Successfully signed in.', Colors.green);
              } else {
                _showSnackBar(
                  'Signed in, but some features may be limited.',
                  Colors.orange,
                );
              }
            }
            break;

          case supabase.AuthChangeEvent.signedOut:
            debugPrint('👋 User signed out');
            if (mounted) {
              _showSnackBar('You have been signed out.', Colors.orange);
            }
            break;

          case supabase.AuthChangeEvent.tokenRefreshed:
            debugPrint('🔄 Token refreshed');
            break;

          case supabase.AuthChangeEvent.userUpdated:
            debugPrint('📝 User updated');
            break;

          case supabase.AuthChangeEvent.passwordRecovery:
            debugPrint('🔑 Password recovery initiated');
            if (mounted) {
              _showSnackBar('Password recovery email sent.', Colors.blue);
            }
            break;

          default:
            debugPrint('❓ Unknown auth event: $event');
            break;
        }
      },
      onError: (error) {
        debugPrint('❌ Auth state change error: $error');
        if (mounted) {
          setState(() {
            _errorMessage = 'Authentication error: $error';
          });
          _showSnackBar('Authentication error occurred.', Colors.red);
        }
      },
    );
  }

  void _showSnackBar(String message, Color backgroundColor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _retryInitialization() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 Building AuthWrapper...');
    debugPrint('   - Loading: $_isLoading');
    debugPrint('   - Session exists: ${_session != null}');
    debugPrint('   - Initialized: $_isInitialized');
    debugPrint('   - Auth Bridge Ready: ${AuthBridgeService.isAuthenticated}');
    debugPrint('   - Error: $_errorMessage');
    debugPrint('   - Mounted: $mounted');

    // Show loading screen while initializing
    if (_isLoading) {
      debugPrint('📺 Showing loading screen');
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Initializing...',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Setting up secure connection',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    // Show error screen if initialization failed
    if (_errorMessage != null && !_isInitialized) {
      debugPrint('📺 Showing error screen');
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 24),
                Text(
                  'Initialization Failed',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _retryInitialization,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show main screen if user is authenticated
    if (_session != null) {
      debugPrint('📺 Showing Mainscreen for user: ${_session!.user.email}');
      debugPrint('   - User ID: ${_session!.user.id}');
      debugPrint(
        '   - Auth Bridge Status: ${AuthBridgeService.isAuthenticated}',
      );

      // Show warning if auth bridge is not ready
      if (!AuthBridgeService.isAuthenticated) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Setting up secure messaging...',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take a few moments',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        );
      }

      return const Mainscreen();
    }

    // Show login screen if user is not authenticated
    debugPrint('📺 Showing LoginScreen - no authenticated user');
    return const LoginScreen();
  }
}
