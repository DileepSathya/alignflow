import 'package:flutter/material.dart';
import 'api.dart';

class ClinicSignupPage extends StatefulWidget {
  final Api api;
  const ClinicSignupPage({super.key, required this.api});
  @override
  State<ClinicSignupPage> createState() => _ClinicSignupPageState();
}

class _ClinicSignupPageState extends State<ClinicSignupPage> {
  final fields = <String, TextEditingController>{
    for (final key in [
      'clinic_name',
      'contact_number',
      'email',
      'business_address',
      'clinician_name',
      'clinician_mobile',
      'clinician_email',
      'clinical_role',
      'username',
      'password'
    ])
      key: TextEditingController(),
  };
  bool busy = false;
  String? message;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (fields.values.any((c) => c.text.trim().isEmpty)) {
      setState(() => message = 'Complete every field.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.api.request('POST', '/api/clinic-signup',
          {for (final e in fields.entries) e.key: e.value.text.trim()});
      if (mounted)
        setState(() => message =
            'Registration sent. You can log in after admin approval.');
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Register clinic')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                for (final e in fields.entries)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                          controller: e.value,
                          obscureText: e.key == 'password',
                          decoration: InputDecoration(
                              labelText: e.key.replaceAll('_', ' ')))),
                if (message != null) Text(message!),
                FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Submitting...' : 'Register')),
              ]))));
}
