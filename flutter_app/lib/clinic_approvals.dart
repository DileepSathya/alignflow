import 'package:flutter/material.dart';
import 'api.dart';

class ClinicApprovals extends StatefulWidget {
  final Api api;
  const ClinicApprovals({super.key, required this.api});
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
      final result =
          await widget.api.request('GET', '/api/admin/clinic-approvals');
      if (mounted)
        setState(() {
          clinics = result['clinics'] as List;
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

  @override
  Widget build(BuildContext context) => ListView(children: [
        if (error != null) ListTile(title: Text(error!)),
        for (final item in clinics)
          Card(
              child: ListTile(
                  title: Text(item['clinic_name'].toString()),
                  subtitle: Text(
                      '${item['area']} · ${item['email']} · ${item['contact_number']}\nAdmin: ${item['admin_name']} (${item['admin_username']}) · ${item['approval_status']}'),
                  isThreeLine: true,
                  trailing: item['approval_status'] == 'pending'
                      ? Wrap(children: [
                          TextButton(
                              onPressed: () => decide(item['id'] as int, false),
                              child: const Text('Reject')),
                          FilledButton(
                              onPressed: () => decide(item['id'] as int, true),
                              child: const Text('Approve')),
                        ])
                      : null)),
      ]);
}
