import 'package:flutter/material.dart';
import 'package:map/pages/log_in_page.dart';
import 'package:map/pages/mainscreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Authwrapper extends StatefulWidget {
  const Authwrapper({super.key});

  @override
  State<Authwrapper> createState() => _AuthwrapperState();
}

class _AuthwrapperState extends State<Authwrapper> {
  bool _isLoading = true;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _getInitialSession();
    _setupAuthListener();
  }

  Future<void> _getInitialSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      setState(() {
        _session = session;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _session = null;
        _isLoading = false;
      });
    }
  }

  void _setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;

      setState(() {
        _session = session;
      });

      // Optional: Handle specific auth events
      switch (event) {
        case AuthChangeEvent.signedIn:
          print('User signed in');
          break;
        case AuthChangeEvent.signedOut:
          print('User signed out');
          break;
        case AuthChangeEvent.tokenRefreshed:
          print('Token refreshed');
          break;
        default:
          break;
      }
    });
  }

  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_session != null) {
      return Mainscreen();
    }
    return LoginScreen();
  }
}
