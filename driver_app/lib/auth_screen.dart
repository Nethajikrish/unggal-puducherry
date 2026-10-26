import 'package:flutter/material.dart';
import 'api.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onDone;
  const AuthScreen({super.key, required this.onDone});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final _license = TextEditingController();
  String _vehicleType = 'auto';
  bool _register = false;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (_register) {
        await Api.register(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
          vehicleType: _vehicleType,
          vehicleNumber: _vehicleNumber.text.trim(),
          licenseNumber: _license.text.trim(),
        );
      } else {
        await Api.login(_phone.text.trim(), _password.text);
      }
      widget.onDone();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.local_taxi, size: 72, color: Colors.orange),
                const SizedBox(height: 8),
                Text('Driver — Nama Puducherry',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 32),
                if (_register) ...[
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: const InputDecoration(labelText: 'Mobile number', counterText: ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (min 6)'),
                ),
                if (_register) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _vehicleType,
                    decoration: const InputDecoration(labelText: 'Vehicle type'),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto')),
                      DropdownMenuItem(value: 'hatchback', child: Text('Hatchback')),
                      DropdownMenuItem(value: 'sedan', child: Text('Sedan')),
                      DropdownMenuItem(value: 'suv', child: Text('SUV')),
                    ],
                    onChanged: (v) => setState(() => _vehicleType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehicleNumber,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Vehicle number (e.g. PY01AB1234)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _license, decoration: const InputDecoration(labelText: 'Driving licence number')),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Please wait…' : (_register ? 'Register as driver' : 'Login')),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register ? 'Have an account? Login' : 'New driver? Register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
