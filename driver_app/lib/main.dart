import 'package:flutter/material.dart';
import 'api.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const DriverApp());
}

class DriverApp extends StatefulWidget {
  const DriverApp({super.key});
  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nama Puducherry Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
      home: Api.token != null
          ? HomeScreen(onLogout: () async {
              await Api.logout();
              setState(() {});
            })
          : AuthScreen(onDone: () => setState(() {})),
    );
  }
}
