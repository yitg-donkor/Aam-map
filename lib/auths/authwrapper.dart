import 'package:flutter/material.dart';
import 'package:map/pages/log_in_page.dart';
import 'package:map/pages/mainscreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isLoading = true;
  Session? _session;
  late final SupabaseClient _supabase;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    WidgetsBinding.instance.addObserver(this);
    _getInitialSession();
    _setupAuthListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Handle deep link when app comes back to foreground
      _supabase.auth.getSessionFromUrl(Uri.base);
    }
  }

  Future<void> _getInitialSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (mounted) {
        setState(() {
          _session = session;
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('Error getting initial session: $error');
      if (mounted) {
        setState(() {
          _session = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleDeepLink() async {
    try {
      await _supabase.auth.getSessionFromUrl(Uri.base);
    } catch (error) {
      debugPrint('Deep link handling error: $error');
    }
  }

  void _setupAuthListener() {
    _supabase.auth.onAuthStateChange.listen(
      (data) {
        final AuthChangeEvent event = data.event;
        final Session? session = data.session;

        if (mounted) {
          setState(() {
            _session = session;
          });
        }

        // Handle specific auth events with better feedback
        switch (event) {
          case AuthChangeEvent.signedIn:
            debugPrint('User signed in: ${session?.user?.email}');
            _showSnackBar('Welcome! Successfully signed in.', Colors.green);
            break;
          case AuthChangeEvent.signedOut:
            debugPrint('User signed out');
            _showSnackBar('You have been signed out.', Colors.orange);
            break;
          case AuthChangeEvent.tokenRefreshed:
            debugPrint('Token refreshed');
            break;
          case AuthChangeEvent.userUpdated:
            debugPrint('User updated');
            break;
          case AuthChangeEvent.passwordRecovery:
            debugPrint('Password recovery initiated');
            _showSnackBar('Password recovery email sent.', Colors.blue);
            break;
          default:
            break;
        }
      },
      onError: (error) {
        debugPrint('Auth state change error: $error');
        if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    // Show loading screen while checking authentication state
    if (_isLoading) {
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
              const SizedBox(height: 16),
              Text('Loading...', style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    // Show main screen if user is authenticated
    if (_session != null) {
      return Mainscreen();
    }

    // Show login screen if user is not authenticated
    return LoginScreen();
  }
}
