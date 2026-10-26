import 'package:flutter/material.dart';
import 'api.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const CustomerApp());
}

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key});
  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  bool get _loggedIn => Api.token != null;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nama Puducherry Cabs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: _loggedIn
          ? HomeScreen(onLogout: () async {
              await Api.logout();
              setState(() {});
            })
          : AuthScreen(onDone: () => setState(() {})),
    );
  }
}
