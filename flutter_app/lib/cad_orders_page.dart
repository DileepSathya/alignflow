import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';
import 'orders_page.dart';

const _tabs = <(String, String)>[
  ('', 'All orders'),
  ('plan_pending', 'Plan pending'),
  ('clinical_approval_pending', 'Clinical approval pending'),
  ('issue_raised', 'Issue raised'),
  ('approved', 'Approved'),
  ('cancelled', 'Cancelled'),
];

class CadOrdersPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const CadOrdersPage(
      {super.key,
      required this.api,
      required this.user,
      required this.onLogout});

  @override
  State<CadOrdersPage> createState() => _CadOrdersPageState();
}

class _CadOrdersPageState extends State<CadOrdersPage> {
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
      final data = await widget.api.request('GET', '/api/cad/overview');
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
                role: 'cad')));
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
                      (widget.user['username']?.toString() ?? 'P')
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
                    const Text('Clinical CAD team',
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
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const DemoPageHeading(
                                      title: 'Orders',
                                      subtitle:
                                          'Every order submitted by the Marketing team appears here with status Plan pending. Open an order to review documents, update its status and leave comments.'),
                                  const SizedBox(height: 20),
                                  SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(children: [
                                        for (final tab in _tabs)
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
                                                                  Text('${(orders[i]['clinic'] as Map?)?['name'] ?? ''}  •  ${_cadStatus(orders[i]['status'])}'),
                                                              trailing: const Icon(Icons.chevron_right))))
                                                  : Align(
                                                      alignment: Alignment.topCenter,
                                                      child: SingleChildScrollView(
                                                          child: SingleChildScrollView(
                                                              scrollDirection: Axis.horizontal,
                                                              child: SizedBox(
                                                                  width: 1060,
                                                                  child: DemoPanel(
                                                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                                                    Container(
                                                                        color: DemoStyle
                                                                            .surface2,
                                                                        padding: const EdgeInsets
                                                                            .all(
                                                                            12),
                                                                        child: const _CadRow(
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
                                                                              child: _CadRow(order: order, onView: () => openOrder(order)))),
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

String _cadStatus(Object? status) => switch (status) {
      'submitted' => 'Plan pending',
      'plan_completed' => 'Clinical approval pending',
      'clinician_issues' => 'Issue raised',
      'cancelled' => 'Cancelled',
      _ => 'Approved',
    };

class _CadRow extends StatelessWidget {
  final bool header;
  final Map<String, dynamic>? order;
  final VoidCallback? onView;
  const _CadRow({this.header = false, this.order, this.onView});
  @override
  Widget build(BuildContext context) {
    final data = order ?? {};
    final clinic = (data['clinic'] as Map?) ?? {};
    final status = data['status'];
    final date =
        DateTime.tryParse(data['created_at']?.toString() ?? '')?.toLocal();
    final uploaded =
        date == null ? '' : '${date.day} ${_months[date.month - 1]}';
    final docs = (data['documents'] as List?)?.length ?? 0;
    final comments = (data['comments'] as List?)?.length ?? 0;
    Widget cell(String label, String value, int flex,
            {String? sub, bool bold = false, bool mono = false}) =>
        Expanded(
            flex: flex,
            child: header
                ? _heading(label)
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
      cell('ORDER', '${data['order_id'] ?? ''}', 13, mono: true),
      cell('PATIENT', '${data['patient_name'] ?? ''}', 14, bold: true),
      cell('CLINIC', '${clinic['name'] ?? ''}', 17,
          sub: clinic['dentist']?.toString()),
      cell('CASE', '', 9),
      cell('UPLOADED', uploaded, 10),
      Expanded(
          flex: 19,
          child: header
              ? _heading('STATUS')
              : Align(
                  alignment: Alignment.centerLeft,
                  child: _CadPill(_cadStatus(status)))),
      cell('DOCS · COMMENTS', '$docs docs · $comments comments', 18),
      SizedBox(
          width: 68,
          child: header
              ? const SizedBox.shrink()
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
  static Widget _heading(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          letterSpacing: .7,
          fontWeight: FontWeight.w700,
          color: DemoStyle.muted));
}

class _CadPill extends StatelessWidget {
  final String label;
  const _CadPill(this.label);
  @override
  Widget build(BuildContext context) {
    final color = label == 'Cancelled'
        ? const Color(0xFFB3261E)
        : label == 'Approved'
            ? const Color(0xFF1B7F4B)
            : DemoStyle.muted;
    final background = label == 'Cancelled'
        ? const Color(0xFFFCE4E2)
        : label == 'Approved'
            ? const Color(0xFFDCF2E5)
            : DemoStyle.surface2;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
