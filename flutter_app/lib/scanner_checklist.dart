import 'package:flutter/material.dart';
import 'api.dart';

/// Renders the order's stored configuration, never a hardcoded checklist.
class ScannerChecklist extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> order;
  final String role;
  final Future<void> Function() onChanged;
  const ScannerChecklist(
      {super.key,
      required this.api,
      required this.order,
      required this.role,
      required this.onChanged});
  @override
  State<ScannerChecklist> createState() => _ScannerChecklistState();
}

class _ScannerChecklistState extends State<ScannerChecklist> {
  bool busy = false;
  String? error;
  List get items => widget.order['checklist'] as List? ?? [];
  bool get pending =>
      ['scanner_review', 'scanner_missing'].contains(widget.order['status']);
  bool get canEdit => pending && ['marketing', 'scanner'].contains(widget.role);
  String get base => '/api/orders/${widget.order['order_id']}';
  bool ready(Map item) => item['waiver'] != null || item['verified'] == true;

  Future<void> run(Future<void> Function() task) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      await widget.onChanged();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> ask(String title) async {
    var text = '';
    final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: TextField(
                    onChanged: (value) => text = value,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Reason / instructions')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (text.trim().isNotEmpty) {
                          Navigator.pop(context, text.trim());
                        }
                      },
                      child: const Text('Save'))
                ]));
    return result;
  }

  Future<void> edit(Map item) async {
    final selected = Set<String>.from(item['document_ids'] as List);
    var text = item['text'] as String? ?? '';
    final docs = (widget.order['documents'] as List)
        .where((d) => (item['extensions'] as List).any((ext) =>
            (d['name'] as String).toLowerCase().endsWith(ext as String)))
        .toList();
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text(item['label'] as String),
                    content: SizedBox(
                        width: 480,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(
                                  'Select at least ${item['min_files']} file(s). Earlier uploads remain available.'),
                              for (final doc in docs)
                                CheckboxListTile(
                                    value: selected.contains(doc['id']),
                                    title: Text(doc['name'] as String),
                                    subtitle:
                                        Text('${doc['by']} • ${doc['at']}'),
                                    onChanged: (value) => update(() {
                                          if (value == true) {
                                            selected.add(doc['id'] as String);
                                          } else {
                                            selected.remove(doc['id']);
                                          }
                                        })),
                              if (item['allow_text'] == true)
                                TextFormField(
                                    initialValue: text,
                                    onChanged: (value) => text = value,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                        labelText: 'Treatment requirements')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Save for review'))
                    ])));
    if (save == true) {
      await run(() async {
        await widget.api.request('PUT', '$base/checklist/${item['id']}', {
          'document_ids': selected.toList(),
          'text': text,
          'verified': false
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = items.where((i) => ready(i as Map)).length;
    final approved = widget.order['scanner_approval'] as Map?;
    final request = widget.order['missing_request'] as Map?;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Required items — $completed of ${items.length}',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Text(
                      'Add files in Documents below, select them for each item, then verify the checklist.'),
                  if (request != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                            'Requested by ${request['by']}: ${request['note']}\n${(request['items'] as List).join(', ')}')),
                  if (approved != null)
                    Text('Approved by ${approved['by']} at ${approved['at']}'),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (busy) const LinearProgressIndicator(),
                  for (final item in items)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Checkbox(
                                    value: ready(item as Map),
                                    onChanged: !busy &&
                                            pending &&
                                            widget.role == 'scanner' &&
                                            item['waiver'] == null
                                        ? (value) => run(() async {
                                              await widget.api.request(
                                                  'PUT',
                                                  '$base/checklist/${item['id']}',
                                                  {
                                                    'document_ids':
                                                        item['document_ids'],
                                                    'text': item['text'],
                                                    'verified': value
                                                  });
                                            })
                                        : null),
                                Expanded(
                                    child: Text(
                                        '${item['label']}${item['mandatory'] == true ? " *" : " (optional)"}')),
                                Text(item['waiver'] != null
                                    ? 'Exception'
                                    : item['verified'] == true
                                        ? 'Verified'
                                        : ((item['document_ids'] as List)
                                                        .length >=
                                                    (item['min_files']
                                                        as int) ||
                                                (item['text'] as String)
                                                    .isNotEmpty)
                                            ? 'Awaiting review'
                                            : 'Missing'),
                              ]),
                              Text(
                                  '${(item['document_ids'] as List).length} / ${item['min_files']} files • ${(item['extensions'] as List).join(', ')}'),
                              for (final document
                                  in (widget.order['documents'] as List).where(
                                      (document) =>
                                          (item['document_ids'] as List)
                                              .contains(document['id'])))
                                Padding(
                                    padding:
                                        const EdgeInsets.only(left: 12, top: 4),
                                    child: Text('• ${document['name']}')),
                              if ((item['text'] as String).isNotEmpty)
                                Text(item['text'] as String),
                              if (item['verified_by'] != null &&
                                  item['verified'] == true)
                                Text('Verified by ${item['verified_by']}'),
                              if (item['waiver'] != null)
                                Text(
                                    'Exception: ${item['waiver']['reason']} — ${item['waiver']['by']}'),
                              Wrap(spacing: 8, children: [
                                if (canEdit)
                                  TextButton(
                                      onPressed: busy ? null : () => edit(item),
                                      child: const Text(
                                          'Select files / edit instructions')),
                                if (pending && widget.role == 'admin')
                                  TextButton(
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              final reason = await ask(
                                                  'Authorize exception: ${item['label']}');
                                              if (reason != null) {
                                                await run(() async {
                                                  await widget.api.request(
                                                      'PUT',
                                                      '$base/checklist/${item['id']}',
                                                      {
                                                        'waiver_reason': reason
                                                      });
                                                });
                                              }
                                            },
                                      child: const Text('Authorize exception')),
                              ]),
                              const Divider(),
                            ])),
                  if (pending && widget.role == 'scanner')
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      FilledButton(
                          onPressed: busy ||
                                  items.any((i) =>
                                      i['mandatory'] == true &&
                                      !ready(i as Map))
                              ? null
                              : () => run(() async {
                                    await widget.api.request(
                                        'POST', '$base/scanner/approve');
                                  }),
                          child: const Text('Approve and send to Planning')),
                      OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final note = await ask(
                                      'Request missing items from Marketing');
                                  if (note != null) {
                                    await run(() async {
                                      await widget.api.request(
                                          'POST',
                                          '$base/scanner/request-missing',
                                          {'note': note});
                                    });
                                  }
                                },
                          child: const Text('Request missing items')),
                    ]),
                  if ((widget.order['scanner_history'] as List? ?? [])
                      .isNotEmpty)
                    ExpansionTile(
                        title: const Text('Scanner review history'),
                        children: [
                          for (final event
                              in widget.order['scanner_history'] as List)
                            ListTile(
                                title:
                                    Text('${event['action']} — ${event['by']}'),
                                subtitle: Text('${event['at']}')),
                        ]),
                ])));
  }
}
