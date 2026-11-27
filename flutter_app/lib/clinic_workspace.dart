import 'branding.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'clinic_dashboard.dart';
import 'orders_page.dart';
import 'role_shell.dart';
import 'demo_style.dart';
import 'app_router.dart';

class ClinicWorkspace extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  final String initialSection;
  final Map<String, String> initialFilters;
  const ClinicWorkspace(
      {super.key,
      required this.api,
      required this.user,
      required this.onLogout,
      this.initialSection = 'Dashboard',
      this.initialFilters = const {}});
  @override
  State<ClinicWorkspace> createState() => _ClinicWorkspaceState();
}

class _ClinicWorkspaceState extends State<ClinicWorkspace> {
  Map<String, dynamic>? clinic;
  String? error;
  late String section = widget.initialSection;
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

  Future<void> add([Map<String, dynamic>? person]) async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _ClinicianDialog(api: widget.api, person: person));
    if (saved == true) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    final people = (clinic?['clinicians'] as List?) ?? [];
    return RoleShell(
      title: section,
      sidebar: Material(
        color: Colors.white,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: BrandLogo(),
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
                          (widget.user['username']?.toString().isNotEmpty ==
                                      true
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
                          Text(
                              widget.user['role'] == 'clinician'
                                  ? 'Doctor'
                                  : 'Clinic admin',
                              style: TextStyle(
                                  fontSize: 11, color: DemoStyle.muted)),
                        ],
                      )),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  for (final item in [
                    ('Dashboard', Icons.dashboard_outlined),
                    ('Orders', Icons.receipt_long_outlined),
                    if (widget.user['role'] == 'clinic_admin')
                      ('Doctors', Icons.people_outline)
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
                            color: section == item.$1
                                ? DemoStyle.accent
                                : DemoStyle.ink),
                        title: Text(item.$1,
                            style: TextStyle(
                                fontSize: 13,
                                color: section == item.$1
                                    ? DemoStyle.accent
                                    : DemoStyle.ink)),
                        trailing: item.$1 == 'Doctors'
                            ? Text('${people.length}',
                                style: const TextStyle(fontSize: 11))
                            : null,
                        onTap: () {
                          if (compact) Navigator.of(context).pop();
                          AppRouter.of(context).go(const {
                            'Dashboard': '/clinic/dashboard',
                            'Orders': '/clinic/orders',
                            'Doctors': '/clinic/clinicians'
                          }[item.$1]!);
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
                ])),
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
                : section == 'Dashboard'
                    ? ClinicDashboard(
                        api: widget.api,
                        clinic: clinic!,
                        user: widget.user,
                        onAddClinician: add)
                    : section == 'Orders'
                        ? OrdersPage(
                            api: widget.api,
                            clinics: [clinic!],
                            user: widget.user,
                            dashboardFilters: widget.initialFilters)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                Row(children: [
                                  Expanded(
                                      child: DemoPageHeading(
                                    title: 'Doctors',
                                    subtitle:
                                        'Manage doctors at ${clinic!['clinic_name']}.',
                                  )),
                                  FilledButton.icon(
                                    onPressed: add,
                                    icon: const Icon(Icons.add),
                                    label:
                                        Text(compact ? 'Add' : 'Add doctor'),
                                  ),
                                ]),
                                const SizedBox(height: 18),
                                if (error != null)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Text(error!,
                                          style: const TextStyle(
                                              color: Colors.red))),
                                Expanded(
                                    child: people.isEmpty
                                        ? const Center(
                                            child: Text(
                                                'No doctors yet. Add your first doctor.'))
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
                                                    child: Icon(
                                                        Icons.person_outline)),
                                                title: Text(person['name']
                                                        ?.toString() ??
                                                    ''),
                                                subtitle: Text(
                                                    '${person['clinical_role'] ?? 'doctor'} · ${person['mobile_number'] ?? ''}'),
                                                trailing: person[
                                                            'account_id'] ==
                                                        widget.user['id']
                                                    ? const Chip(
                                                        label: Text('Admin'))
                                                    : person['account_id'] ==
                                                            null
                                                        ? TextButton(
                                                            onPressed: () =>
                                                                add(person),
                                                            child: const Text(
                                                                'Create login'))
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

class _ClinicianDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? person;
  const _ClinicianDialog({required this.api, this.person});

  @override
  State<_ClinicianDialog> createState() => _ClinicianDialogState();
}

class _ClinicianDialogState extends State<_ClinicianDialog> {
  late final values = <String, dynamic>{
    'clinical_role': 'doctor',
    ...?widget.person,
  };
  bool saving = false;
  String? error;

  Future<void> save() async {
    if (saving) return;
    if ((values['username'] as String? ?? '').trim().isEmpty ||
        (values['password'] as String? ?? '').length < 8) {
      setState(() =>
          error = 'Enter a username and a password of at least 8 characters.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.request('POST', '/api/my-clinic/clinicians', values);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.person == null
            ? 'Add doctor'
            : 'Create login for ${widget.person!['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final field in {
            if (widget.person == null) ...{
              'name': 'Name',
              'mobile_number': 'Mobile number',
              'email': 'Email',
              'clinical_role': 'Clinical role',
            },
            'username': 'Username',
            'password': 'Password (at least 8 characters)',
          }.entries)
            TextFormField(
                initialValue: values[field.key]?.toString(),
                enabled: !saving,
                obscureText: field.key == 'password',
                decoration: InputDecoration(labelText: field.value),
                onChanged: (value) => values[field.key] = value),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
        ]),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: saving ? null : save, child: const Text('Save')),
        ],
      );
}
