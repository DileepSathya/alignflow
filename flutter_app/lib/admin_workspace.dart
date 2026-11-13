import 'package:flutter/material.dart';
import 'api.dart';
import 'admin_page.dart';
import 'demo_style.dart';
import 'orders_page.dart';

class AdminWorkspace extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const AdminWorkspace(
      {super.key,
      required this.api,
      required this.user,
      required this.onLogout});
  @override
  State<AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<AdminWorkspace> {
  String section = 'All orders';
  int orderCount = 0, userCount = 0;
  final sections = const ['All orders', 'Users', 'Performance'];
  final icons = const [
    Icons.receipt_long_outlined,
    Icons.people_outline,
    Icons.bar_chart_outlined
  ];

  Future<void> refreshCounts() async {
    try {
      final data = await widget.api.request('GET', '/api/admin/overview');
      if (mounted) {
        setState(() {
          orderCount = data['total_orders'] as int;
          userCount = data['users'] as int;
        });
      }
    } catch (_) {/* The page shows its own loading error. */}
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    Widget rail() => Container(
        width: compact ? 248 : 190,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                DemoBrandMark(size: 34),
                SizedBox(width: 10),
                Text('AlignFlow',
                    style: TextStyle(
                        fontFamily: 'Bricolage',
                        fontSize: 19,
                        fontWeight: FontWeight.w700)),
              ])),
          const SizedBox(height: 24),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: DemoStyle.accentSoft,
                  border: Border.all(color: DemoStyle.line),
                  borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFBCE2DE),
                    child:
                        Text('A', style: TextStyle(color: DemoStyle.accent))),
                SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Admin',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Administrator',
                          style:
                              TextStyle(fontSize: 11, color: DemoStyle.muted)),
                    ]))
              ])),
          const SizedBox(height: 24),
          for (var i = 0; i < sections.length; i++)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                    leading: Icon(icons[i],
                        color: section == sections[i]
                            ? DemoStyle.accent
                            : DemoStyle.muted),
                    title:
                        Text(sections[i], style: const TextStyle(fontSize: 13)),
                    selected: section == sections[i],
                    trailing: i < 2
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: section == sections[i]
                                    ? const Color(0xFFBCE2DE)
                                    : DemoStyle.surface2,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text('${i == 0 ? orderCount : userCount}',
                                style: const TextStyle(fontSize: 11)))
                        : null,
                    selectedTileColor: DemoStyle.accentSoft,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                            color: section == sections[i]
                                ? DemoStyle.accent
                                : Colors.transparent)),
                    onTap: () {
                      setState(() => section = sections[i]);
                      if (compact) {
                        Navigator.pop(context);
                      }
                    })),
          const Spacer(),
          const Divider(),
          OutlinedButton(
              onPressed: () async {
                await widget.api.logout();
                widget.onLogout();
              },
              child: const Text('Log out')),
        ]));
    return Scaffold(
        drawer: compact ? Drawer(child: rail()) : null,
        body: Row(children: [
          if (!compact) rail(),
          Expanded(
              child: Column(children: [
            if (compact)
              Builder(
                  builder: (context) => AppBar(
                      title: Text(section),
                      leading: IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => Scaffold.of(context).openDrawer()))),
            Expanded(
                child: switch (section) {
              'Users' => AdminPage(
                  api: widget.api,
                  user: widget.user,
                  onLogout: widget.onLogout,
                  embedded: true,
                  onUsersChanged: refreshCounts),
              'Performance' => AdminPerformanceView(api: widget.api),
              _ => AdminOrdersView(
                  api: widget.api,
                  onOverviewChanged: (data) {
                    if (mounted) {
                      setState(() {
                        orderCount = data['total_orders'] as int;
                        userCount = data['users'] as int;
                      });
                    }
                  }),
            }),
          ]))
        ]));
  }
}

class AdminOrdersView extends StatefulWidget {
  final Api api;
  final ValueChanged<Map<String, dynamic>>? onOverviewChanged;
  const AdminOrdersView({super.key, required this.api, this.onOverviewChanged});
  @override
  State<AdminOrdersView> createState() => _AdminOrdersViewState();
}

class _AdminOrdersViewState extends State<AdminOrdersView> {
  List<Map<String, dynamic>> orders = [];
  Map<String, dynamic> overview = {};
  bool loading = true;
  String? error;
  final search = TextEditingController();
  String status = '';
  int page = 1, total = 0;
  @override
  void initState() {
    super.initState();
    refreshOverview();
    refresh();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> refreshOverview() async {
    try {
      final data = await widget.api.request('GET', '/api/admin/overview');
      if (mounted) {
        setState(() => overview = data);
        widget.onOverviewChanged?.call(data);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
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
            'page': '$page',
            'limit': '25',
            if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
            if (status.isNotEmpty) 'status_filter': status,
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
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => OrderDetailPage(
                api: widget.api,
                orderId: order['order_id'] as String,
                role: 'admin')));
    refresh();
    refreshOverview();
  }

  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const DemoPageHeading(
                        title: 'All orders',
                        subtitle:
                            'Every order across Marketing, Clinical CAD, Lab and QC, with its full details and current status.'),
                    const SizedBox(height: 20),
                    SizedBox(
                        height: 82,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _AdminStat('${overview['total_orders'] ?? '—'}',
                                  'Total orders'),
                              _AdminStat(
                                  '${overview['in_plan'] ?? '—'}', 'In plan'),
                              _AdminStat(
                                  '${overview['in_manufacturing'] ?? '—'}',
                                  'In manufacturing'),
                              _AdminStat(
                                  '${overview['in_qc'] ?? '—'}', 'In QC'),
                              _AdminStat('${overview['completed'] ?? '—'}',
                                  'Completed'),
                              _AdminStat('${overview['cancelled'] ?? '—'}',
                                  'Cancelled'),
                              _AdminStat('${overview['open_issues'] ?? '—'}',
                                  'Open issues'),
                            ])),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: search,
                              decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText:
                                      'Search order ID, patient, clinic or dentist',
                                  suffixIcon: IconButton(
                                      tooltip: 'Search',
                                      icon: const Icon(Icons.arrow_forward),
                                      onPressed: () {
                                        page = 1;
                                        refresh();
                                      })),
                              onSubmitted: (_) {
                                page = 1;
                                refresh();
                              })),
                      const SizedBox(width: 12),
                      SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                              initialValue: status,
                              isExpanded: true,
                              decoration: const InputDecoration(),
                              items: const [
                                DropdownMenuItem(
                                    value: '', child: Text('All statuses')),
                                DropdownMenuItem(
                                    value: 'submitted',
                                    child: Text('Submitted')),
                                DropdownMenuItem(
                                    value: 'plan_completed',
                                    child: Text('Plan pending')),
                                DropdownMenuItem(
                                    value: 'clinician_issues',
                                    child: Text('Clinical issues')),
                                DropdownMenuItem(
                                    value: 'clinician_approved',
                                    child: Text('Clinician approved')),
                                DropdownMenuItem(
                                    value: 'manufactured',
                                    child: Text('Manufactured')),
                                DropdownMenuItem(
                                    value: 'manufacturing_in_process',
                                    child: Text('Manufacturing in process')),
                                DropdownMenuItem(
                                    value: 'qc_issues',
                                    child: Text('QC issues')),
                                DropdownMenuItem(
                                    value: 'qc_approved',
                                    child: Text('Completed')),
                                DropdownMenuItem(
                                    value: 'cancelled',
                                    child: Text('Cancelled')),
                              ],
                              onChanged: (value) {
                                status = value ?? '';
                                page = 1;
                                refresh();
                              }))
                    ]),
                    const SizedBox(height: 16),
                    if (error != null)
                      Text(error!,
                          style: const TextStyle(color: DemoStyle.danger)),
                    Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : orders.isEmpty
                                ? const Center(child: Text('No orders yet.'))
                                : Align(
                                    alignment: Alignment.topCenter,
                                    child: SingleChildScrollView(
                                        child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: SizedBox(
                                                width: 1190,
                                                child: DemoPanel(
                                                    child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                      Container(
                                                          color: DemoStyle
                                                              .surface2,
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(12),
                                                          child:
                                                              const _AdminOrderRow(
                                                                  header:
                                                                      true)),
                                                      for (final order
                                                          in orders) ...[
                                                        const Divider(
                                                            height: 1,
                                                            color:
                                                                DemoStyle.line),
                                                        InkWell(
                                                            onTap: () =>
                                                                openOrder(
                                                                    order),
                                                            child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .all(
                                                                        12),
                                                                child: _AdminOrderRow(
                                                                    order:
                                                                        order,
                                                                    onView: () =>
                                                                        openOrder(
                                                                            order)))),
                                                      ],
                                                    ]))))))),
                    if (total > 25)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('$total orders  •  page $page'),
                        IconButton(
                            onPressed: page > 1
                                ? () {
                                    page--;
                                    refresh();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left)),
                        IconButton(
                            onPressed: page * 25 < total
                                ? () {
                                    page++;
                                    refresh();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_right)),
                      ]),
                  ]))));
}

class _AdminStat extends StatelessWidget {
  final String value, label;
  const _AdminStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
          width: 151,
          child: DemoPanel(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value,
                            style: const TextStyle(
                                fontSize: 23, fontWeight: FontWeight.w700)),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: DemoStyle.muted)),
                      ])))));
}

class _AdminOrderRow extends StatelessWidget {
  final bool header;
  final Map<String, dynamic>? order;
  final VoidCallback? onView;
  const _AdminOrderRow({this.header = false, this.order, this.onView});
  @override
  Widget build(BuildContext context) {
    Widget cell(String heading, String value, int flex,
            {String? sub, bool bold = false, bool mono = false}) =>
        Expanded(
            flex: flex,
            child: header
                ? _label(heading)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text(value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: mono ? 'monospace' : null,
                                fontSize: 12,
                                fontWeight: bold
                                    ? FontWeight.w700
                                    : FontWeight.normal)),
                        if (sub != null)
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: DemoStyle.muted)),
                      ]));
    final data = order ?? {};
    final clinic = (data['clinic'] as Map?) ?? {};
    final status = data['status']?.toString() ?? '';
    final date =
        DateTime.tryParse(data['created_at']?.toString() ?? '')?.toLocal();
    final dateText = date == null
        ? ''
        : '${date.day} ${_months[date.month - 1]} ${date.year}';
    final age = data['age'];
    final issues = (data['issues'] as List?)?.length ?? 0;
    return Row(children: [
      cell('ORDER ID', '${data['order_id'] ?? ''}', 13,
          sub: dateText, mono: true),
      cell('PATIENT', '${data['patient_name'] ?? ''}', 14,
          sub: age == null ? null : '$age yrs', bold: true),
      cell('CLINIC', '${clinic['name'] ?? ''}', 14,
          sub: clinic['dentist']?.toString()),
      _stage('CURRENT STATUS', header ? '' : _currentStatusLabel(status), 17,
          tone: _statusTone(status)),
      _stage('PLAN', header ? '' : _planLabel(data), 11, tone: _planTone(data)),
      _stage('MANUFACTURING', header ? '' : _manufacturingLabel(data), 13,
          tone: _manufacturingTone(data)),
      _stage('QC', header ? '' : _qcLabel(data), 11, tone: _qcTone(data)),
      cell('ISSUES', issues == 0 ? 'None' : '$issues raised', 9),
      SizedBox(
          width: 70,
          child: header
              ? Align(
                  alignment: Alignment.centerRight, child: _label('DETAILS'))
              : Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                      onPressed: onView,
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10)),
                      child: const Text('View')))),
    ]);
  }

  static const _months = [
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
  static Widget _label(String value) => Text(value,
      style: const TextStyle(
          fontSize: 10,
          letterSpacing: .7,
          fontWeight: FontWeight.w700,
          color: DemoStyle.muted));
  Widget _stage(String heading, String value, int flex,
          {required String tone}) =>
      Expanded(
          flex: flex,
          child: header
              ? _label(heading)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: _StagePill(value, tone)));
  static bool _reached(Map<String, dynamic> order, String step) =>
      ((order['history'] as List?) ?? [])
          .any((entry) => entry is Map && entry['status'] == step);
  static String _statusTone(String status) => status == 'cancelled'
      ? 'red'
      : {'qc_approved', 'manufacture_completed'}.contains(status)
          ? 'green'
          : 'blue';
  static String _currentStatusLabel(String status) => switch (status) {
        'plan_completed' => 'Plan pending',
        'qc_approved' || 'manufacture_completed' => 'Manufacture completed',
        _ => orderStatusLabel(status),
      };
  static String _planLabel(Map<String, dynamic> order) {
    if (order['status'] == 'cancelled') return 'Cancelled';
    if (_planApproved(order)) return 'Approved';
    return 'Pending';
  }

  static bool _planApproved(Map<String, dynamic> order) =>
      _reached(order, 'clinician_approved') ||
      {
        'clinician_approved',
        'manufacturing_in_process',
        'manufactured',
        'qc_issues',
        'qc_approved',
        'manufacture_completed'
      }.contains(order['status']);

  static String _planTone(Map<String, dynamic> order) =>
      order['status'] == 'cancelled'
          ? 'red'
          : _planApproved(order)
              ? 'green'
              : 'grey';
  static String _manufacturingLabel(Map<String, dynamic> order) =>
      _reached(order, 'manufactured') ||
              {'qc_approved', 'manufacture_completed'}.contains(order['status'])
          ? 'Completed'
          : {'clinician_approved', 'manufacturing_in_process'}.contains(order['status'])
              ? 'Pending'
              : 'Not started';
  static String _manufacturingTone(Map<String, dynamic> order) =>
      _manufacturingLabel(order) == 'Completed' ? 'green' : 'grey';
  static String _qcLabel(Map<String, dynamic> order) =>
      {'qc_approved', 'manufacture_completed'}.contains(order['status'])
          ? 'Approved'
          : {'manufactured', 'qc_issues'}.contains(order['status'])
              ? 'Pending'
              : 'Not started';
  static String _qcTone(Map<String, dynamic> order) =>
      _qcLabel(order) == 'Approved' ? 'green' : 'grey';
}

class _StagePill extends StatelessWidget {
  final String label, tone;
  const _StagePill(this.label, this.tone);
  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      'green' => const Color(0xFF1B7F4B),
      'red' => const Color(0xFFB3261E),
      'blue' => const Color(0xFF235D9E),
      _ => DemoStyle.muted,
    };
    final background = switch (tone) {
      'green' => const Color(0xFFDCF2E5),
      'red' => const Color(0xFFFCE4E2),
      'blue' => const Color(0xFFDCE9F8),
      _ => DemoStyle.surface2,
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)));
  }
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
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await widget.api
          .request('GET', '/api/performance?year=$year&month=$month');
      if (mounted)
        setState(() {
          data = result;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 48),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const DemoPageHeading(
                        title: 'Marketing team performance',
                        subtitle:
                            'Orders submitted and clinics added by each Marketing team member.'),
                    const SizedBox(height: 20),
                    Wrap(spacing: 12, children: [
                      SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<int>(
                              initialValue: year,
                              decoration:
                                  const InputDecoration(labelText: 'Year'),
                              items: List.generate(
                                      6, (i) => DateTime.now().year - i)
                                  .map((y) => DropdownMenuItem(
                                      value: y, child: Text('$y')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  year = v;
                                  refresh();
                                }
                              })),
                      SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<int>(
                              initialValue: month,
                              decoration:
                                  const InputDecoration(labelText: 'Month'),
                              items: List.generate(12, (i) => i + 1)
                                  .map((m) => DropdownMenuItem(
                                      value: m, child: Text('$m')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  month = v;
                                  refresh();
                                }
                              })),
                      SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<int>(
                              initialValue: top,
                              decoration:
                                  const InputDecoration(labelText: 'Show'),
                              items: const [3, 5, 10, 1000]
                                  .map((n) => DropdownMenuItem(
                                      value: n,
                                      child: Text(
                                          n == 1000 ? 'Everyone' : 'Top $n')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => top = v);
                              })),
                      SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                              initialValue: rankBy,
                              decoration:
                                  const InputDecoration(labelText: 'Rank by'),
                              items: const ['Orders', 'Clinics']
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => rankBy = v);
                              })),
                    ]),
                    const SizedBox(height: 20),
                    if (error != null)
                      Text(error!,
                          style: const TextStyle(color: DemoStyle.danger)),
                    Expanded(
                        child: data == null
                            ? const Center(child: CircularProgressIndicator())
                            : ListView(children: [
                                Wrap(spacing: 12, runSpacing: 12, children: [
                                  _stat(
                                      'Orders submitted', '${data!['orders']}'),
                                  _stat('Clinics added', '${data!['clinics']}'),
                                  _stat('Cancelled orders',
                                      '${data!['cancelled']}'),
                                ]),
                                const SizedBox(height: 20),
                                DemoPanel(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                      const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Text('Top performers',
                                              style: TextStyle(
                                                  fontFamily: 'Bricolage',
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16))),
                                      const Divider(height: 1),
                                      for (final row in _ranking())
                                        ListTile(
                                            title: Text(
                                                row['name']?.toString() ?? ''),
                                            subtitle: Text(
                                                'Clinics added: ${row['clinics']}'),
                                            trailing: Text(
                                                '${row['orders']} orders',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700))),
                                    ])),
                                const SizedBox(height: 20),
                                DemoPanel(
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text('Month-wise dashboard',
                                                  style: TextStyle(
                                                      fontFamily: 'Bricolage',
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 16)),
                                              const SizedBox(height: 20),
                                              for (final row
                                                  in (data!['months'] as List))
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 8),
                                                    child: Row(children: [
                                                      SizedBox(
                                                          width: 30,
                                                          child: Text(
                                                              '${row['month']}')),
                                                      Expanded(
                                                          child: LinearProgressIndicator(
                                                              value: (row['orders']
                                                                          as num)
                                                                      .toDouble() /
                                                                  _maxMonth(),
                                                              minHeight: 12,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          3),
                                                              backgroundColor:
                                                                  DemoStyle
                                                                      .surface2,
                                                              color: DemoStyle
                                                                  .accent)),
                                                      const SizedBox(width: 10),
                                                      SizedBox(
                                                          width: 35,
                                                          child: Text(
                                                              '${row['orders']}')),
                                                    ])),
                                            ]))),
                              ])),
                  ]))));

  List<dynamic> _ranking() {
    final rows = List<dynamic>.from(data!['ranking'] as List);
    if (rankBy == 'Clinics')
      rows.sort((a, b) => (b['clinics'] as num).compareTo(a['clinics'] as num));
    return rows.take(top).toList();
  }

  double _maxMonth() {
    final counts = (data!['months'] as List)
        .map((row) => (row['orders'] as num).toDouble());
    final max = counts.fold<double>(0, (a, b) => b > a ? b : a);
    return max == 0 ? 1 : max;
  }

  Widget _stat(String label, String value) => SizedBox(
      width: 190,
      child: DemoPanel(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontFamily: 'Bricolage',
                            fontSize: 26,
                            fontWeight: FontWeight.w700)),
                    Text(label, style: const TextStyle(color: DemoStyle.muted)),
                  ]))));
}
