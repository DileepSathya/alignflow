import 'branding.dart';
import 'role_shell.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';
import 'orders_page.dart';
import 'app_router.dart';

const teamNames = {
  'scanner': 'Scanner team',
  'planning': 'Planning team',
  'production': 'Production team'
};
const teamDescriptions = {
  'scanner':
      'Upload missing documents, verify the checklist and approve orders for Planning.',
  'planning':
      'Review submitted cases, prepare plans and handle clinician feedback.',
  'production':
      'Orders approved by the clinic and assigned by the Planning team appear here.',
};

class TeamPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const TeamPage(
      {super.key,
      required this.api,
      required this.user,
      required this.onLogout});
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  List<Map<String, dynamic>> orders = [];
  bool loading = true;
  String? error;
  String filter = '';
  String query = '';
  int page = 1;
  int total = 0;
  final search = TextEditingController();
  String get role => widget.user['role'] as String;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.request(
          'GET',
          Uri(path: '/api/orders', queryParameters: {
            'limit': '25',
            'page': '$page',
            if (filter.isNotEmpty &&
                !['scanner_approved', 'scanner_missing'].contains(filter))
              'status_filter': filter,
            if (filter == 'scanner_approved') 'scanner_approved': 'true',
            if (filter == 'scanner_missing') 'scanner_missing': 'true',
            if (query.isNotEmpty) 'q': query,
          }).toString());
      if (mounted) {
        setState(() {
          orders = (result['orders'] as List).cast<Map<String, dynamic>>();
          total = result['total'] as int;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openOrder(Map<String, dynamic> order) async {
    await AppRouter.of(context).openOrder(order['order_id'] as String);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final name = teamNames[role] ?? role;
    Widget rail() => Container(
        width: MediaQuery.sizeOf(context).width <= 900
            ? null
            : RoleShell.navigationWidth,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: BrandLogo()),
          const SizedBox(height: 24),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: DemoStyle.accentSoft,
                  border: Border.all(color: DemoStyle.line),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFBCE2DE),
                    child: Text(
                        (widget.user['username']?.toString() ?? 'S')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(color: DemoStyle.accent))),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.user['username']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(name,
                          style: const TextStyle(
                              fontSize: 11, color: DemoStyle.muted)),
                    ])),
              ])),
          const SizedBox(height: 24),
          ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long_outlined,
                  size: 19, color: DemoStyle.accent),
              title: const Text('Orders',
                  style: TextStyle(fontSize: 13, color: DemoStyle.accent)),
              selected: true,
              selectedTileColor: DemoStyle.accentSoft,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: DemoStyle.accent))),
          const Spacer(),
          const Divider(),
          OutlinedButton(
              onPressed: () async {
                await widget.api.logout();
                widget.onLogout();
              },
              child: const Text('Log out')),
        ]));
    final content = Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: RoleShell.contentWidth),
            child: Padding(
                padding: RoleShell.pagePadding,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DemoPageHeading(
                          title: 'Orders',
                          subtitle: teamDescriptions[role] ?? ''),
                      const SizedBox(height: 20),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        SizedBox(
                            width: 320,
                            child: TextField(
                                controller: search,
                                decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    hintText: 'Search orders'),
                                onSubmitted: (value) {
                                  query = value.trim();
                                  page = 1;
                                  refresh();
                                })),
                        SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: filter,
                                decoration:
                                    const InputDecoration(labelText: 'Status'),
                                items: role == 'scanner'
                                    ? const [
                                        DropdownMenuItem(
                                            value: '',
                                            child: Text('All orders')),
                                        DropdownMenuItem(
                                            value: 'scanner_review',
                                            child: Text('Pending review')),
                                        DropdownMenuItem(
                                            value: 'scanner_missing',
                                            child: Text(
                                                'Missing / unverified items')),
                                        DropdownMenuItem(
                                            value: 'scanner_approved',
                                            child: Text('Approved')),
                                      ]
                                    : const [
                                        DropdownMenuItem(
                                            value: '',
                                            child: Text('All statuses')),
                                        DropdownMenuItem(
                                            value: 'submitted',
                                            child: Text('Submitted')),
                                        DropdownMenuItem(
                                            value: 'plan_completed',
                                            child: Text('Plan completed')),
                                        DropdownMenuItem(
                                            value: 'clinician_approved',
                                            child: Text('Clinician approved')),
                                        DropdownMenuItem(
                                            value: 'manufactured',
                                            child: Text('QC approval pending')),
                                        DropdownMenuItem(
                                            value: 'qc_issues',
                                            child: Text('QC raised issue')),
                                        DropdownMenuItem(
                                            value: 'qc_approved',
                                            child: Text('QC approved'))
                                      ],
                                onChanged: (value) {
                                  filter = value ?? '';
                                  page = 1;
                                  refresh();
                                })),
                      ]),
                      const SizedBox(height: 20),
                      if (error != null)
                        Text(error!,
                            style: const TextStyle(color: DemoStyle.danger)),
                      Expanded(
                          child: DemoPanel(
                              child: loading
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : orders.isEmpty
                                      ? const Center(
                                          child: Text('No matching orders.'))
                                      : ListView.separated(
                                          itemCount: orders.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(
                                                  height: 1,
                                                  color: DemoStyle.line),
                                          itemBuilder: (_, i) {
                                            final order = orders[i];
                                            return ListTile(
                                                onTap: () => openOrder(order),
                                                title: Text(
                                                    order['patient_name']
                                                            ?.toString() ??
                                                        '',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                subtitle: Text(
                                                    '${order['order_id']}  •  ${(order['clinic'] as Map?)?['name'] ?? ''}'),
                                                trailing: DemoStatusPill(
                                                    label: orderStatusLabel(
                                                        order['status'])));
                                          }))),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('$total orders • Page $page'),
                        IconButton(
                            tooltip: 'Previous page',
                            onPressed: loading || page == 1
                                ? null
                                : () {
                                    page--;
                                    refresh();
                                  },
                            icon: const Icon(Icons.chevron_left)),
                        IconButton(
                            tooltip: 'Next page',
                            onPressed: loading || page * 25 >= total
                                ? null
                                : () {
                                    page++;
                                    refresh();
                                  },
                            icon: const Icon(Icons.chevron_right)),
                      ]),
                    ]))));
    return RoleShell(sidebar: rail(), title: 'Orders', content: content);
  }
}
