import 'package:alignflow/api.dart';
import 'package:alignflow/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _IssueApi extends Api {
  int reads = 0;
  bool firstResolved = false;
  bool secondResolved = false;
  bool batches = false;
  int unread = 0;
  String? postedPath;
  String? reply;

  @override
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? data]) async {
    if (method == 'GET') reads++;
    if (path.endsWith('/read')) {
      expect(data!['through_reply_id'], 'r1');
      unread = 0;
      return {'read_through': 1};
    }
    if (method == 'POST') {
      postedPath = path;
      reply = data!['text'] as String;
    }
    return {
      'order': {
        'patient_name': 'Test patient', 'clinic': {}, 'history': [],
        'status': 'clinician_issues', 'comments': [],
        if (batches) ...{
          'current_batch': 2,
          'batches': [{'status': 'qc_approved'}, {'status': 'clinician_issues'}],
        },
        'issues': [
          {'id': 'a', 'number': 1, 'text': 'First issue', 'batch_number': 1, 'resolved_at': firstResolved ? 'done' : null},
          {'id': 'b', 'number': 2, 'text': 'Second issue', 'batch_number': 2,
            'resolved_at': secondResolved ? 'done' : null, 'unread': unread, 'replies': [
            {'id': 'r1', 'text': 'Check scan', 'by': 'Planner'},
            if (reply != null) {'text': reply, 'by': 'Reviewer'}
          ]},
        ],
        'documents': [
          if (reads > 1) {'id': 'pdf', 'issue_id': 'a', 'name': 'Scan.pdf'},
        ],
      },
    };
  }
}

void main() {
  testWidgets('opening issues refreshes attachments and replies target the selected issue', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _IssueApi();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: OrderDetailPage(api: api, orderId: 'ORD-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issues (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Scan.pdf'), findsNothing);
    expect(find.text('Conversations'), findsNothing);
    await tester.tap(find.text('Issue #1 · Open'));
    await tester.tap(find.text('Issue #2 · Open'));
    await tester.pumpAndSettle();
    expect(find.text('Scan.pdf'), findsOneWidget);
    expect(find.text('1 unread'), findsNothing);
    api.unread = 1;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('1 unread'), findsNWidgets(2));
    expect(find.text('Post reply'), findsNothing);
    await tester.tap(find.text('Conversations').last);
    await tester.pumpAndSettle();
    expect(find.text('1 unread'), findsNothing);
    expect(find.text('Attachments (0)'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Reply to this issue'), 'Review complete');
    await tester.pump();
    await tester.tap(find.text('Post reply').last);
    await tester.pumpAndSettle();
    expect(api.postedPath, '/api/orders/ORD-1/issues/b/replies');
    expect(find.text('Conversations'), findsNWidgets(2));
    await tester.tap(find.text('Conversations').last);
    await tester.pumpAndSettle();
    expect(find.text('Review complete'), findsNothing);
    expect(find.text('Post reply'), findsNothing);
    await tester.tap(find.text('Conversations').last);
    await tester.pumpAndSettle();
    expect(find.text('Review complete'), findsOneWidget);

    api.firstResolved = true;
    api.batches = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Issue #2 · Open'), findsOneWidget);
    expect(find.text('Issue #1 · Resolved'), findsNothing);
    await tester.tap(find.textContaining('Batch 1/2'));
    await tester.pumpAndSettle();
    expect(find.text('Issue #1 · Resolved'), findsOneWidget);
    expect(find.text('Issue #2 · Open'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only the single open issue expands and resolved threads are read-only', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _IssueApi()..firstResolved = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: OrderDetailPage(api: api, orderId: 'ORD-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Issues (2)'));
    await tester.pumpAndSettle();
    expect(find.text('First issue'), findsNothing);
    expect(find.text('Second issue'), findsOneWidget);
    api.secondResolved = true;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Conversations'), findsNothing);
    await tester.tap(find.text('Issue #2 · Resolved'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversations'));
    await tester.pumpAndSettle();
    expect(find.text('Check scan'), findsOneWidget);
    expect(find.text('Post reply'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
