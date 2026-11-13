import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';
import 'orders_page.dart';

const _labTabs = <(String, String)>[
  ('', 'All orders'),
  ('manufacturing_not_started', 'Manufacturing not started'),
  ('manufacturing_in_process', 'Manufacturing in process'),
  ('qc_approval_pending', 'QC approval pending'),
  ('qc_issue_raised', 'QC issue raised'),
  ('manufacturing_completed', 'Manufacturing completed'),
];

class LabOrdersPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const LabOrdersPage(
      {super.key,
      required this.api,
      required this.user,
      required this.onLogout});

  @override
  State<LabOrdersPage> createState() => _LabOrdersPageState();
}

class _LabOrdersPageState extends State<LabOrdersPage> {
  final search = TextEditingController();
  List<Map<String, dynamic>> orders = [];
  Map<String, dynamic> overview = {};
  String group = '', query = '';
  int? clinicId;
  int page = 1, total = 0;
  bool loading = true;
  String? error;

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
      final data = await widget.api.request('GET', '/api/lab/overview');
      if (mounted) setState(() => overview = data);
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
            if (group.isNotEmpty) 'status_group': group,
            if (query.isNotEmpty) 'q': query,
            if (clinicId != null) 'clinic_id': '$clinicId',
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
                role: 'lab')));
    refreshOverview();
    refresh();
  }

  Widget rail(bool compact) => Container(
      width: compact ? null : 190,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            ])),
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
                      (widget.user['username']?.toString() ?? 'M')
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
                    const Text('Lab & Manufacturing team',
                        style: TextStyle(fontSize: 11, color: DemoStyle.muted)),
                  ]))
            ])),
        const SizedBox(height: 24),
        ListTile(
            dense: true,
            selected: true,
            selectedTileColor: DemoStyle.accentSoft,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: DemoStyle.accent)),
            leading: const Icon(Icons.receipt_long_outlined,
                size: 19, color: DemoStyle.accent),
            title: const Text('Orders',
                style: TextStyle(fontSize: 13, color: DemoStyle.accent)),
            trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFFBCE2DE),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${overview['all_orders'] ?? '—'}',
                    style: const TextStyle(fontSize: 11)))),
        const Spacer(),
        const Divider(),
        OutlinedButton(
            onPressed: () async {
              await widget.api.logout();
              widget.onLogout();
            },
            child: const Text('Log out')),
      ]));

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 900;
    final clinics = (overview['clinics'] as List?) ?? [];
    return Scaffold(
        drawer: compact ? Drawer(child: rail(true)) : null,
        body: Row(children: [
          if (!compact) rail(false),
          Expanded(
              child: Column(children: [
            if (compact)
              Builder(
                  builder: (context) => AppBar(
                      title: const Text('Orders'),
                      leading: IconButton(
                          icon: const Icon(Icons.menu),
                          onPressed: () => Scaffold.of(context).openDrawer()))),
            Expanded(
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const DemoPageHeading(
                                      title: 'Orders',
                                      subtitle:
                                          'Orders approved by the clinic and assigned by the CAD team appear here. Start manufacturing, then send the order to QC.'),
                                  const SizedBox(height: 20),
                                  SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(children: [
                                        for (final tab in _labTabs)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8),
                                              child: ChoiceChip(
                                                  label: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(tab.$2),
                                                        const SizedBox(
                                                            width: 6),
                                                        Text(
                                                            '${overview[tab.$1.isEmpty ? 'all_orders' : tab.$1] ?? '—'}',
                                                            style: const TextStyle(
                                                                fontFamily:
                                                                    'monospace',
                                                                fontSize: 11)),
                                                      ]),
                                                  selected: group == tab.$1,
                                                  selectedColor:
                                                      DemoStyle.accent,
                                                  backgroundColor: Colors.white,
                                                  labelStyle: TextStyle(
                                                      color: group == tab.$1
                                                          ? Colors.white
                                                          : DemoStyle.ink),
                                                  side: BorderSide(
                                                      color: group == tab.$1
                                                          ? DemoStyle.accent
                                                          : DemoStyle.line),
                                                  showCheckmark: false,
                                                  onSelected: (_) {
                                                    setState(
                                                        () => group = tab.$1);
                                                    page = 1;
                                                    refresh();
                                                  })),
                                      ])),
                                  const SizedBox(height: 16),
                                  Row(children: [
                                    Expanded(
                                        child: TextField(
                                            controller: search,
                                            decoration: InputDecoration(
                                                prefixIcon:
                                                    const Icon(Icons.search),
                                                hintText:
                                                    'Search patient, clinic or order ID',
                                                suffixIcon: IconButton(
                                                    tooltip: 'Search',
                                                    icon: const Icon(
                                                        Icons.arrow_forward),
                                                    onPressed: () {
                                                      query =
                                                          search.text.trim();
                                                      page = 1;
                                                      refresh();
                                                    })),
                                            onSubmitted: (value) {
                                              query = value.trim();
                                              page = 1;
                                              refresh();
                                            })),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                        width: compact ? 140 : 180,
                                        child: DropdownButtonFormField<int?>(
                                            initialValue: clinicId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(),
                                            items: [
                                              const DropdownMenuItem<int?>(
                                                  value: null,
                                                  child: Text('All clinics')),
                                              for (final clinic in clinics)
                                                DropdownMenuItem<int?>(
                                                    value: clinic['id'] as int,
                                                    child: Text(
                                                        '${clinic['name']}',
                                                        overflow: TextOverflow
                                                            .ellipsis))
                                            ],
                                            onChanged: (value) {
                                              setState(() => clinicId = value);
                                              page = 1;
                                              refresh();
                                            })),
                                  ]),
                                  const SizedBox(height: 16),
                                  if (error != null)
                                    Text(error!,
                                        style: const TextStyle(
                                            color: DemoStyle.danger)),
                                  Expanded(
                                      child: loading
                                          ? const Center(
                                              child:
                                                  CircularProgressIndicator())
                                          : orders.isEmpty
                                              ? const Center(
                                                  child: Text(
                                                      'No matching orders.'))
                                              : compact
                                                  ? ListView.separated(
                                                      itemCount: orders.length,
                                                      separatorBuilder: (_, __) =>
                                                          const SizedBox(
                                                              height: 8),
                                                      itemBuilder: (_, i) => DemoPanel(
                                                          child: ListTile(
                                                              onTap: () => openOrder(
                                                                  orders[i]),
                                                              title: Text(
                                                                  '${orders[i]['order_id']}  •  ${orders[i]['patient_name']}',
                                                                  style: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700)),
                                                              subtitle:
                                                                  Text('${(orders[i]['clinic'] as Map?)?['name'] ?? ''}  •  ${_labStatus(orders[i]['status'])}'),
                                                              trailing: const Icon(Icons.chevron_right))))
                                                  : Align(
                                                      alignment: Alignment.topCenter,
                                                      child: SingleChildScrollView(
                                                          child: SingleChildScrollView(
                                                              scrollDirection: Axis.horizontal,
                                                              child: SizedBox(
                                                                  width: 940,
                                                                  child: DemoPanel(
                                                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                                                    Container(
                                                                        color: DemoStyle
                                                                            .surface2,
                                                                        padding: const EdgeInsets
                                                                            .all(
                                                                            12),
                                                                        child: const _LabRow(
                                                                            header:
                                                                                true)),
                                                                    for (final order
                                                                        in orders) ...[
                                                                      const Divider(
                                                                          height:
                                                                              1,
                                                                          color:
                                                                              DemoStyle.line),
                                                                      InkWell(
                                                                          onTap: () => openOrder(
                                                                              order),
                                                                          child: Padding(
                                                                              padding: const EdgeInsets.all(12),
                                                                              child: _LabRow(order: order))),
                                                                    ],
                                                                  ]))))))),
                                  if (total > 25)
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text('$total orders  •  page $page'),
                                          IconButton(
                                              onPressed: page > 1
                                                  ? () {
                                                      page--;
                                                      refresh();
                                                    }
                                                  : null,
                                              icon: const Icon(
                                                  Icons.chevron_left)),
                                          IconButton(
                                              onPressed: page * 25 < total
                                                  ? () {
                                                      page++;
                                                      refresh();
                                                    }
                                                  : null,
                                              icon: const Icon(
                                                  Icons.chevron_right)),
                                        ]),
                                ]))))),
          ]))
        ]));
  }
}

String _labStatus(Object? status) => switch (status) {
      'clinician_approved' => 'Manufacturing not started',
      'manufacturing_in_process' => 'Manufacturing in process',
      'manufactured' => 'QC approval pending',
      'qc_issues' => 'QC issue raised',
      _ => 'Manufacturing completed',
    };

class _LabRow extends StatelessWidget {
  final bool header;
  final Map<String, dynamic>? order;
  const _LabRow({this.header = false, this.order});
  @override
  Widget build(BuildContext context) {
    final data = order ?? {};
    final clinic = (data['clinic'] as Map?) ?? {};
    final history = (data['history'] as List?) ?? [];
    final assignment = history
        .where((entry) => entry is Map && entry['status'] == 'plan_completed')
        .lastOrNull;
    final assignedBy =
        assignment is Map ? assignment['by']?.toString() ?? '' : '';
    final label = _labStatus(data['status']);
    Widget cell(String heading, String value, int flex,
            {String? sub, bool bold = false, bool mono = false}) =>
        Expanded(
            flex: flex,
            child: header
                ? _heading(heading)
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
    return Row(children: [
      cell('ASSIGNED BY', assignedBy.isEmpty ? 'Clinical CAD team' : assignedBy,
          27,
          sub: 'Clinical CAD team', bold: true),
      cell('ORDER ID', '${data['order_id'] ?? ''}', 25,
          sub: data['patient_name']?.toString(), mono: true),
      cell('CLINIC', '${clinic['name'] ?? ''}', 26),
      Expanded(
          flex: 22,
          child: header
              ? Align(
                  alignment: Alignment.centerRight, child: _heading('ACTION'))
              : Align(
                  alignment: Alignment.centerRight, child: _LabPill(label))),
    ]);
  }

  static Widget _heading(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          letterSpacing: .7,
          fontWeight: FontWeight.w700,
          color: DemoStyle.muted));
}

class _LabPill extends StatelessWidget {
  final String label;
  const _LabPill(this.label);
  @override
  Widget build(BuildContext context) {
    final color = label == 'Manufacturing completed'
        ? const Color(0xFF1B7F4B)
        : label == 'QC issue raised'
            ? const Color(0xFFB3261E)
            : label == 'Manufacturing in process'
                ? const Color(0xFF235D9E)
                : DemoStyle.muted;
    final background = label == 'Manufacturing completed'
        ? const Color(0xFFDCF2E5)
        : label == 'QC issue raised'
            ? const Color(0xFFFCE4E2)
            : label == 'Manufacturing in process'
                ? const Color(0xFFDCE9F8)
                : DemoStyle.surface2;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
        ]));
  }
}
