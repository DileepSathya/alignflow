import 'package:alignflow/api.dart';
import 'package:alignflow/scanner_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> order({bool verified = false, bool selected = false}) =>
      {
        'order_id': 'ORD-000001',
        'status': 'scanner_review',
        'documents': selected
            ? [
                {'id': 'file-1', 'name': 'upper-arch.stl'}
              ]
            : [],
        'checklist': [
          {
            'id': 'custom',
            'label': 'Developer configured item',
            'mandatory': true,
            'min_files': 1,
            'extensions': ['.stl'],
            'allow_text': false,
            'document_ids': selected ? ['file-1'] : [],
            'text': '',
            'verified': verified,
            'waiver': null
          }
        ],
      };
  Future<void> show(WidgetTester tester, String role,
      {bool verified = false, bool selected = false}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ScannerChecklist(
                    api: Api(),
                    order: order(verified: verified, selected: selected),
                    role: role,
                    onChanged: () async {})))));
  }

  testWidgets('renders configured items and blocks incomplete submission',
      (tester) async {
    await show(tester, 'scanner');
    expect(find.text('Developer configured item *'), findsOneWidget);
    expect(find.text('Upload missing files'), findsNothing);
    final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit for planner review'));
    expect(approve.onPressed, isNull);
  });
  testWidgets('clinician can submit mapped documents', (tester) async {
    await show(tester, 'clinic_admin', selected: true);
    final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit for planner review'));
    expect(approve.onPressed, isNotNull);
  });
  testWidgets('selected files appear by name under the required item',
      (tester) async {
    await show(tester, 'scanner', selected: true);
    expect(find.text('• upper-arch.stl'), findsOneWidget);
  });
  testWidgets('marketing can select but cannot verify or approve',
      (tester) async {
    await show(tester, 'marketing');
    expect(find.text('Upload missing files'), findsNothing);
    expect(find.text('Approve and send to Planning'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
  });
  testWidgets('only admin sees authorize exception', (tester) async {
    await show(tester, 'admin');
    expect(find.text('Authorize exception'), findsOneWidget);
    expect(find.text('Upload missing files'), findsNothing);
  });
}
