import 'package:flutter/material.dart';
import 'api.dart';
import 'orders_page.dart';

class ClinicWorkspace extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const ClinicWorkspace(
      {super.key,
      required this.api,
      required this.user,
      required this.onLogout});
  @override
  State<ClinicWorkspace> createState() => _ClinicWorkspaceState();
}

class _ClinicWorkspaceState extends State<ClinicWorkspace> {
  Map<String, dynamic>? clinic;
  String? error;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final data = await widget.api.request('GET', '/api/my-clinic');
      if (mounted)
        setState(() => clinic = data['clinic'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> add() async {
    final name = TextEditingController(),
        mobile = TextEditingController(),
        email = TextEditingController(),
        role = TextEditingController(text: 'doctor');
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Add clinician'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name')),
                  TextField(
                      controller: mobile,
                      decoration:
                          const InputDecoration(labelText: 'Mobile number')),
                  TextField(
                      controller: email,
                      decoration: const InputDecoration(labelText: 'Email')),
                  TextField(
                      controller: role,
                      decoration:
                          const InputDecoration(labelText: 'Clinical role')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Add'))
                ]));
    if (ok == true) {
      try {
        await widget.api.request('POST', '/api/my-clinic/clinicians', {
          'name': name.text.trim(),
          'mobile_number': mobile.text.trim(),
          'email': email.text.trim(),
          'clinical_role': role.text.trim()
        });
        await refresh();
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      }
    }
    name.dispose();
    mobile.dispose();
    email.dispose();
    role.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(clinic?['clinic_name']?.toString() ?? 'Clinic'),
          actions: [
            TextButton(
                onPressed: () async {
                  await widget.api.logout();
                  widget.onLogout();
                },
                child: const Text('Log out'))
          ]),
      body: clinic == null
          ? Center(child: Text(error ?? 'Loading...'))
          : Column(children: [
              SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Orders')),
                    ButtonSegment(value: 1, label: Text('Clinicians'))
                  ],
                  selected: {
                    tab
                  },
                  onSelectionChanged: (value) =>
                      setState(() => tab = value.first)),
              if (error != null) Text(error!),
              Expanded(
                  child: tab == 0
                      ? OrdersPage(
                          api: widget.api,
                          clinics: [clinic!],
                          user: widget.user)
                      : ListView(children: [
                          ListTile(
                              title: const Text('Clinicians'),
                              trailing: IconButton(
                                  onPressed: add, icon: const Icon(Icons.add))),
                          for (final person in (clinic!['clinicians'] as List))
                            ListTile(
                                title: Text(person['name'].toString()),
                                subtitle: Text(
                                    '${person['clinical_role'] ?? 'doctor'} · ${person['mobile_number']}')),
                        ])),
            ]));
}
