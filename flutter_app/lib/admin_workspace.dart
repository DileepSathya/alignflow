import 'package:flutter/material.dart';
import 'api.dart';
import 'admin_page.dart';
import 'demo_style.dart';
import 'orders_page.dart';

class AdminWorkspace extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const AdminWorkspace({super.key, required this.api, required this.user, required this.onLogout});
  @override
  State<AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<AdminWorkspace> {
  String section = 'All orders';
  final sections = const ['All orders', 'Users', 'Performance'];
  final icons = const [Icons.receipt_long_outlined, Icons.people_outline, Icons.bar_chart_outlined];

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    Widget rail() => Container(width: 248, color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
          DemoBrandMark(size: 34),
          SizedBox(width: 10), Text('AlignFlow', style: TextStyle(fontFamily: 'Bricolage', fontSize: 19, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(height: 24),
        const DemoPanel(child: Padding(padding: EdgeInsets.all(12), child: Text('Admin',
          style: TextStyle(fontWeight: FontWeight.w600)))),
        const SizedBox(height: 24),
        for (var i = 0; i < sections.length; i++) Padding(
          padding: const EdgeInsets.only(bottom: 4), child: ListTile(
            leading: Icon(icons[i], color: section == sections[i] ? DemoStyle.accent : DemoStyle.muted),
            title: Text(sections[i]), selected: section == sections[i],
            selectedTileColor: DemoStyle.accentSoft,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onTap: () { setState(() => section = sections[i]);
              if (compact) Navigator.pop(context); })),
        const Spacer(), const Divider(),
        ListTile(leading: const CircleAvatar(radius: 17, backgroundColor: DemoStyle.accentSoft,
          child: Icon(Icons.person, color: DemoStyle.accent, size: 18)),
          title: Text(widget.user['name']?.toString() ?? 'Admin'), subtitle: const Text('Admin')),
        TextButton.icon(onPressed: () async { await widget.api.logout(); widget.onLogout(); },
          icon: const Icon(Icons.logout), label: const Text('Log out')),
      ]));
    return Scaffold(drawer: compact ? Drawer(child: rail()) : null,
      body: Row(children: [if (!compact) rail(), Expanded(child: Column(children: [
        if (compact) Builder(builder: (context) => AppBar(title: Text(section),
          leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer()))),
        Expanded(child: switch (section) {
          'Users' => AdminPage(api: widget.api, user: widget.user, onLogout: widget.onLogout, embedded: true),
          'Performance' => AdminPerformanceView(api: widget.api),
          _ => AdminOrdersView(api: widget.api),
        }),
      ]))]));
  }
}

class AdminOrdersView extends StatefulWidget {
  final Api api;
  const AdminOrdersView({super.key, required this.api});
  @override
  State<AdminOrdersView> createState() => _AdminOrdersViewState();
}

class _AdminOrdersViewState extends State<AdminOrdersView> {
  List<Map<String, dynamic>> orders = [];
  bool loading = true;
  String? error;
  final search = TextEditingController();
  @override
  void initState() { super.initState(); refresh(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
    try { final result = await widget.api.request('GET', Uri(path: '/api/orders', queryParameters: {
      'limit': '100', if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
    }).toString());
      if (mounted) setState(() => orders = (result['orders'] as List).cast<Map<String, dynamic>>());
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1180), child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 48), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const DemoPageHeading(title: 'All orders', subtitle: 'Every order across Marketing, Clinical CAD, Lab and QC, with its full details and current status.'),
          const SizedBox(height: 20),
          SizedBox(width: 360, child: TextField(controller: search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search orders'),
            onSubmitted: (_) => refresh())),
          const SizedBox(height: 20),
          if (error != null) Text(error!, style: const TextStyle(color: DemoStyle.danger)),
          Expanded(child: DemoPanel(child: loading ? const Center(child: CircularProgressIndicator())
            : orders.isEmpty ? const Center(child: Text('No orders yet.'))
            : ListView.separated(itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: DemoStyle.line),
              itemBuilder: (context, i) { final order = orders[i];
                return ListTile(title: Text(order['patient_name']?.toString() ?? ''),
                  subtitle: Text('${order['order_id']}  •  ${(order['clinic'] as Map?)?['name'] ?? ''}'),
                  trailing: DemoStatusPill(label: orderStatusLabel(order['status'])),
                  onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) =>
                    OrderDetailPage(api: widget.api, orderId: order['order_id'] as String, role: 'admin')));
                    refresh(); });
              }))),
        ]))));
}

class AdminPerformanceView extends StatefulWidget {
  final Api api;
  const AdminPerformanceView({super.key, required this.api});
  @override
  State<AdminPerformanceView> createState() => _AdminPerformanceViewState();
}

class _AdminPerformanceViewState extends State<AdminPerformanceView> {
  Map<String, dynamic>? data;
  String? error;
  int year = DateTime.now().year;
  int month = DateTime.now().month;
  int top = 5;
  String rankBy = 'Orders';
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try { final result = await widget.api.request('GET', '/api/performance?year=$year&month=$month');
      if (mounted) setState(() { data = result; error = null; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1180), child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 48), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const DemoPageHeading(title: 'Marketing team performance',
            subtitle: 'Orders submitted and clinics added by each Marketing team member.'),
          const SizedBox(height: 20),
          Wrap(spacing: 12, children: [
            SizedBox(width: 120, child: DropdownButtonFormField<int>(initialValue: year,
              decoration: const InputDecoration(labelText: 'Year'),
              items: List.generate(6, (i) => DateTime.now().year - i).map((y) =>
                DropdownMenuItem(value: y, child: Text('$y'))).toList(),
              onChanged: (v) { if (v != null) { year = v; refresh(); } })),
            SizedBox(width: 140, child: DropdownButtonFormField<int>(initialValue: month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: List.generate(12, (i) => i + 1).map((m) =>
                DropdownMenuItem(value: m, child: Text('$m'))).toList(),
              onChanged: (v) { if (v != null) { month = v; refresh(); } })),
            SizedBox(width: 120, child: DropdownButtonFormField<int>(initialValue: top,
              decoration: const InputDecoration(labelText: 'Show'),
              items: const [3, 5, 10, 1000].map((n) => DropdownMenuItem(
                value: n, child: Text(n == 1000 ? 'Everyone' : 'Top $n'))).toList(),
              onChanged: (v) { if (v != null) setState(() => top = v); })),
            SizedBox(width: 160, child: DropdownButtonFormField<String>(initialValue: rankBy,
              decoration: const InputDecoration(labelText: 'Rank by'),
              items: const ['Orders', 'Clinics'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) { if (v != null) setState(() => rankBy = v); })),
          ]),
          const SizedBox(height: 20),
          if (error != null) Text(error!, style: const TextStyle(color: DemoStyle.danger)),
          Expanded(child: data == null ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _stat('Orders submitted', '${data!['orders']}'),
                  _stat('Clinics added', '${data!['clinics']}'),
                  _stat('Cancelled orders', '${data!['cancelled']}'),
                ]),
                const SizedBox(height: 20),
                DemoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Padding(padding: EdgeInsets.all(16), child: Text('Top performers',
                    style: TextStyle(fontFamily: 'Bricolage', fontWeight: FontWeight.w700, fontSize: 16))),
                  const Divider(height: 1),
                  for (final row in _ranking()) ListTile(
                    title: Text(row['name']?.toString() ?? ''),
                    subtitle: Text('Clinics added: ${row['clinics']}'),
                    trailing: Text('${row['orders']} orders',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                ])),
                const SizedBox(height: 20),
                DemoPanel(child: Padding(padding: const EdgeInsets.all(16), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Month-wise dashboard', style: TextStyle(fontFamily: 'Bricolage',
                      fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 20),
                    for (final row in (data!['months'] as List)) Padding(
                      padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                        SizedBox(width: 30, child: Text('${row['month']}')),
                        Expanded(child: LinearProgressIndicator(
                          value: (row['orders'] as num).toDouble() / _maxMonth(),
                          minHeight: 12, borderRadius: BorderRadius.circular(3),
                          backgroundColor: DemoStyle.surface2, color: DemoStyle.accent)),
                        const SizedBox(width: 10),
                        SizedBox(width: 35, child: Text('${row['orders']}')),
                      ])),
                  ]))),
              ])),
        ]))));

  List<dynamic> _ranking() {
    final rows = List<dynamic>.from(data!['ranking'] as List);
    if (rankBy == 'Clinics') rows.sort((a, b) => (b['clinics'] as num).compareTo(a['clinics'] as num));
    return rows.take(top).toList();
  }

  double _maxMonth() {
    final counts = (data!['months'] as List).map((row) => (row['orders'] as num).toDouble());
    final max = counts.fold<double>(0, (a, b) => b > a ? b : a);
    return max == 0 ? 1 : max;
  }

  Widget _stat(String label, String value) => SizedBox(width: 190, child: DemoPanel(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontFamily: 'Bricolage', fontSize: 26, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(color: DemoStyle.muted)),
      ]))));
}
