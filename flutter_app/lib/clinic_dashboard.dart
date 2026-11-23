import 'package:flutter/material.dart';
import 'api.dart';
import 'orders_page.dart';
import 'demo_style.dart';

class ClinicDashboard extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> clinic, user;
  final VoidCallback onAddClinician;
  const ClinicDashboard(
      {super.key,
      required this.api,
      required this.clinic,
      required this.user,
      required this.onAddClinician});
  @override
  State<ClinicDashboard> createState() => _ClinicDashboardState();
}

class _ClinicDashboardState extends State<ClinicDashboard> {
  Map<String, dynamic>? data;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await widget.api.request('GET', '/api/my-clinic/overview');
      if (mounted) {
        setState(() {
          data = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> orders(String title, Map<String, String> filters) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Padding(
                padding: const EdgeInsets.all(20),
                child: OrdersPage(
                    api: widget.api,
                    clinics: [widget.clinic],
                    user: widget.user,
                    dashboardFilters: filters)))));
    refresh();
  }

  Future<void> open(Map row) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OrderDetailPage(
            api: widget.api,
            orderId: row['order_id'],
            role: widget.user['role'])));
    refresh();
  }

  String clinician(Object? id) {
    for (final p in widget.clinic['clinicians'] as List? ?? []) {
      if (p['clinician_id'] == id) return p['name'].toString();
    }
    return 'Unassigned clinician';
  }

  String age(Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '');
    if (time == null) return 'Unknown';
    final hours = DateTime.now().difference(time).inHours;
    return hours < 24 ? '${hours < 0 ? 0 : hours}h' : '${hours ~/ 24}d';
  }

  Widget queue(String title, List rows, String empty) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (rows.isEmpty) Text(empty),
            for (final row in rows)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row['patient_name']} · ${row['order_id']}'),
                  subtitle: Text(
                      '${clinician(row['clinician_id'])} · ${orderStatusLabel(row['status'])}\n'
                      '${row['revised'] == true && row['status'] == 'plan_completed' ? 'Revised plan · ' : ''}'
                      'In stage ${age(row['stage_since'])} · Updated ${age(row['updated_at'])} ago'
                      '${row['missing_request'] == null ? '' : '\n${(row['missing_request']['items'] as List? ?? []).join(', ')}\n${row['missing_request']['note'] ?? ''}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(row)),
          ])));
  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error!),
                  TextButton(onPressed: refresh, child: const Text('Retry'))
                ]));
    }
    final counts = data!['counts'] as Map;
    final months = (data!['months'] as List).cast<int>();
    final peak = months.fold<int>(1, (a, b) => a > b ? a : b);
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return ListView(children: [
      DemoPageHeading(
          title: 'Clinic dashboard',
          subtitle:
              '${widget.clinic['clinic_name']} · Your cases and next decisions'),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create order'),
            onPressed: () async {
              await showDialog<bool>(
                  context: context,
                  builder: (_) => CreateOrderDialog(
                      api: widget.api, clinics: [widget.clinic]));
              refresh();
            }),
        OutlinedButton(
            onPressed: widget.onAddClinician,
            child: const Text('Add clinician')),
        OutlinedButton(
            onPressed: () => orders('All orders', {}),
            child: const Text('View all orders')),
        IconButton(
            onPressed: refresh,
            tooltip: 'Refresh dashboard',
            icon: const Icon(Icons.refresh)),
      ]),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final item in [
          ('total', 'Total orders'),
          ('active', 'Active cases'),
          ('approval', 'Awaiting approval'),
          ('completed', 'Manufacturing completed')
        ])
          SizedBox(
              width: 220,
              child: Card(
                  child: InkWell(
                      onTap: () => orders(item.$2,
                          item.$1 == 'total' ? {} : {'status_group': item.$1}),
                      child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${counts[item.$1]}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium),
                                Text(item.$2)
                              ]))))),
      ]),
      const SizedBox(height: 16),
      queue('Needs your attention', data!['approvals'],
          'No plans awaiting approval.'),
      queue('Missing records · coordinate with Marketing', data!['missing'],
          'No missing-record requests.'),
      const SizedBox(height: 16),
      Text('Case progress', style: Theme.of(context).textTheme.titleLarge),
      Wrap(spacing: 8, children: [
        for (final item in [
          ('scanner', 'Document preparation'),
          ('planning', 'Planning'),
          ('approval', 'Awaiting approval'),
          ('revision', 'Revision'),
          ('manufacturing', 'Manufacturing'),
          ('qc', 'QC'),
          ('completed', 'Completed')
        ])
          ActionChip(
              label: Text('${item.$2} · ${counts[item.$1]}'),
              onPressed: () => orders(item.$2, {'status_group': item.$1})),
        ActionChip(
            label: Text('Cancelled · ${counts['cancelled']}'),
            onPressed: () =>
                orders('Cancelled', {'status_filter': 'cancelled'})),
      ]),
      queue('Recently updated cases', data!['recent'],
          'Create your first order to get started.'),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clinician overview',
                        style: Theme.of(context).textTheme.titleLarge),
                    for (final p in widget.clinic['clinicians'] as List? ?? [])
                      ListTile(
                          title: Text(p['name']),
                          subtitle: Text(
                              '${data!['clinicians']['${p['clinician_id']}']?['total'] ?? 0} total · '
                              '${data!['clinicians']['${p['clinician_id']}']?['active'] ?? 0} active · '
                              '${data!['clinicians']['${p['clinician_id']}']?['approval'] ?? 0} awaiting approval'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => orders(p['name'],
                              {'clinician_id': '${p['clinician_id']}'})),
                  ]))),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New orders · ${data!['year']}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text(
                        'All orders by creation month, including cancelled orders. UTC calendar.'),
                    for (var i = 0; i < 12; i++)
                      InkWell(
                          onTap: () => orders('${labels[i]} ${data!['year']}', {
                                'created_month':
                                    '${data!['year']}-${(i + 1).toString().padLeft(2, '0')}'
                              }),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(children: [
                                SizedBox(width: 40, child: Text(labels[i])),
                                Expanded(
                                    child: LinearProgressIndicator(
                                        value: months[i] / peak,
                                        minHeight: 10)),
                                SizedBox(
                                    width: 40,
                                    child: Text('${months[i]}',
                                        textAlign: TextAlign.right)),
                              ]))),
                  ]))),
    ]);
  }
}
