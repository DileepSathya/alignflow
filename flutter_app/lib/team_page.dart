import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';
import 'orders_page.dart';

const teamNames = {'cad': 'Clinical CAD', 'lab': 'Lab / Manufacturing', 'qc': 'QC'};
const teamDescriptions = {
  'cad': 'Review submitted cases, prepare plans and handle clinician feedback.',
  'lab': 'Orders approved by the clinic and assigned by the CAD team appear here.',
  'qc': 'Review manufactured orders and record quality decisions.',
};
class TeamPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const TeamPage({super.key, required this.api, required this.user, required this.onLogout});
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  List<Map<String, dynamic>> orders = [];
  bool loading = true;
  String? error;
  String filter = '';
  String query = '';
  final search = TextEditingController();
  String get role => widget.user['role'] as String;

  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await widget.api.request('GET', Uri(path: '/api/orders', queryParameters: {
        'limit': '100', if (filter.isNotEmpty) 'status_filter': filter,
        if (query.isNotEmpty) 'q': query,
      }).toString());
      if (mounted) setState(() => orders = (result['orders'] as List).cast<Map<String, dynamic>>());
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> openOrder(Map<String, dynamic> order) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailPage(
      api: widget.api, orderId: order['order_id'] as String, role: role)));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    final name = teamNames[role] ?? role;
    Widget rail() => Container(width: 248, color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
          DemoBrandMark(size: 34),
          SizedBox(width: 10), Text('AlignFlow', style: TextStyle(fontFamily: 'Bricolage', fontSize: 19, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 24),
        DemoPanel(child: Padding(padding: const EdgeInsets.all(12), child: Text(name,
          style: const TextStyle(fontWeight: FontWeight.w600)))),
        const SizedBox(height: 24),
        ListTile(leading: const Icon(Icons.receipt_long_outlined, color: DemoStyle.accent),
          title: const Text('Orders'), selected: true, selectedTileColor: DemoStyle.accentSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        const Spacer(), const Divider(),
        ListTile(leading: const CircleAvatar(radius: 17, backgroundColor: DemoStyle.accentSoft,
          child: Icon(Icons.person, color: DemoStyle.accent, size: 18)),
          title: Text(widget.user['name']?.toString() ?? ''), subtitle: Text(name)),
        TextButton.icon(onPressed: () async { await widget.api.logout(); widget.onLogout(); },
          icon: const Icon(Icons.logout), label: const Text('Log out')),
      ]));
    final content = Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180),
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 28, 16, 48), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DemoPageHeading(title: 'Orders', subtitle: teamDescriptions[role] ?? ''),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: 320, child: TextField(controller: search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search orders'),
              onSubmitted: (value) { query = value.trim(); refresh(); })),
            SizedBox(width: 220, child: DropdownButtonFormField<String>(initialValue: filter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'submitted', child: Text('Submitted')),
                DropdownMenuItem(value: 'plan_completed', child: Text('Plan completed')),
                DropdownMenuItem(value: 'clinician_approved', child: Text('Clinician approved')),
                DropdownMenuItem(value: 'manufactured', child: Text('Sent to QC')),
                DropdownMenuItem(value: 'qc_approved', child: Text('QC approved'))],
              onChanged: (value) { filter = value ?? ''; refresh(); })),
          ]),
          const SizedBox(height: 20),
          if (error != null) Text(error!, style: const TextStyle(color: DemoStyle.danger)),
          Expanded(child: DemoPanel(child: loading
            ? const Center(child: CircularProgressIndicator())
            : orders.isEmpty ? const Center(child: Text('No matching orders.'))
            : ListView.separated(itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: DemoStyle.line),
              itemBuilder: (_, i) { final order = orders[i];
                return ListTile(onTap: () => openOrder(order),
                  title: Text(order['patient_name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${order['order_id']}  •  ${(order['clinic'] as Map?)?['name'] ?? ''}'),
                  trailing: DemoStatusPill(label: order['status']?.toString().replaceAll('_', ' ') ?? ''));
              }))),
        ]))));
    return Scaffold(
      drawer: compact ? Drawer(child: rail()) : null,
      body: Row(children: [if (!compact) rail(), Expanded(child: Column(children: [
        if (compact) Builder(builder: (context) => AppBar(title: const Text('Orders'),
          leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer()))),
        Expanded(child: content),
      ]))]));
  }
}
