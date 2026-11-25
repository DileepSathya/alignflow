import 'scanner_checklist.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'demo_style.dart';
import 'app_router.dart';

const _statuses = <String, String>{
  'upcoming': 'Upcoming',
  'scanner_review': 'Preparing documents',
  'scanner_missing': 'Document corrections requested',
  'planner_document_review': 'Planner document review',
  'submitted': 'Ready for Planning',
  'planning_in_progress': 'Planning in progress',
  'plan_completed': 'Clinician review pending',
  'issue_raised': 'Issue Raised',
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

String batchLabel(Map order, int number) {
  final batches = order['batches'] as List;
  final batch = batches[number - 1];
  return 'Batch $number/${batches.length} · ${batch['quantity']} aligners · ${orderStatusLabel(batch['status'])}';
}

String assignedClinicianName(Map order) {
  final clinicianId = order['clinician_id'];
  final clinicians = (order['clinic'] as Map?)?['clinicians'] as List?;
  if (clinicianId == null || clinicians == null) return '—';
  for (final clinician in clinicians) {
    if (clinician is Map && clinician['clinician_id'] == clinicianId) {
      return clinician['name']?.toString() ?? '—';
    }
  }
  return '—';
}

const issueRecipients = {
  'marketing': 'Marketing', 'scanner': 'Scanner', 'planning': 'Planning',
  'production': 'Production', 'clinician': 'Case clinician',
};

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
    await AppRouter.of(context).openOrder(order['order_id'] as String);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final issueQueue = widget.dashboardFilters.containsKey('issue_queue');
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final desktop = MediaQuery.sizeOf(context).width >= 1050;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            DemoPageHeading(
                title: issueQueue ? 'Issue queue' : 'Orders',
                subtitle:
                    issueQueue ? 'Open an order to review its assigned issues.' : 'Track every patient case from submission to delivery.'),
            if (!issueQueue && ['marketing', 'clinic_admin', 'clinician']
                .contains(widget.user['role']))
              FilledButton.icon(
                  onPressed: create,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('Create order')),
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
                                                          child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                    '${(order['clinic'] as Map)['name']}',
                                                                    style: const TextStyle(
                                                                        color: DemoStyle
                                                                            .muted)),
                                                                Text(
                                                                    assignedClinicianName(
                                                                        order),
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            11,
                                                                        color: DemoStyle
                                                                            .muted)),
                                                              ])),
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
                                                '${(order['clinic'] as Map)['name']}\n${assignedClinicianName(order)}'),
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
    final issues = {'issue_raised', 'cancelled', 'clinician_issues', 'qc_issues'};
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
      caseId = TextEditingController(),
      age = TextEditingController(),
      notes = TextEditingController();
  int? get clinicId => widget.clinics.length == 1
      ? widget.clinics.first['id'] as int
      : selectedClinicId;
  int? selectedClinicId;
  late int? clinicianId = widget.clinics.length == 1 &&
          (widget.clinics.first['clinicians'] as List?)?.length == 1
      ? widget.clinics.first['clinicians'][0]['clinician_id'] as int
      : null;
  bool saving = false;
  String? error;
  late final requestId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}-${Random.secure().nextInt(0x7fffffff)}';
  List<PlatformFile> attachments = [];
  final Map<String, List<int>> mappedFiles = {};
  List<dynamic> mandatoryItems = [];
  bool checklistLoaded = false;
  String? createdOrderId;
  int uploadedCount = 0;
  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    email.dispose();
    clinicPatientId.dispose();
    caseId.dispose();
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

  Future<void> loadChecklist() async {
    try {
      final response = await widget.api.request('GET', '/api/scanner/checklist');
      if (mounted) {
        setState(() {
          mandatoryItems = (response['items'] as List)
              .where((item) => item['mandatory'] == true).toList();
          checklistLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load required files: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    loadChecklist();
  }

  Future<void> selectMappedFiles(Map item) async {
    final id = item['id'] as String;
    final compatible = <int>[
      for (var index = 0; index < attachments.length; index++)
        if ((item['extensions'] as List).any((extension) =>
            attachments[index].name.toLowerCase().endsWith(extension as String)) &&
            !mappedFiles.entries.any((entry) =>
                entry.key != id && entry.value.contains(index)))
          index
    ];
    final selected = Set<int>.from(mappedFiles[id] ?? []);
    final result = await showDialog<Set<int>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text('Map ${item['label']}'),
                  content: SizedBox(
                      width: 480,
                      child: ListView(shrinkWrap: true, children: [
                        for (final index in compatible)
                          CheckboxListTile(
                              title: Text(attachments[index].name),
                              value: selected.contains(index),
                              onChanged: (value) => update(() {
                                    if (value == true) {
                                      selected.add(index);
                                    } else {
                                      selected.remove(index);
                                    }
                                  }))
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, selected),
                        child: const Text('Save'))
                  ],
                )));
    if (result != null && mounted) {
      setState(() => mappedFiles[id] = result.toList()..sort());
    }
  }

  bool get allMandatoryMapped => checklistLoaded && mandatoryItems.every(
      (item) => (mappedFiles[item['id']] ?? []).length >= item['min_files']);

  Future<void> save({bool sendForReview = false}) async {
    if (sendForReview && !allMandatoryMapped) return;
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
      final result = createdOrderId == null
          ? await widget.api.request('POST', '/api/orders', {
              'request_id': requestId,
              if (caseId.text.trim().isNotEmpty) 'case_id': caseId.text.trim(),
              'patient_name': name.text.trim(),
              'patient_mobile_number': mobile.text.trim(),
              'patient_email':
                  email.text.trim().isEmpty ? null : email.text.trim(),
              'clinic_patient_id': clinicPatientId.text.trim().isEmpty
                  ? null
                  : clinicPatientId.text.trim(),
              'clinician_id': clinicianId,
              'age': parsedAge,
              'clinic_id': clinicId,
              'notes': notes.text.trim(),
            })
          : null;
      createdOrderId ??= (result!['order'] as Map)['order_id'] as String;
      while (uploadedCount < attachments.length) {
        final index = uploadedCount;
        final checklistId = mappedFiles.entries
            .where((entry) => entry.value.contains(index))
            .map((entry) => entry.key)
            .firstOrNull;
        await widget.api
            .uploadOrderFile(createdOrderId!, attachments[index],
                checklistId: checklistId, category: 'scan');
        uploadedCount++;
      }
      if (sendForReview) {
        await widget.api.request('POST',
            '/api/orders/$createdOrderId/document-review/submit');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() => error = createdOrderId == null
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
                      controller: caseId,
                      decoration:
                          const InputDecoration(labelText: 'Case ID (optional)')),
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
                          labelText: 'Case notes/ Treatment Plan (optional)')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: saving || createdOrderId != null ? null : pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach photos, X-rays or scans')),
                  if (attachments.isNotEmpty)
                    Text('${attachments.length} file(s) selected'),
                  for (final item in mandatoryItems) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: saving || createdOrderId != null || attachments.isEmpty ? null : () => selectMappedFiles(item),
                        icon: const Icon(Icons.upload_file),
                        label: Text('Map ${item['label']}')),
                    Text('${(mappedFiles[item['id']] ?? []).length}/${item['min_files']} files mapped • ${(item['extensions'] as List).join(', ')}'),
                  ],
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
              onPressed: saving ? null : () => save(),
              child: Text(saving ? 'Submitting...' : 'Submit order')),
          FilledButton(
              onPressed: saving || !allMandatoryMapped
                  ? null
                  : () => save(sendForReview: true),
              child: const Text('Submit for planner review'))
        ]);
  }
}



class OrderDetailPage extends StatefulWidget {
  final Api api;
  final String orderId;
  final String role;
  final int? userId;
  final bool qcMode;
  final bool openIssues;
  const OrderDetailPage(
      {super.key,
      required this.api,
      required this.orderId,
      this.role = 'marketing',
      this.userId,
      this.openIssues = false,
      this.qcMode = false});
  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> with WidgetsBindingObserver {
  final issueText = TextEditingController();
  final issueExpansion = <String, bool>{};
  final openConversations = <String>{};
  final pendingReceipts = <String>{};
  final readThrough = <String, int>{};
  final issueScroll = ScrollController();
  Timer? issuePoll;
  bool polling = false;
  final replyDrafts = <String, TextEditingController>{};
  final issueFiles = <PlatformFile>[];
  String? savedIssueId;
  String? issueRecipient;
  bool get clinicUser => const {'clinician', 'clinic_admin'}.contains(widget.role);

  List<DropdownMenuItem<String>> recipientItems({bool raising = false}) => [
    for (final recipient in issueRecipients.entries)
      if ((!raising || recipient.key != widget.role) && (recipient.key != 'clinician' || order?['clinician_id'] != null))
        DropdownMenuItem(value: recipient.key, child: Text(recipient.value)),
  ];
  int? issueBatch;
  String? issueError;
  int? selectedBatch;
  int? get batchNumber => selectedBatch ?? order?['current_batch'] as int?;
  Map<String, dynamic>? order;
  List<dynamic> planners = [];
  String? error;
  final comment = TextEditingController();
  bool busy = false;
  bool get canManufacture => widget.role == 'production' || widget.role == 'admin';
  bool get canReviewQc => const {'admin', 'production', 'planning'}.contains(widget.role);
  bool get canReviewPlan =>
      const {'admin', 'marketing', 'clinic_admin', 'clinician'}
          .contains(widget.role);
  final Set<String> collapsedSections = {
    'patient',
    'clinic',
    'required_items',
    'scan_documents',
    'plan_documents',
    'comments',
    'issues',
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.openIssues) {
      collapsedSections.remove('issues');
      issuePoll = Timer.periodic(const Duration(seconds: 10), (_) => pollIssues());
    }
    issueScroll.addListener(() {
      if (openConversations.isNotEmpty && issuesVisible) setState(() {});
    });
    refresh();
    if (widget.role == 'admin' || widget.role == 'planning') loadPlanners();
  }

  Future<void> loadPlanners() async {
    try {
      final result = await widget.api.request('GET', '/api/planners');
      if (mounted)
        setState(() => planners = result['users'] as List<dynamic>);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    issuePoll?.cancel();
    issueScroll.dispose();
    comment.dispose();
    issueText.dispose();
    for (final draft in replyDrafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final result =
          await widget.api.request('GET', '/api/orders/${widget.orderId}');
      if (mounted)
        setState(() {
          final firstLoad = order == null;
          order = result['order'] as Map<String, dynamic>;
          if (firstLoad && widget.openIssues) {
            for (final issue in order!['issues'] as List) {
              if (issue['resolved_at'] == null && (issue['can_resolve'] == true ||
                  (issue['raised_to'] == null && const {'marketing', 'admin'}.contains(widget.role)))) {
                selectedBatch = issue['batch_number'] as int?;
                break;
              }
            }
          }
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
      if (path.endsWith('/status') && batchNumber != null) {
        body = {...?body, 'batch_number': batchNumber};
      }
      final result = await widget.api.request(method, path, body);
      if (mounted)
        setState(() {
          final previousCurrent = order?['current_batch'];
          order = result['order'] as Map<String, dynamic>;
          if (selectedBatch == previousCurrent) selectedBatch = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submitPlan() async {
    int? quantity;
    if (batchNumber == null) {
      quantity = await showDialog<int>(context: context, builder: (context) =>
        StatefulBuilder(builder: (context, update) => AlertDialog(
          title: const Text('Required aligner quantity'),
          content: TextField(autofocus: true, keyboardType: TextInputType.number,
              onChanged: (value) => update(() => quantity = int.tryParse(value))),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: (quantity ?? 0) > 0 ? () => Navigator.pop(context, quantity) : null,
                child: const Text('Submit plan'))])));
      if (quantity == null || !mounted) return;
    }
    await action('POST', '/api/orders/${widget.orderId}/status',
        {'status': 'plan_completed', if (quantity != null) 'aligner_quantity': quantity});
  }

  Future<void> approvePlan() async {
    final total = order?['aligner_quantity'] as int?;
    String mode = 'together';
    int? count;
    if (batchNumber == null && total != null) {
      final confirmed = await showDialog<bool>(context: context, builder: (context) =>
        StatefulBuilder(builder: (context, update) {
          final n = count ?? 0;
          final valid = n > 0 && n <= total;
          return AlertDialog(title: const Text('Approve dispatch plan'),
            content: SizedBox(width: 360, child: ListView(shrinkWrap: true, children: [
              Text('$total aligners'),
              DropdownButton<String>(value: mode, items: const [
                DropdownMenuItem(value: 'together', child: Text('Dispatch all together')),
                DropdownMenuItem(value: 'batches', child: Text('Dispatch in batches'))],
                onChanged: (value) => update(() {
                  mode = value!;
                  count = null;
                })),
              if (mode == 'batches') ...[
                TextField(keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Number of batches (1–$total)'),
                    onChanged: (value) => update(() => count = int.tryParse(value))),
                if (valid)
                  for (var i = 1; i <= n; i++)
                    Text('Batch $i/$n · ${total ~/ n + (i == n ? total % n : 0)} aligners')
              ]])),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: mode == 'together' || valid ? () => Navigator.pop(context, true) : null,
                  child: const Text('Approve'))]);
        }));
      if (confirmed != true || !mounted) return;
    }
    await action('POST', '/api/orders/${widget.orderId}/status', {
      'status': 'clinician_approved', if (batchNumber == null) 'dispatch_mode': mode,
      if (mode == 'batches') 'batch_count': count});
  }

  Future<void> changeAssignment(int? userId, {bool requireReason = false}) async {
    String? reason;
    if (requireReason) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reason for assignment change'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Enter a reason'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    }
    await action('POST', '/api/orders/${widget.orderId}/assignment', {
      'user_id': userId,
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> addFiles(String category) async {
    setState(() {
      busy = true;
      error = null;
    });
    var uploaded = false;
    try {
      final selection = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'stl']);
      for (final file in selection) {
        if (!mounted) return;
        await widget.api.uploadOrderFile(widget.orderId, file, category: category);
        uploaded = true;
      }
      if (uploaded && mounted) await refresh();
    } catch (e) {
      if (uploaded && mounted) await refresh();
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickIssueFiles() async {
    setState(() => busy = true);
    try {
      final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'stl']);
      if (mounted) setState(() => issueFiles.addAll(files));
    } catch (e) {
      if (mounted) setState(() => issueError = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> raiseIssue() async {
    final description = issueText.text.trim();
    if (description.isEmpty) {
      setState(() => issueError = 'Describe the issue before submitting.');
      return;
    }
    setState(() {
      busy = true;
      issueError = null;
    });
    try {
      if (savedIssueId == null) {
        final result = await widget.api.request('POST', '/api/orders/${widget.orderId}/issues', {
          if (batchNumber != null) 'batch_number': batchNumber,
          'text': description,
          if (!clinicUser) 'raised_to': issueRecipient,
        });
        if (!mounted) return;
        setState(() {
          issueBatch = batchNumber;
          selectedBatch = issueBatch;
          savedIssueId = result['issue_id'] as String;
          order = result['order'] as Map<String, dynamic>;
        });
      }
      while (issueFiles.isNotEmpty) {
        final result = await widget.api.uploadOrderFile(
            widget.orderId, issueFiles.first, issueId: savedIssueId);
        if (!mounted) return;
        setState(() {
          issueFiles.removeAt(0);
          order = result['order'] as Map<String, dynamic>;
        });
      }
      issueText.clear();
      setState(() { savedIssueId = null; issueRecipient = null; });
    } catch (e) {
      if (mounted) setState(() => issueError = savedIssueId == null
          ? e.toString()
          : 'Issue saved. Upload failed for ${issueFiles.first.name}. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget issueForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (savedIssueId == null && !clinicUser)
        DropdownButton<String>(value: issueRecipient, hint: const Text('Assign issue to'),
          items: recipientItems(raising: true), onChanged: busy ? null : (team) => setState(() => issueRecipient = team)),
      if (savedIssueId == null && clinicUser)
        const Text('Marketing or Admin will assign your issue.'),
      if (savedIssueId == null)
        TextField(controller: issueText, enabled: !busy, minLines: 2, maxLines: 4,
          maxLength: 5000, decoration: const InputDecoration(hintText: 'Describe the issue')),
      if (savedIssueId == null)
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
          onPressed: busy ? null : pickIssueFiles, icon: const Icon(Icons.upload_file),
          label: const Text('Upload documents'))),
      for (final file in issueFiles)
        ListTile(dense: true, title: Text(file.name), trailing: IconButton(
          tooltip: 'Remove file', icon: const Icon(Icons.close),
          onPressed: busy ? null : () => setState(() {
            issueFiles.remove(file);
            issueError = null;
            if (savedIssueId != null && issueFiles.isEmpty) {
              savedIssueId = null;
              issueText.clear();
            }
          }))),
      if (issueError != null)
        Text(issueError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      Align(alignment: Alignment.centerRight, child: FilledButton(
        onPressed: busy || (!clinicUser && issueRecipient == null && savedIssueId == null) ? null : raiseIssue,
        child: Text(savedIssueId == null ? 'Raise issue' : 'Retry upload'))),
    ],
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) pollIssues();
  }

  bool get issuesVisible => !collapsedSections.contains('issues') &&
      ModalRoute.of(context)?.isCurrent == true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> pollIssues() async {
    if (!mounted || !issuesVisible || busy || polling || pendingReceipts.isNotEmpty) return;
    polling = true;
    final previous = order;
    try {
      final result = await widget.api.request('GET', '/api/orders/${widget.orderId}');
      if (mounted && !busy && issuesVisible && identical(previous, order)) {
        setState(() => order = result['order'] as Map<String, dynamic>);
      }
    } catch (_) {
      // Keep the displayed order and retry on the next poll.
    } finally {
      polling = false;
    }
  }

  Future<void> markDisplayedReplies(Map issue, int index) async {
    final id = issue['id'] as String;
    if (!mounted || !issuesVisible || !openConversations.contains(id) ||
        (issue['unread'] ?? 0) == 0 || index < (readThrough[id] ?? 0) ||
        !pendingReceipts.add(id)) return;
    try {
      await widget.api.request('POST', '/api/orders/${widget.orderId}/issues/$id/read',
          {'through_reply_id': issue['replies'][index]['id']});
      readThrough[id] = index + 1;
    } catch (_) {
      // Retain the badge until the server confirms the receipt.
    } finally {
      pendingReceipts.remove(id);
    }
    if (readThrough[id] == index + 1) await pollIssues();
  }

  Widget unreadBadge(Map issue) => Text('${issue['unread']} unread',
      style: const TextStyle(color: Color(0xff187341), fontWeight: FontWeight.bold));

  Future<void> postIssueReply(String id, TextEditingController draft) async {
    final text = draft.text.trim();
    if (text.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request('POST',
          '/api/orders/${widget.orderId}/issues/$id/replies', {'text': text});
      if (!mounted) return;
      setState(() => order = result['order'] as Map<String, dynamic>);
      draft.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      await refresh();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget issueRow(Map item, Map data, int openCount) {
    final id = item['id'] as String;
    final isOpen = item['resolved_at'] == null;
    final expanded = issueExpansion[id] ?? (isOpen && openCount == 1);
    final target = item['raised_to'];
    final recipient = issueRecipients[target] ?? const {'cad': 'Planning', 'lab': 'Production'}[target] ?? 'Awaiting assignment';
    final canAssign = isOpen && target == null && const {'marketing', 'admin'}.contains(widget.role);
    return Column(key: ValueKey(id), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        leading: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
        title: Text('Issue #${item['number']} · ${isOpen ? 'Open' : 'Resolved'}'),
        trailing: (item['unread'] ?? 0) > 0 ? unreadBadge(item) : null,
        onTap: () => setState(() => issueExpansion[id] = !expanded),
      ),
      if (expanded) Padding(
        padding: const EdgeInsetsDirectional.only(start: 52),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item['text'] as String),
          subtitle: Text('${item['by']} → $recipient'),
          trailing: isOpen && item['can_resolve'] == true
              ? PopupMenuButton<bool>(enabled: !busy, tooltip: 'Resolve issue',
                  onSelected: (revision) => action('POST', '/api/orders/${widget.orderId}/issues/$id/resolve',
                      {'requires_plan_revision': revision}),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: false, child: Text('Clarification only · resume interrupted stage')),
                    PopupMenuItem(value: true, child: Text('Plan revision required')),
                  ], child: const Chip(label: Text('Resolve issue')))
              : null,
        ),
        if (canAssign)
          DropdownButton<String>(hint: const Text('Assign issue to'), items: recipientItems(),
            onChanged: busy ? null : (team) => action('POST', '/api/orders/${widget.orderId}/issues/$id/assign', {'raised_to': team})),
        if (item['resolved_by'] != null)
          Text('Resolved by ${item['resolved_by']} · ${item['requires_plan_revision'] == true ? 'Plan revision required' : 'Clarification only'}'),
        issueDiscussion(item, data),
        ]),
      ),
    ]);
  }

  Widget issueDiscussion(Map issue, Map data) {
    final id = issue['id'] as String;
    final documents = (data['documents'] as List).cast<Map>();
    final attachments = documents.where((doc) => doc['issue_id'] == id).toList();
    final replies = issue['replies'] as List? ?? const [];
    final draft = replyDrafts.putIfAbsent(id, () => TextEditingController());
    final label = Theme.of(context).textTheme.titleSmall;
    final conversationOpen = openConversations.contains(id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (attachments.isNotEmpty) ...[
      Text('Attachments (${attachments.length})', style: label),
      for (final file in attachments)
        ListTile(
          leading: const Icon(Icons.attach_file),
          title: Text(file['name'] as String),
          trailing: documentDeleteButton(data, file) ??
              const Icon(Icons.download_outlined),
          onTap: () => downloadFile(file),
        ),
      const SizedBox(height: 8),
      ],
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(conversationOpen ? Icons.expand_more : Icons.chevron_right),
        title: Text('Conversations', style: label),
        trailing: (issue['unread'] ?? 0) > 0 ? unreadBadge(issue) : null,
        onTap: () => setState(() {
          if (!openConversations.remove(id)) openConversations.add(id);
        }),
      ),
      if (conversationOpen) ...[
        for (final (index, reply) in replies.indexed)
          Builder(builder: (replyContext) {
            if ((issue['unread'] ?? 0) > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!replyContext.mounted) return;
                final box = replyContext.findRenderObject() as RenderBox?;
                final viewport = Scrollable.of(replyContext).context.findRenderObject() as RenderBox?;
                if (box == null || viewport == null || !box.hasSize || !viewport.hasSize) return;
                final bounds = box.localToGlobal(Offset.zero, ancestor: viewport) & box.size;
                if (bounds.top >= 0 && bounds.top < viewport.size.height &&
                    (bounds.bottom <= viewport.size.height || bounds.height > viewport.size.height)) {
                  markDisplayedReplies(issue, index);
                }
              });
            }
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(reply['text'] as String),
              subtitle: Text('${reply['by']} · ${activityTimestamp(reply['at'])}'),
            );
          }),
        if (issue['resolved_at'] == null) ...[
          TextField(
            key: PageStorageKey('issue-reply-$id'),
            controller: draft, enabled: !busy, minLines: 1, maxLines: 4,
            maxLength: 5000, decoration: const InputDecoration(hintText: 'Reply to this issue'),
          ),
          Align(alignment: Alignment.centerRight, child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: draft,
            builder: (_, value, __) => FilledButton(
              onPressed: busy || value.text.trim().isEmpty ? null : () => postIssueReply(id, draft),
              child: const Text('Post reply'),
            ),
          )),
        ],
      ],
      const Divider(),
    ]);
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
    final caseId = TextEditingController(text: current['case_id'] as String?);
    final age = TextEditingController(text: current['age']?.toString() ?? '');
    final notes =
        TextEditingController(text: current['notes'] as String? ?? '');
    final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Edit patient'),
                scrollable: true,
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
                          controller: caseId,
                          decoration: const InputDecoration(
                              labelText: 'Case ID (optional)')),
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
        'case_id': caseId.text.trim().isEmpty ? null : caseId.text.trim(),
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
    caseId.dispose();
    age.dispose();
    notes.dispose();
  }

  String stageEntryLabel(Map<String, dynamic> data) {
    final history = (data['history'] as List?) ?? [];
    for (final event in history.reversed) {
      if (event['status'] == data['status']) {
        final at = event['at'];
        if (DateTime.tryParse(at?.toString() ?? '') != null) {
          return 'Entered stage ${activityTimestamp(at)}';
        }
        break;
      }
    }
    return 'Stage entry time unavailable';
  }

  String activityTimestamp(Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (time == null) return 'Unknown time';
    final date = MaterialLocalizations.of(context).formatMediumDate(time);
    final clock = [time.hour, time.minute, time.second]
        .map((part) => part.toString().padLeft(2, '0'))
        .join(':');
    return '$date · $clock';
  }

  String activityStatus(Object value) =>
      _statuses[value] ?? value.toString().replaceAll('_', ' ');

  Future<void> showActivity() async {
    final path = '/api/orders/${widget.orderId}/activity';
    Future<Map<String, dynamic>>? request;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order activity'),
        content: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .55,
          child: FutureBuilder(
            future: request ??= widget.api.request('GET', path),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                    child: Text('Could not load order activity.'));
              }
              final result = snapshot.data;
              if (result == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = result['activity'] as List;
              if (entries.isEmpty) {
                return const Center(child: Text('No activity recorded.'));
              }
              return ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final entry = entries[index] as Map;
                  final actor = entry['actor'] as Map;
                  final details = entry['details'] as Map;
                  final previous = details['from_status'];
                  final next = details['to_status'];
                  final fields = details['fields'] as List?;
                  final items = details['items'] as List?;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry['action'].toString()),
                    subtitle: Text([
                      '${actor['name'] ?? 'Unknown user'} · '
                          '${activityTimestamp(entry['at'])}',
                      if (next != null)
                        previous == null
                            ? activityStatus(next)
                            : '${activityStatus(previous)} → '
                                '${activityStatus(next)}',
                      if (details['assignee'] != null)
                        'Assigned to ${details['assignee']}',
                      if (details['document'] != null)
                        details['document'].toString(),
                      if (details['item'] != null) details['item'].toString(),
                      if (items != null) items.join(', '),
                      if (fields != null)
                        fields
                            .map((field) =>
                                field.toString().replaceAll('_', ' '))
                            .join(', '),
                    ].join('\n')),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget documentPanel(Map<String, dynamic> data, String category) {
    final isScan = category == 'scan';
    final title = isScan ? 'Scan Documents' : 'Plan Documents';
    final documents = (data['documents'] as List).cast<Map>().where((document) {
      final assignedCategory = document['category'];
      return (document['issue_id'] as String? ?? '').isEmpty &&
          (assignedCategory == category || (isScan && assignedCategory == null));
    }).toList();
    return panel(
      '$title (${documents.length})',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final document in documents) documentTile(data, document),
          if (data['status'] != 'cancelled')
            OutlinedButton.icon(
              onPressed: busy ? null : () => addFiles(category),
              icon: const Icon(Icons.upload_file),
              label: Text(isScan ? 'Add scan documents' : 'Add plan documents'),
            ),
        ],
      ),
      section: '${category}_documents',
    );
  }

  Widget documentTile(Map<String, dynamic> data, Map document) {
    final unclassified = document['category'] == null;
    final path = '/api/orders/${widget.orderId}/documents/${document['id']}';
    return ListTile(
      title: Text(document['name'] as String),
      subtitle: Text('Uploaded by ${document['by']} (${document['role']})'
          '${unclassified ? ' • Needs classification' : ''}'),
      onTap: () => downloadFile(document),
      trailing: unclassified && widget.role == 'admin'
          ? PopupMenuButton<String>(
              enabled: !busy,
              tooltip: 'Classify document',
              onSelected: (category) =>
                  action('PATCH', '$path/category', {'category': category}),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'scan', child: Text('Assign to Scan Documents')),
                PopupMenuItem(value: 'plan', child: Text('Assign to Plan Documents')),
              ],
            )
          : documentDeleteButton(data, document),
    );
  }

  Widget? documentDeleteButton(Map data, Map document) {
    final canDelete = !['admin', 'clinician'].contains(widget.role) &&
        document['role'] == widget.role &&
        (document['checklist_id'] == null || document['checklist_id'] == '') &&
        !(data['checklist'] as List? ?? []).any(
            (item) => (item['document_ids'] as List).contains(document['id']));
    if (!canDelete) return null;
    return IconButton(
      tooltip: 'Delete',
      icon: const Icon(Icons.delete_outline),
      onPressed: busy
          ? null
          : () async {
              try {
                await widget.api.request('DELETE',
                    '/api/orders/${widget.orderId}/documents/${document['id']}');
                await refresh();
              } catch (e) {
                if (mounted) setState(() => error = e.toString());
              }
            },
    );
  }

  Widget panel(String title, Widget child, {String? section}) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (section == null)
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16))
            else
              InkWell(
                  onTap: () async {
                    final opening = collapsedSections.contains(section);
                    setState(() {
                        if (opening) {
                          collapsedSections.remove(section);
                        } else {
                          collapsedSections.add(section);
                        }
                    });
                    if (section == 'issues') {
                      issuePoll?.cancel();
                      if (opening) {
                        issuePoll = Timer.periodic(const Duration(seconds: 10), (_) => pollIssues());
                      }
                    }
                    if (section == 'issues' && opening && !busy) {
                      setState(() => busy = true);
                      try {
                        await refresh();
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    }
                  },
                  child: Row(children: [
                    Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16))),
                    Icon(collapsedSections.contains(section)
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up),
                  ])),
            if (section == null || !collapsedSections.contains(section)) ...[
              const Divider(),
              child,
            ]
          ])));
  @override
  Widget build(BuildContext context) {
    final number = batchNumber;
    final batches = order?['batches'] as List?;
    final data = number == null ? order : <String, dynamic>{
      ...order!, ...Map<String, dynamic>.from(batches![number - 1] as Map),
      if (number == order!['current_batch']) 'status': order!['status'],
      if (order!['status'] == 'issue_raised' && !const {'upcoming', 'qc_approved'}.contains(batches[number - 1]['status'])) 'status': 'issue_raised',
      'planner_assignment_open': const {'planning_in_progress', 'submitted', 'plan_completed', 'clinician_issues'}.contains(batches[number - 1]['status']),
      'issues': (order!['issues'] as List).where((i) => i['batch_number'] == number).toList(),
    };
    final openCount = (data?['issues'] as List? ?? []).where((i) => i['resolved_at'] == null).length;
    return Scaffold(
        appBar: AppBar(title: Text(widget.orderId)),
        body: data == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Text(error!))
            : ListView(controller: issueScroll, padding: const EdgeInsets.all(20), children: [
                if (number != null && batches != null) ...[
                  Text('${batches.where((b) => b['status'] == 'qc_approved').length}/${batches.length} batches complete'),
                  for (var i = 1; i <= batches.length; i++)
                    ListTile(selected: i == number, title: Text(batchLabel(data, i)),
                      onTap: busy || savedIssueId != null ? null : () => setState(() => selectedBatch = i)),
                ],
                if (data['aligner_quantity'] != null) Text("Total aligners: ${data['aligner_quantity']}"),
                if (order!['status'] == 'issue_raised')
                  const Text('Order on hold until all open issues are resolved.'),
                Text(data['patient_name'] as String,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                Text(_statuses[data['status']] ?? '${data['status']}'),
                if (widget.role == 'admin') Text(stageEntryLabel(data)),
                const SizedBox(height: 8),
                Text('Created on ${activityTimestamp(data['created_at'])}'),
                Text(
                    'Created by ${(data['created_by'] as Map?)?['name'] ?? 'Unknown user'}'),
                Text('Last modified ${activityTimestamp(data['updated_at'])}'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: showActivity,
                      icon: const Icon(Icons.history),
                      label: const Text('View activity')),
                ),
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
                    'patient & Casenotes',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Name: ${data['patient_name']}'),
                          Text('Patient ID: ${data['patient_id'] ?? '—'}'),
                          Text('Case ID: ${data['case_id'] ?? '—'}'),
                          Text(
                              'Clinic patient ID: ${data['clinic_patient_id'] ?? '—'}'),
                          Text(
                              'Mobile: ${data['patient_mobile_number'] ?? '—'}'),
                          Text('Email: ${data['patient_email'] ?? '—'}'),
                          Text('Age: ${data['age'] ?? '—'}'),
                          const Divider(height: 16, thickness: 1),
                          Text('Case notes: ${data['notes'] ?? ''}'),
                          if (widget.role == 'marketing')
                            TextButton.icon(
                                onPressed: busy ? null : editPatient,
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit patient')),
                        ]), section: 'patient'),
                panel(
                    'Clinic (view only)',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Name: ${(data['clinic'] as Map)['name']}'),
                          Text('Clinician: ${assignedClinicianName(data)}'),
                          Text(
                              'Contact: ${(data['clinic'] as Map)['contact']}'),
                          Text(
                              'Email: ${(data['clinic'] as Map)['email'] ?? '—'}'),
                          Text('Area: ${(data['clinic'] as Map)['area']}'),
                        ]), section: 'clinic'),
                if (data['checklist'] != null)
                  panel(
                      'Required items',
                      ScannerChecklist(
                          api: widget.api,
                          order: data,
                          role: widget.role,
                          onChanged: refresh),
                      section: 'required_items'),
                documentPanel(data, 'scan'),
                documentPanel(data, 'plan'),
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
                          if (!['admin', 'clinician'].contains(widget.role))
                            TextField(
                                controller: comment,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                    hintText: 'Write a comment')),
                          if (!['admin', 'clinician'].contains(widget.role))
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
                        ]), section: 'comments'),
                panel(
                    'Issues (${(data['issues'] as List).length})',
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in data['issues'] as List)
                            issueRow(item as Map, data, openCount),
                          if ((savedIssueId != null && issueBatch == number) ||
                              (savedIssueId == null && (number == null || number == order!['current_batch'] || order!['independent_batches'] == true) &&
                                !const {'cancelled', 'upcoming', 'qc_approved', 'manufacture_completed'}.contains(data['status'])))
                            issueForm(),
                        ]), section: 'issues'),
                if (number == null && ['marketing', 'clinic_admin', 'clinician']
                        .contains(widget.role) &&
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
                if (widget.role == 'admin' &&
                    data['status'] == 'submitted' &&
                    data['assigned_planner'] == null)
                  Wrap(spacing: 8, children: [
                    FilledButton(
                        onPressed: busy || widget.userId == null
                            ? null
                            : () => action(
                                'POST',
                                '/api/admin/orders/${widget.orderId}/assign',
                                {'user_id': widget.userId}),
                        child: const Text('Assign to me')),
                    PopupMenuButton<int>(
                      enabled: !busy && planners.isNotEmpty,
                      tooltip: 'Assign to planner',
                      onSelected: (id) => action(
                          'POST',
                          '/api/admin/orders/${widget.orderId}/assign',
                          {'user_id': id}),
                      itemBuilder: (_) => [
                        for (final planner in planners)
                          PopupMenuItem<int>(
                              value: planner['id'] as int,
                              child: Text(planner['name'].toString())),
                      ],
                      child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('Assign to planner')),
                    ),
                  ]),
                if (data['assigned_planner'] != null &&
                    data['planner_assignment_open'] == true &&
                    (widget.role == 'admin' ||
                        (widget.role == 'planning' && !widget.qcMode &&
                            data['status'] == 'planning_in_progress' &&
                            (data['assigned_planner'] as Map?)?['id'] == widget.userId)))
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (data['status'] == 'planning_in_progress' &&
                        (data['assigned_planner'] as Map?)?['id'] == widget.userId &&
                        (widget.role == 'admin' ||
                            (data['assigned_by'] as Map?)?['id'] == null ||
                            (data['assigned_by'] as Map?)?['id'] == widget.userId))
                      OutlinedButton(
                        onPressed: busy ? null : () => changeAssignment(null,
                            requireReason: widget.role == 'planning'),
                        child: const Text('Drop order'),
                      ),
                    if (widget.role == 'admin' ||
                        (data['assigned_by'] as Map?)?['id'] == null ||
                        (data['assigned_by'] as Map?)?['id'] == widget.userId)
                      PopupMenuButton<int>(
                        enabled: !busy && planners.isNotEmpty,
                        tooltip: 'Change assignee',
                        onSelected: (id) => changeAssignment(id,
                            requireReason: widget.role == 'planning'),
                        itemBuilder: (_) => [
                          if (widget.role == 'admin' && widget.userId != null &&
                              widget.userId != (data['assigned_planner'] as Map?)?['id'])
                            PopupMenuItem<int>(
                                value: widget.userId!, child: const Text('Assign to me')),
                          for (final planner in planners)
                            if (planner['id'] != (data['assigned_planner'] as Map?)?['id'])
                              PopupMenuItem<int>(
                                  value: planner['id'] as int,
                                  child: Text(planner['name'].toString())),
                        ],
                        child: const Chip(label: Text('Change assignee')),
                      ),
                    if (!widget.qcMode && data['status'] == 'planning_in_progress' &&
                        (data['assigned_planner'] as Map?)?['id'] == widget.userId)
                      FilledButton(
                          onPressed: busy
                              ? null
                              : submitPlan,
                          child: const Text('Plan completed')),
                  ]),
                if (canReviewPlan && data['status'] == 'plan_completed' &&
                    (data['revision_approval_required'] != true || data['can_approve_revision'] == true))
                  FilledButton(
                      onPressed: busy
                          ? null
                          : approvePlan,
                      child: const Text('Clinician approved')),
                if (canReviewPlan &&
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
                if (canManufacture &&
                    data['status'] == 'clinician_approved')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'manufacturing_in_process'}),
                      child: const Text('Start manufacturing')),
                if (canManufacture &&
                    data['status'] == 'manufacturing_in_process')
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => action(
                              'POST',
                              '/api/orders/${widget.orderId}/status',
                              {'status': 'manufactured'}),
                      child: const Text('Send to QC')),
                if (canReviewQc && data['status'] == 'manufactured')
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
