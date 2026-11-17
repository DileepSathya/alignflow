import 'package:flutter/material.dart';
import 'api.dart';
import 'orders_page.dart';
import 'role_shell.dart';
import 'demo_style.dart';

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
  String section = 'Orders';
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    final people = (clinic?['clinicians'] as List?) ?? [];
    return RoleShell(
      title: section,
      sidebar: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              DemoBrandMark(size: 34),
              SizedBox(width: 9),
              Text('AlignFlow',
                  style: TextStyle(
                      fontFamily: 'Bricolage',
                      fontSize: 19,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DemoStyle.accentSoft,
              border: Border.all(color: DemoStyle.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFBCE2DE),
                child: Text(
                  (widget.user['username']?.toString().isNotEmpty == true
                          ? widget.user['username'].toString()[0]
                          : 'C')
                      .toUpperCase(),
                  style: const TextStyle(color: DemoStyle.accent),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.user['username']?.toString() ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  const Text('Clinic admin',
                      style: TextStyle(fontSize: 11, color: DemoStyle.muted)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 24),
          for (final item in [
            ('Orders', Icons.receipt_long_outlined),
            ('Clinicians', Icons.people_outline)
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ListTile(
                dense: true,
                selected: section == item.$1,
                selectedTileColor: DemoStyle.accentSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: section == item.$1
                          ? DemoStyle.accent
                          : Colors.transparent),
                ),
                leading: Icon(item.$2,
                    size: 19,
                    color:
                        section == item.$1 ? DemoStyle.accent : DemoStyle.ink),
                title: Text(item.$1,
                    style: TextStyle(
                        fontSize: 13,
                        color: section == item.$1
                            ? DemoStyle.accent
                            : DemoStyle.ink)),
                trailing: item.$1 == 'Clinicians'
                    ? Text('${people.length}',
                        style: const TextStyle(fontSize: 11))
                    : null,
                onTap: () {
                  setState(() => section = item.$1);
                  if (compact) Navigator.of(context).pop();
                },
              ),
            ),
          const Spacer(),
          const Divider(),
          OutlinedButton(
            onPressed: () async {
              await widget.api.logout();
              widget.onLogout();
            },
            child: const Text('Log out'),
          ),
        ]),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: RoleShell.contentWidth),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: clinic == null
                ? Center(
                    child: error == null
                        ? const CircularProgressIndicator()
                        : Text(error!))
                : section == 'Orders'
                    ? OrdersPage(
                        api: widget.api, clinics: [clinic!], user: widget.user)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            Row(children: [
                              Expanded(
                                  child: DemoPageHeading(
                                title: 'Clinicians',
                                subtitle:
                                    'Manage clinicians at ${clinic!['clinic_name']}.',
                              )),
                              FilledButton.icon(
                                onPressed: add,
                                icon: const Icon(Icons.add),
                                label: Text(compact ? 'Add' : 'Add clinician'),
                              ),
                            ]),
                            const SizedBox(height: 18),
                            if (error != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(error!,
                                      style:
                                          const TextStyle(color: Colors.red))),
                            Expanded(
                                child: people.isEmpty
                                    ? const Center(
                                        child: Text(
                                            'No clinicians yet. Add your first clinician.'))
                                    : Card(
                                        child: ListView.separated(
                                        itemCount: people.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(height: 1),
                                        itemBuilder: (_, index) {
                                          final person = people[index]
                                              as Map<String, dynamic>;
                                          return ListTile(
                                            leading: const CircleAvatar(
                                                child:
                                                    Icon(Icons.person_outline)),
                                            title: Text(
                                                person['name']?.toString() ??
                                                    ''),
                                            subtitle: Text(
                                                '${person['clinical_role'] ?? 'doctor'} · ${person['mobile_number'] ?? ''}'),
                                            trailing: person['account_id'] ==
                                                    widget.user['id']
                                                ? const Chip(
                                                    label: Text('Admin'))
                                                : null,
                                          );
                                        },
                                      ))),
                          ]),
          ),
        ),
      ),
    );
  }
}
