import 'scanner_checklist.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';

const _statuses = <String, String>{
  'scanner_review': 'Preparing documents',
  'scanner_missing': 'Document corrections requested',
  'planner_document_review': 'Planner document review',
  'submitted': 'Ready for Planning',
  'planning_in_progress': 'Planning in progress',
  'plan_completed': 'Clinician review pending',
  'clinician_issues': 'Clinician raised issues',
  'clinician_approved': 'Clinician approved',
  'manufacturing_in_process': 'Manufacturing in process',
  'manufactured': 'QC approval pending',
  'qc_issues': 'QC raised issue',
  'qc_approved': 'QC approved',
  'manufacture_completed': 'QC approved', // Legacy completed orders.
  'cancelled': 'Cancelled',
};

String orderStatusLabel(Object? status) =>
    _statuses[status] ?? status?.toString() ?? '';

const _progressSteps = <(String, String)>[
  ('scanner_review', 'Preparing documents'),
  ('planner_document_review', 'Planner document review'),
  ('scanner_missing', 'Document corrections requested'),
  ('submitted', 'Documents approved'),
  ('planning_in_progress', 'Planning in progress'),
  ('plan_completed', 'Plan completed'),
  ('plan_completed', 'Clinician review pending'),
  ('clinician_issues', 'Clinician raised issues'),
  ('clinician_approved', 'Clinician approved'),
  ('manufacturing_in_process', 'Manufacturing in process'),
  ('manufactured', 'Manufactured'),
  ('manufactured', 'QC approval pending'),
  ('qc_issues', 'QC raised issue'),
  ('qc_approved', 'QC approved'),
];

class OrdersPage extends StatefulWidget {
  final Api api;
  final List<Map<String, dynamic>> clinics;
  final Map<String, dynamic> user;
  final Map<String, String> dashboardFilters;
  final ValueChanged<int>? onTotalChanged;
  const OrdersPage(
      {super.key,
      required this.api,
      required this.clinics,
      required this.user,
      this.dashboardFilters = const {},
      this.onTotalChanged});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final search = TextEditingController();
  List<Map<String, dynamic>> orders = [];
  String filter = '';
  String? error;
  bool loading = true;
  int page = 1, total = 0;

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

  Future<void> refresh({int? newPage}) async {
    if (newPage != null) page = newPage;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final path = Uri(path: '/api/orders', queryParameters: {
        ...widget.dashboardFilters,
        if (filter.isNotEmpty) 'status_group': '',
        'page': '$page',
        'limit': '25',
        if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
        if (filter.isNotEmpty) 'status_filter': filter,
      }).toString();
      final result = await widget.api.request('GET', path);
      if (mounted) {
        setState(() {
          orders = (result['orders'] as List).cast<Map<String, dynamic>>();
          total = result['total'] as int;
        });
        if (search.text.trim().isEmpty && filter.isEmpty) {
          widget.onTotalChanged?.call(total);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) =>
            CreateOrderDialog(api: widget.api, clinics: widget.clinics));
    if (saved == true) refresh(newPage: 1);
  }

  Future<void> openOrder(Map<String, dynamic> order) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OrderDetailPage(
            api: widget.api,
            orderId: order['order_id'] as String,
            role: widget.user['role'] as String)));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final desktop = MediaQuery.sizeOf(context).width >= 1050;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            const DemoPageHeading(
                title: 'Orders',
                subtitle:
                    'Track every patient case from submission to delivery.'),
            if (widget.user['role'] == 'marketing' ||
                widget.user['role'] == 'clinic_admin')
              FilledButton.icon(
                  onPressed: create,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('Upload patient details')),
          ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
            child: TextField(
                controller: search,
                onSubmitted: (_) => refresh(newPage: 1),
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search order ID, patient or clinic name',
                    suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: () => refresh(newPage: 1),
                        icon: const Icon(Icons.arrow_forward))))),
        const SizedBox(width: 10),
        SizedBox(
            width: narrow ? 138 : 170,
            child: DropdownButtonFormField<String>(
                initialValue: filter,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('All statuses')),
                  ..._statuses.entries
                      .where((entry) => entry.key != 'manufacture_completed')
                      .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value,
                              overflow: TextOverflow.ellipsis)))
                ],
                onChanged: (value) {
                  filter = value ?? '';
                  refresh(newPage: 1);
                })),
      ]),
      const SizedBox(height: 16),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.red)),
      Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : orders.isEmpty
                  ? Center(
                      child: Text(error == null
                          ? 'No matching orders.'
                          : 'Orders could not be loaded.'))
                  : Align(
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                          child: DemoPanel(
                              child: desktop
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                          Container(
                                              color: DemoStyle.surface2,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                              child: const Row(children: [
                                                Expanded(
                                                    flex: 2,
                                                    child: _OrderHeading(
                                                        'ORDER ID')),
                                                Expanded(
                                                    flex: 3,
                                                    child: _OrderHeading(
                                                        'PATIENT NAME')),
                                                Expanded(
                                                    flex: 3,
                                                    child: _OrderHeading(
                                                        'CLINIC NAME')),
                                                Expanded(
                                                    flex: 3,
                                                    child: _OrderHeading(
                                                        'STATUS')),
                                                SizedBox(
                                                    width: 76,
                                                    child: Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: _OrderHeading(
                                                            'DETAILS'))),
                                              ])),
                                          for (final order in orders) ...[
                                            const Divider(
                                                height: 1,
                                                color: DemoStyle.line),
                                            InkWell(
                                                onTap: () => openOrder(order),
                                                child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 16,
                                                        vertical: 13),
                                                    child: Row(children: [
                                                      Expanded(
                                                          flex: 2,
                                                          child: Text(
                                                              '${order['order_id']}',
                                                              style: const TextStyle(
                                                                  fontFamily:
                                                                      'monospace',
                                                                  fontSize: 12,
                                                                  color: DemoStyle
                                                                      .muted))),
                                                      Expanded(
                                                          flex: 3,
                                                          child: Text(
                                                              '${order['patient_name']}',
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700))),
                                                      Expanded(
                                                          flex: 3,
                                                          child: Text(
                                                              '${(order['clinic'] as Map)['name']}',
                                                              style: const TextStyle(
                                                                  color: DemoStyle
                                                                      .muted))),
                                                      Expanded(
                                                          flex: 3,
                                                          child: Align(
                                                              alignment: Alignment
                                                                  .centerLeft,
                                                              child: _OrderStatus(
                                                                  status:
                                                                      '${order['status']}'))),
                                                      SizedBox(
                                                          width: 76,
                                                          child: Align(
                                                              alignment: Alignment
                                                                  .centerRight,
                                                              child: OutlinedButton(
                                                                  onPressed: () =>
                                                                      openOrder(
                                                                          order),
                                                                  style: OutlinedButton.styleFrom(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                          horizontal:
                                                                              11)),
                                                                  child: const Text(
                                                                      'View')))),
                                                    ]))),
                                          ],
                                        ])
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: orders.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(
                                              height: 1, color: DemoStyle.line),
                                      itemBuilder: (_, index) {
                                        final order = orders[index];
                                        return ListTile(
                                            onTap: () => openOrder(order),
                                            title: Text(
                                                '${order['order_id']}  •  ${order['patient_name']}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            subtitle: Text(
                                                '${(order['clinic'] as Map)['name']}'),
                                            trailing: _OrderStatus(
                                                status: '${order['status']}'));
                                      }))))),
      if (total > 25)
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('$total orders  •  page $page'),
          IconButton(
              onPressed: page > 1 ? () => refresh(newPage: page - 1) : null,
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              onPressed:
                  page * 25 < total ? () => refresh(newPage: page + 1) : null,
              icon: const Icon(Icons.chevron_right)),
        ]),
    ]);
  }
}

class _OrderHeading extends StatelessWidget {
  final String text;
  const _OrderHeading(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: DemoStyle.muted));
}

class _OrderStatus extends StatelessWidget {
  final String status;
  const _OrderStatus({required this.status});
  @override
  Widget build(BuildContext context) {
    final completed = {'qc_approved', 'manufacture_completed'};
    final issues = {'cancelled', 'clinician_issues', 'qc_issues'};
    final color = completed.contains(status)
        ? const Color(0xFF1B7F4B)
        : issues.contains(status)
            ? const Color(0xFFB3261E)
            : const Color(0xFF235D9E);
    final background = completed.contains(status)
        ? const Color(0xFFDCF2E5)
        : issues.contains(status)
            ? const Color(0xFFFCE4E2)
            : const Color(0xFFDCE9F8);
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
              child: Text(orderStatusLabel(status),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
        ]));
  }
}

class CreateOrderDialog extends StatefulWidget {
  final Api api;
  final List<Map<String, dynamic>> clinics;
  const CreateOrderDialog(
      {super.key, required this.api, required this.clinics});
  @override
  State<CreateOrderDialog> createState() => _CreateOrderDialogState();
}

class _CreateOrderDialogState extends State<CreateOrderDialog> {
  final name = TextEditingController(),
      mobile = TextEditingController(),
      email = TextEditingController(),
      clinicPatientId = TextEditingController(),
      age = TextEditingController(),
      notes = TextEditingController();
  int? get clinicId => widget.clinics.length == 1
      ? widget.clinics.first['id'] as int
      : selectedClinicId;
  int? selectedClinicId;
  int? clinicianId;
  bool saving = false;
  String? error;
  late final requestId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}-${Random.secure().nextInt(0x7fffffff)}';
  List<PlatformFile> attachments = [];
  String? createdOrderId;
  int uploadedCount = 0;
  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    email.dispose();
    clinicPatientId.dispose();
    age.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'stl']);
    if (result.isNotEmpty)
      setState(() => attachments = [...attachments, ...result]);
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty ||
        mobile.text.trim().isEmpty ||
        clinicId == null ||
        clinicianId == null) {
      setState(() => error =
          'Enter patient name and mobile, then select a clinic and clinician.');
      return;
    }
    final parsedAge =
        age.text.trim().isEmpty ? null : int.tryParse(age.text.trim());
    if (age.text.trim().isNotEmpty &&
        (parsedAge == null || parsedAge < 0 || parsedAge > 120)) {
      setState(() => error = 'Enter an age from 0 to 120.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = createdOrderId == null ? await widget.api.request('POST', '/api/orders', {
        'request_id': requestId,
        'patient_name': name.text.trim(),
        'patient_mobile_number': mobile.text.trim(),
        'patient_email': email.text.trim().isEmpty ? null : email.text.trim(),
        'clinic_patient_id': clinicPatientId.text.trim().isEmpty
            ? null
            : clinicPatientId.text.trim(),
        'clinician_id': clinicianId,
        'age': parsedAge,
        'clinic_id': clinicId,
        'notes': notes.text.trim(),
      }) : null;
      createdOrderId ??= (result!['order'] as Map)['order_id'] as String;
      while (uploadedCount < attachments.length) {
        await widget.api.uploadOrderFile(createdOrderId!, attachments[uploadedCount]);
        uploadedCount++;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = createdOrderId == null
          ? e.toString()
          : 'Order $createdOrderId was created. ${attachments.length - uploadedCount} file(s) still need uploading. Retry to continue. $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinic =
        widget.clinics.where((item) => item['id'] == clinicId).firstOrNull;
    return AlertDialog(
        title: const Text('Upload patient details'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  const Text(
                      'Create a new order from the details received on WhatsApp.'),
                  const SizedBox(height: 16),
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Patient name *')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: mobile,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Patient mobile *')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Patient email (optional)')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: clinicPatientId,
                      decoration: const InputDecoration(
                          labelText: 'Clinic patient ID (optional)')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: age,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Age (optional)')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                      initialValue: clinicId,
                      decoration: const InputDecoration(labelText: 'Clinic *'),
                      items: widget.clinics
                          .map((item) => DropdownMenuItem(
                              value: item['id'] as int,
                              child: Text(item['clinic_name'] as String)))
                          .toList(),
                      onChanged: widget.clinics.length == 1
                          ? null
                          : (value) => setState(() {
                                selectedClinicId = value;
                                clinicianId = null;
                              })),
                  if (clinic != null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                        initialValue: clinicianId,
                        decoration:
                            const InputDecoration(labelText: 'Clinician *'),
                        items: ((clinic['clinicians'] as List?) ?? [])
                            .map((person) => DropdownMenuItem<int>(
                                value: person['clinician_id'] as int,
                                child: Text(person['name'] as String)))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => clinicianId = value)),
                    Text(
                        'Contact: ${clinic['contact_number']}  •  ${clinic['email'] ?? 'No email'}'),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Case notes (optional)')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: saving ? null : pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach photos, X-rays or scans')),
                  if (attachments.isNotEmpty)
                    Text('${attachments.length} file(s) selected'),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: const TextStyle(color: Colors.red))),
                ]))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? 'Submitting...' : 'Submit order'))
        ]);
  }
}

class RaiseIssueDialog extends StatefulWidget {
  final String targetTeam;
  const RaiseIssueDialog({super.key, required this.targetTeam});

  @override
  State<RaiseIssueDialog> createState() => _RaiseIssueDialogState();
}

class _RaiseIssueDialogState extends State<RaiseIssueDialog> {
  final comment = TextEditingController();
  List<PlatformFile> files = [];
  String? error;

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> pickFiles() async {
    final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'stl']);
    if (mounted && selection.isNotEmpty)
      setState(() => files = [...files, ...selection]);
  }

  void submit() {
    final text = comment.text.trim();
    if (text.isEmpty) {
      setState(() => error = 'Describe the issue before submitting.');
      return;
    }
    Navigator.pop(context, (text: text, files: files));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Raise issue'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  TextField(
                      controller: comment,
                      maxLines: 4,
                      decoration: InputDecoration(
                          labelText: 'Issue comment *',
                          hintText:
                              'Describe the issue for the ${widget.targetTeam} team')),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                      onPressed: pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach files (optional)')),
                  const Text('PDF, JPG, PNG, or STL'),
                  for (var i = 0; i < files.length; i++)
                    ListTile(
                        dense: true,
                        title: Text(files[i].name),
                        trailing: IconButton(
                            tooltip: 'Remove file',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => files.removeAt(i)))),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Raise issue')),
        ],
      );
}

class OrderDetailPage extends StatefulWidget {
  final Api api;
  final String orderId;
  final String role;
  final int? userId;
  final bool qcMode;
  const OrderDetailPage(
      {super.key,
      required this.api,
      required this.orderId,
      this.role = 'marketing',
      this.userId,
      this.qcMode = false});
  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  Map<String, dynamic>? order;
  List<dynamic> planners = [];
  String? error;
  final comment = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    refresh();
    if (widget.role == 'admin') loadPlanners();
  }

  Future<void> loadPlanners() async {
    try {
      final result = await widget.api.request('GET', '/api/users');
      if (mounted) setState(() => planners =
          (result['users'] as List<dynamic>).where((user) => user['role'] == 'planning').toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final result =
          await widget.api.request('GET', '/api/orders/${widget.orderId}');
      if (mounted)
        setState(() {
          order = result['order'] as Map<String, dynamic>;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> action(String method, String path,
      [Map<String, dynamic>? body]) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request(method, path, body);
      if (mounted)
        setState(() => order = result['order'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addFiles() async {
    final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'stl']);
    if (selection.isEmpty) return;
    setState(() => busy = true);
    try {
      for (final file in selection) {
        await widget.api.uploadOrderFile(widget.orderId, file);
      }
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> raiseIssue() async {
    final isQc = widget.qcMode;
    final details = await showDialog<({String text, List<PlatformFile> files})>(
        context: context,
        builder: (_) => RaiseIssueDialog(
            targetTeam: isQc ? 'Production team' : 'Planning team'));
    if (details == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    var uploaded = 0;
    var issueCreated = false;
    String? submissionError;
    try {
      await widget.api.request('POST', '/api/orders/${widget.orderId}/issues', {
        'text': details.text,
        'raised_to': isQc ? 'production' : 'planning'
      });
      issueCreated = true;
      for (final file in details.files) {
        await widget.api.uploadOrderFile(widget.orderId, file);
        uploaded++;
      }
    } catch (e) {
      submissionError = issueCreated
          ? 'Issue saved; $uploaded of ${details.files.length} files uploaded. $e'
          : e.toString();
    } finally {
      await refresh();
      if (mounted) {
        setState(() {
          busy = false;
          if (submissionError != null) {
            error = submissionError;
          }
        });
      }
    }
  }

  Future<void> downloadFile(Map document) async {
    try {
      final bytes = await widget.api
          .downloadOrderFile(widget.orderId, document['id'] as String);
      await FilePicker.saveFile(
          fileName: document['name'] as String,
          bytes: Uint8List.fromList(bytes));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> editPatient() async {
    final current = order!;
    final name = TextEditingController(text: current['patient_name'] as String);
    final mobile = TextEditingController(
        text: current['patient_mobile_number'] as String? ?? '');
    final email =
        TextEditingController(text: current['patient_email'] as String? ?? '');
    final clinicPatientId = TextEditingController(
        text: current['clinic_patient_id'] as String? ?? '');
    final age = TextEditingController(text: current['age']?.toString() ?? '');
    final notes =
        TextEditingController(text: current['notes'] as String? ?? '');
    final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Edit patient'),
                content: SizedBox(
                    width: 500,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Patient name')),
                      TextField(
                          controller: mobile,
                          decoration: const InputDecoration(
                              labelText: 'Patient mobile')),
                      TextField(
                          controller: email,
                          decoration: const InputDecoration(
                              labelText: 'Patient email')),
                      TextField(
                          controller: clinicPatientId,
                          decoration: const InputDecoration(
                              labelText: 'Clinic patient ID')),
                      TextField(
                          controller: age,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Age')),
                      TextField(
                          controller: notes,
                          maxLines: 3,
                          decoration:
                              const InputDecoration(labelText: 'Case notes')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Save'))
                ]));
    if (saved == true) {
      await action('PUT', '/api/orders/${widget.orderId}/patient', {
        'patient_name': name.text.trim(),
        'patient_mobile_number': mobile.text.trim(),
        'patient_email': email.text.trim().isEmpty ? null : email.text.trim(),
        'clinic_patient_id': clinicPatientId.text.trim().isEmpty
            ? null
            : clinicPatientId.text.trim(),
        'age': age.text.trim().isEmpty ? null : int.tryParse(age.text.trim()),
        'notes': notes.text.trim(),
      });
    }
    name.dispose();
    mobile.dispose();
    email.dispose();
    clinicPatientId.dispose();
    age.dispose();
    notes.dispose();
  }

  Widget panel(String title, Widget child) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            child
          ])));
  @override
  Widget build(BuildContext context) {
    final data = order;
    return Scaffold(
        appBar: AppBar(title: Text(widget.orderId)),
        body: data == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Text(error!))
            : ListView(padding: const EdgeInsets.all(20), children: [
                Text(data['patient_name'] as String,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                Text(_statuses[data['status']] ?? '${data['status']}'),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                panel(
                    'Progress',
                    SizedBox(
                        height: 80,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (var i = 0; i < _progressSteps.length; i++)
                                SizedBox(
                                    width: 145,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Builder(builder: (context) {
                                            final step = _progressSteps[i];
                                            final history =
                                                data['history'] as List;
                                            final reached = step.$1 ==
                                                        'qc_approved' &&
                                                    data['status'] ==
                                                        'manufacture_completed' ||
                                                history.any((entry) =>
                                                    entry['status'] == step.$1);
                                            return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(children: [
                                                    Container(
                                                        width: 26,
                                                        height: 26,
                                                        alignment:
                                                            Alignment.center,
                                                        decoration: BoxDecoration(
                                                            shape:
                                                                BoxShape.circle,
                                                            color: reached
                                                                ? DemoStyle
                                                                    .accent
                                                                : DemoStyle
                                                                    .surface2),
                                                        child: Text('${i + 1}',
                                                            style: TextStyle(
                                                                fontSize: 11,
                                                                color: reached
                                                                    ? Colors
                                                                        .white
                                                                    : DemoStyle
                                                                        .muted))),
                                                    Expanded(
                                                        child: Container(
                                                            height: 2,
                                                            color: DemoStyle
                                                                .line)),
                                                  ]),
                                                  const SizedBox(height: 8),
                                                  Text(step.$2,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              DemoStyle.muted),
                                                      maxLines: 2),
                                                ]);
                                          }),
                                        ])),
                            ]))),
                panel(
                    'Patient',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Name: ${data['patient_name']}'),
                          Text('Patient ID: ${data['patient_id'] ?? '—'}'),
                          Text(
                              'Clinic patient ID: ${data['clinic_patient_id'] ?? '—'}'),
                          Text(
                              'Mobile: ${data['patient_mobile_number'] ?? '—'}'),
                          Text('Email: ${data['patient_email'] ?? '—'}'),
                          Text('Age: ${data['age'] ?? '—'}'),
                          Text('Case notes: ${data['notes'] ?? ''}'),
                          if (widget.role == 'marketing')
                            TextButton.icon(
                                onPressed: busy ? null : editPatient,
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit patient')),
                        ])),
                panel(
                    'Clinic (view only)',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Name: ${(data['clinic'] as Map)['name']}'),
                          Text(
                              'Clinicians: ${((data['clinic'] as Map)['clinicians'] as List?)?.map((person) => person['name']).join(', ') ?? (data['clinic'] as Map)['dentist'] ?? '—'}'),
                          Text(
                              'Contact: ${(data['clinic'] as Map)['contact']}'),
                          Text(
                              'Email: ${(data['clinic'] as Map)['email'] ?? '—'}'),
                          Text('Area: ${(data['clinic'] as Map)['area']}'),
                        ])),
                if (data['checklist'] != null)
                  ScannerChecklist(
                      api: widget.api,
                      order: data,
                      role: widget.role,
                      onChanged: refresh),
                panel(
                    'Documents (${(data['documents'] as List).length})',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final document in data['documents'] as List)
                            ListTile(
                                title: Text(document['name'] as String),
                                subtitle: Text(
                                    'Uploaded by ${document['by']} (${document['role']})'),
                                onTap: () => downloadFile(document as Map),
                                trailing: widget.role != 'admin' &&
                                        document['role'] == widget.role &&
                                        (document['checklist_id'] == null ||
                                            document['checklist_id'] == '') &&
                                        !(data['checklist'] as List? ?? []).any(
                                            (item) =>
                                                (item['document_ids'] as List)
                                                    .contains(document['id']))
                                    ? IconButton(
                                        tooltip: 'Delete',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: busy
                                            ? null
                                            : () async {
                                                try {
                                                  await widget.api.request(
                                                      'DELETE',
                                                      '/api/orders/${widget.orderId}/documents/${document['id']}');
                                                  await refresh();
                                                } catch (e) {
                                                  if (mounted)
                                                    setState(() =>
                                                        error = e.toString());
                                                }
                                              })
                                    : null),
                          if (widget.role != 'admin')
                            OutlinedButton.icon(
                                onPressed: busy ? null : addFiles,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Add documents')),
                        ])),
                panel(
                    'Comments (${(data['comments'] as List).length})',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in data['comments'] as List)
                            ListTile(
                                title: Text(item['text'] as String),
                                subtitle:
                                    Text('${item['by']} • ${item['at']}')),
                          if (widget.role != 'admin')
                            TextField(
                                controller: comment,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    hintText: 'Write a comment')),
                          if (widget.role != 'admin')
                            Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            if (comment.text.trim().isEmpty)
                                              return;
                                            await action(
                                                'POST',
                                                '/api/orders/${widget.orderId}/comments',
                                                {'text': comment.text.trim()});
                                            comment.clear();
                                          },
                                    child: const Text('Post comment'))),
                        ])),
                panel(
                    'Issues (${(data['issues'] as List).length})',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in data['issues'] as List)
                            ListTile(
                                title: Text(item['text'] as String),
                                subtitle: Text('${item['by']} → ${[
                                  'lab',
                                  'production'
                                ].contains(item['raised_to']) ? 'Production team' : 'Planning team'} • ${item['resolved_at'] == null ? 'Open' : 'Resolved'}'),
                                trailing: ((widget.role == 'planning' &&
                                                [
                                                  'cad',
                                                  'planning'
                                                ].contains(item['raised_to']) &&
                                                data['status'] ==
                                                    'clinician_issues') ||
                                            (widget.role == 'production' &&
                                                [
                                                  'lab',
                                                  'production'
                                                ].contains(item['raised_to']) &&
                                                data['status'] ==
                                                    'qc_issues')) &&
                                        item['resolved_at'] == null
                                    ? TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => action('POST',
                                                '/api/orders/${widget.orderId}/issues/${item['id']}/resolve'),
                                        child: const Text('Resolve'))
                                    : null),
                          if ((['marketing', 'clinic_admin']
                                      .contains(widget.role) &&
                                  data['status'] == 'plan_completed') ||
                              (widget.qcMode &&
                                  data['status'] == 'manufactured'))
                            Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                    onPressed: busy ? null : raiseIssue,
                                    child: const Text('Raise issue'))),
                        ])),
                if (['marketing', 'clinic_admin'].contains(widget.role) &&
                    [
                      'scanner_review',
                      'scanner_missing',
                      'planner_document_review',
                      'submitted',
                      'planning_in_progress',
                      'plan_completed',
                      'clinician_issues'
                    ].contains(data['status']))
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => action(
                                  'POST',
                                  '/api/orders/${widget.orderId}/status',
                                  {'status': 'cancelled'}),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel order'))),
                if (data['assigned_planner'] != null)
                  Text('Planner: ${data['assigned_planner']['name']}'),
                if (widget.role == 'planning' &&
                    !widget.qcMode &&
                    data['status'] == 'submitted')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action('POST',
                              '/api/orders/${widget.orderId}/assign', {}),
                      child: const Text('Assign to me')),
                if (widget.role == 'admin' && data['status'] == 'submitted' &&
                    data['assigned_planner'] == null)
                  Wrap(spacing: 8, children: [
                    FilledButton(
                      onPressed: busy || widget.userId == null ? null : () => action(
                        'POST', '/api/admin/orders/${widget.orderId}/assign',
                        {'user_id': widget.userId}),
                      child: const Text('Assign to me')),
                    PopupMenuButton<int>(
                      enabled: !busy && planners.isNotEmpty,
                      tooltip: 'Assign to planner',
                      onSelected: (id) => action(
                        'POST', '/api/admin/orders/${widget.orderId}/assign',
                        {'user_id': id}),
                      itemBuilder: (_) => [
                        for (final planner in planners)
                          PopupMenuItem<int>(value: planner['id'] as int,
                            child: Text(planner['name'].toString())),
                      ],
                      child: const Padding(padding: EdgeInsets.all(10),
                        child: Text('Assign to planner')),
                    ),
                  ]),
                if (['planning', 'admin'].contains(widget.role) &&
                    !widget.qcMode &&
                    data['status'] == 'planning_in_progress' &&
                    (data['assigned_planner'] as Map?)?['id'] == widget.userId)
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'plan_completed'}),
                      child: const Text('Plan completed')),
                if (['marketing', 'clinic_admin'].contains(widget.role) &&
                    data['status'] == 'plan_completed')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'clinician_approved'}),
                      child: const Text('Clinician approved')),
                if (['marketing', 'clinic_admin'].contains(widget.role) &&
                    data['status'] == 'clinician_issues' &&
                    (data['issues'] as List).isEmpty)
                  OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'plan_completed'}),
                      child: const Text('Return to clinical review')),
                if (widget.role == 'production' &&
                    data['status'] == 'clinician_approved')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'manufacturing_in_process'}),
                      child: const Text('Start manufacturing')),
                if (widget.role == 'production' &&
                    data['status'] == 'manufacturing_in_process')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'manufactured'}),
                      child: const Text('Send to QC')),
                if (widget.qcMode && data['status'] == 'manufactured')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'qc_approved'}),
                      child: const Text('QC approved')),
              ]));
  }
}
