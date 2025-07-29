// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:map/auths/authwrapper.dart';
import 'package:map/pages/mainscreen.dart';
import 'package:map/pages/sign_up_page.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  final accessToken = dotenv.env['AcessToken'] ?? '';
  MapboxOptions.setAccessToken(accessToken);
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Map App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AuthWrapper(),
    );
  }
}
