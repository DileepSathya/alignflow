import 'package:alignflow/admin_workspace.dart';
import 'package:alignflow/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OrderApi extends Api {
  final listQueries = <Uri>[];
  Map<String, dynamic>? submitted;

  @override
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? data]) async {
    final uri = Uri.parse(path);
    if (path == '/api/clinics') {
      return {
        'clinics': [
          {
            'id': 2,
            'clinic_name': 'Test clinic',
            'clinicians': [
              {'clinician_id': 3, 'name': 'Test clinician'}
            ]
          }
        ]
      };
    }
    if (path == '/api/admin/overview') {
      return {'total_orders': submitted == null ? 0 : 1};
    }
    if (uri.path == '/api/orders' && method == 'GET') {
      listQueries.add(uri);
      return {'orders': [], 'total': 0};
    }
    if (path == '/api/orders' && method == 'POST') {
      submitted = data;
      return {
        'order': {'order_id': 'ORD-000001'}
      };
    }
    throw StateError('Unexpected request: $method $path');
  }
}

void main() {
  testWidgets('admin submission refreshes the overview and filtered list',
      (tester) async {
    final api = _OrderApi();
    int? count;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminOrdersView(
                api: api,
                userId: 7,
                onOverviewChanged: (data) => count = data['total_orders'] as int))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'previous patient');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    final queriesBeforeCreation = api.listQueries.length;
    await tester.tap(find.text('Create order'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Patient');
    await tester.enterText(fields.at(1), '5551234');
    final clinician = find.widgetWithText(DropdownButtonFormField<int>, 'Clinician *');
    await tester.ensureVisible(clinician);
    await tester.tap(clinician);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test clinician').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit order'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.submitted?['clinic_id'], 2);
    expect(api.submitted?['clinician_id'], 3);
    expect(count, 1);
    expect(api.listQueries.length, queriesBeforeCreation + 1);
    expect(api.listQueries.last.queryParameters['q'], 'previous patient');
  });
}
