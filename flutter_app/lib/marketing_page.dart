import 'package:flutter/material.dart';
import 'api.dart';
import 'orders_page.dart';
import 'demo_style.dart';

const _teal = Color(0xFF0B7A75);
const _ink = Color(0xFF10242B);

class MarketingPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  const MarketingPage({super.key, required this.api, required this.user, required this.onLogout});

  @override
  State<MarketingPage> createState() => _MarketingPageState();
}

class _MarketingPageState extends State<MarketingPage> {
  final search = TextEditingController();
  List<Map<String, dynamic>> clinics = [];
  bool loading = true;
  String? error;
  String section = 'Orders';

  @override
  void initState() { super.initState(); refresh(); search.addListener(() => setState(() {})); }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> refresh() async {
    try {
      final result = await widget.api.request('GET', '/api/clinics');
      if (mounted) setState(() { clinics = (result['clinics'] as List).cast<Map<String, dynamic>>(); error = null; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> edit([Map<String, dynamic>? clinic]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => ClinicDialog(api: widget.api, clinic: clinic));
    if (saved == true) refresh();
  }

  Future<void> delete(Map<String, dynamic> clinic) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Delete clinic?'),
      content: Text('Delete ${clinic['clinic_name']}?'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete'))],
    ));
    if (confirmed != true) return;
    try { await widget.api.request('DELETE', '/api/clinics/${clinic['id']}'); await refresh(); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
  }

  void showActions(Map<String, dynamic> clinic) {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(clinic['clinic_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () { Navigator.pop(sheetContext); edit(clinic); }),
        ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'), onTap: () { Navigator.pop(sheetContext); delete(clinic); }),
      ],
    )));
  }

  Widget sidebar({bool compact = false}) => Container(
    width: compact ? null : 248, color: Colors.white,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.all(20), child: Row(children: [
        DemoBrandMark(size: 34),
        SizedBox(width: 10), Text('AlignFlow', style: TextStyle(fontFamily: 'Bricolage', fontSize: 19, fontWeight: FontWeight.bold)),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: DemoPanel(
        child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Marketing team', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(widget.user['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: DemoStyle.muted)),
          ])))),
      const SizedBox(height: 24),
      navItem('Orders', Icons.receipt_long_outlined),
      navItem('Clinics', Icons.home_work_outlined),
      const Spacer(), const Divider(),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), child: Container(
        padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: DemoStyle.bg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [CircleAvatar(radius: 16, backgroundColor: const Color(0xFFD9F1EF), child: Text((widget.user['name'] as String).substring(0, 1).toUpperCase())),
          const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.user['username'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Text('Marketing team', style: TextStyle(fontSize: 11)),
          ]))]),
      )),
      Padding(padding: const EdgeInsets.all(20), child: OutlinedButton(onPressed: () async { await widget.api.logout(); widget.onLogout(); }, child: const Text('Log out'))),
    ]),
  );

  Widget navItem(String name, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    child: Material(color: section == name ? const Color(0xFFD9F1EF) : Colors.transparent, borderRadius: BorderRadius.circular(9),
      child: ListTile(dense: true, leading: Icon(icon, color: section == name ? _teal : _ink),
        title: Text(name), selected: section == name, onTap: () { setState(() => section = name); if (MediaQuery.sizeOf(context).width < 900) Navigator.pop(context); })),
  );

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final query = search.text.trim().toLowerCase();
    final visible = clinics.where((c) => [c['clinic_name'], c['dentist_name'], c['area']]
        .any((v) => (v?.toString().toLowerCase() ?? '').contains(query))).toList();
    return Scaffold(
      drawer: narrow ? Drawer(child: sidebar(compact: true)) : null,
      body: Row(children: [if (!narrow) sidebar(), Expanded(child: Column(children: [
        if (narrow) AppBar(title: const Text('AlignFlow'), backgroundColor: Colors.white,
          leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer()))),
        Expanded(child: Padding(padding: EdgeInsets.all(narrow ? 16 : 24), child: section == 'Orders'
          ? OrdersPage(api: widget.api, clinics: clinics, user: widget.user)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Clinics', style: Theme.of(context).textTheme.headlineLarge),
              const Text('Partner clinics you contact over WhatsApp.', style: TextStyle(color: DemoStyle.muted)),
            ])), FilledButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add), label: Text(narrow ? 'Add' : 'Add clinic'))]),
            const SizedBox(height: 18),
            TextField(controller: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search clinic, dentist or area', filled: true, fillColor: Colors.white)),
            const SizedBox(height: 18),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
            Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : visible.isEmpty
              ? Center(child: Text(query.isEmpty ? 'No clinics yet. Add your first clinic.' : 'No matching clinics.'))
              : narrow ? ListView.separated(itemCount: visible.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => Card(child: InkWell(onLongPress: () => showActions(visible[i]), child: Padding(padding: const EdgeInsets.all(16), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(visible[i]['clinic_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Dentist: ${visible[i]['dentist_name']}'), Text('Contact: ${visible[i]['contact_number']}'),
                      if (visible[i]['email'] != null) Text(visible[i]['email'] as String), Text('Area: ${visible[i]['area']}'),
                      const SizedBox(height: 4), const Text('Long press for actions', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ])))))
              : Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDFE8EB))),
                  child: Column(children: [
                    Container(height: 40, color: const Color(0xFFE9F0F2), child: const Row(children: [
                      Expanded(flex: 3, child: Padding(padding: EdgeInsets.only(left: 14), child: Text('CLINIC'))),
                      Expanded(flex: 2, child: Text('DENTIST')), Expanded(flex: 3, child: Text('CONTACT')),
                      Expanded(flex: 2, child: Text('AREA')), SizedBox(width: 92),
                    ])),
                    Expanded(child: ListView.separated(itemCount: visible.length, separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => ClinicRow(clinic: visible[i], onEdit: () => edit(visible[i]), onDelete: () => delete(visible[i])))),
                  ]))),
          ]))),
      ]))]),
    );
  }
}

class ClinicRow extends StatefulWidget {
  final Map<String, dynamic> clinic;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const ClinicRow({super.key, required this.clinic, required this.onEdit, required this.onDelete});
  @override
  State<ClinicRow> createState() => _ClinicRowState();
}

class _ClinicRowState extends State<ClinicRow> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(onEnter: (_) => setState(() => hovered = true), onExit: (_) => setState(() => hovered = false),
    child: Container(height: 62, padding: const EdgeInsets.symmetric(horizontal: 14), color: hovered ? const Color(0xFFF7FAFA) : Colors.white,
      child: Row(children: [
        Expanded(flex: 3, child: Text(widget.clinic['clinic_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(flex: 2, child: Text(widget.clinic['dentist_name'] as String)),
        Expanded(flex: 3, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.clinic['contact_number'] as String), if (widget.clinic['email'] != null) Text(widget.clinic['email'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        Expanded(flex: 2, child: Text(widget.clinic['area'] as String)),
        SizedBox(width: 92, child: hovered ? Row(children: [
          IconButton(tooltip: 'Edit clinic', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: widget.onEdit),
          IconButton(tooltip: 'Delete clinic', icon: const Icon(Icons.delete_outline, size: 19), onPressed: widget.onDelete),
        ]) : null),
      ])));
}

class ClinicDialog extends StatefulWidget {
  final Api api;
  final Map<String, dynamic>? clinic;
  const ClinicDialog({super.key, required this.api, this.clinic});
  @override
  State<ClinicDialog> createState() => _ClinicDialogState();
}

class _ClinicDialogState extends State<ClinicDialog> {
  late final name = TextEditingController(text: widget.clinic?['clinic_name'] as String? ?? '');
  late final dentist = TextEditingController(text: widget.clinic?['dentist_name'] as String? ?? '');
  late final contact = TextEditingController(text: widget.clinic?['contact_number'] as String? ?? '');
  late final email = TextEditingController(text: widget.clinic?['email'] as String? ?? '');
  late final area = TextEditingController(text: widget.clinic?['area'] as String? ?? '');
  bool saving = false;
  String? error;

  @override
  void dispose() { name.dispose(); dentist.dispose(); contact.dispose(); email.dispose(); area.dispose(); super.dispose(); }

  Future<void> save() async {
    if ([name, dentist, contact, area].any((c) => c.text.trim().isEmpty)) { setState(() => error = 'Complete all required fields.'); return; }
    if (email.text.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) {
      setState(() => error = 'Enter a valid email address.'); return;
    }
    setState(() { saving = true; error = null; });
    try {
      await widget.api.request(widget.clinic == null ? 'POST' : 'PUT',
        widget.clinic == null ? '/api/clinics' : '/api/clinics/${widget.clinic!['id']}', {
          'clinic_name': name.text.trim(), 'dentist_name': dentist.text.trim(),
          'contact_number': contact.text.trim(), 'email': email.text.trim(), 'area': area.text.trim(),
        });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.clinic == null ? 'Add clinic' : 'Edit clinic'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Save a clinic so it can be picked when uploading orders.'), const SizedBox(height: 18),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Clinic name')), const SizedBox(height: 12),
      TextField(controller: dentist, decoration: const InputDecoration(labelText: 'Dentist')), const SizedBox(height: 12),
      TextField(controller: contact, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact number')), const SizedBox(height: 12),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')), const SizedBox(height: 12),
      TextField(controller: area, decoration: const InputDecoration(labelText: 'Area / city')),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
    ]))),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Saving...' : widget.clinic == null ? 'Add clinic' : 'Save changes'))],
  );
}
