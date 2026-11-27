import 'package:flutter/material.dart';
import 'api.dart';
import 'marketing_page.dart';

class ClinicApprovals extends StatefulWidget {
  final Api api;
  final void Function(int id, String name)? onOrders;
  const ClinicApprovals({super.key, required this.api, this.onOrders});
  @override
  State<ClinicApprovals> createState() => _ClinicApprovalsState();
}

class _ClinicApprovalsState extends State<ClinicApprovals> {
  List clinics = [];
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await widget.api.request('GET', '/api/clinics');
      if (mounted)
        setState(() {
          clinics = (result['clinics'] as List)
            ..sort((a, b) {
              final aPending = a['approval_status'] == 'pending' ? 0 : 1;
              final bPending = b['approval_status'] == 'pending' ? 0 : 1;
              return aPending.compareTo(bPending);
            });
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> decide(int id, bool approved) async {
    String? reason;
    if (!approved) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Reject clinic'),
                  content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: 'Reason')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Reject'))
                  ]));
      reason = controller.text.trim();
      controller.dispose();
      if (confirmed != true || reason.isEmpty) return;
    }
    try {
      await widget.api.request('POST', '/api/admin/clinic-approvals/$id',
          {'approved': approved, if (reason != null) 'reason': reason});
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> viewClinic(int id) async {
    try {
      final clinic = await widget.api.request('GET', '/api/admin/clinics/$id');
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(clinic['clinic_name'].toString()),
                content: SizedBox(
                  width: 500,
                  child: ListView(shrinkWrap: true, children: [
                    for (final field in {
                      'Clinic name': clinic['clinic_name'],
                      'Contact number': clinic['contact_number'],
                      'Clinic email': clinic['email'],
                      'Area': clinic['area'],
                    }.entries)
                      ListTile(
                          title: Text(field.key),
                          subtitle: Text('${field.value ?? ''}')),
                    for (final person in clinic['clinicians'] as List) ...[
                      const Divider(),
                      for (final field in {
                        'Doctor name': person['name'],
                        'Doctor mobile': person['mobile_number'],
                        'Doctor email': person['email'],
                        'Clinical role': person['clinical_role'],
                        'Username': person['username'],
                      }.entries)
                        ListTile(
                            title: Text(field.key),
                            subtitle: Text('${field.value ?? ''}')),
                    ],
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ],
              ));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ListView(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                    onPressed: () async {
                      final saved = await showDialog<bool>(
                          context: context,
                          builder: (_) => ClinicDialog(api: widget.api));
                      if (saved == true) refresh();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add clinic')))),
        if (error != null) ListTile(title: Text(error!)),
        for (final item in clinics)
          Card(
              child: ListTile(
                  onTap: () => viewClinic(item['id'] as int),
                  title: Text(item['clinic_name'].toString()),
                  subtitle: Text(
                      '${item['area']} · ${item['email']} · ${item['contact_number']}\n${item['approval_status'] ?? 'approved'}'),
                  isThreeLine: true,
                  trailing: item['signup_source'] == 'self' &&
                          item['approval_status'] == 'pending'
                      ? Wrap(children: [
                          TextButton(
                              onPressed: () => decide(item['id'] as int, false),
                              child: const Text('Reject')),
                          FilledButton(
                              onPressed: () => decide(item['id'] as int, true),
                              child: const Text('Approve')),
                        ])
                      : widget.onOrders == null
                          ? null
                          : TextButton(
                              onPressed: () => widget.onOrders!(
                                  item['id'] as int,
                                  item['clinic_name'].toString()),
                              child: const Text('View orders'),
                            ))),
      ]);
}
