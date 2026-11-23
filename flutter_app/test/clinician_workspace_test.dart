import 'package:alignflow/api.dart';
import 'package:alignflow/clinic_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ClinicianApi extends Api {
  Map<String, dynamic>? submitted;

  @override
  Future<Map<String, dynamic>> request(String method, String path,
      [Map<String, dynamic>? data]) async {
    switch (Uri.parse(path).path) {
      case '/api/my-clinic':
        return {
          'clinic': {
            'id': 2,
            'clinic_name': 'Test clinic',
            'clinicians': [
              {'clinician_id': 9, 'name': 'Doctor'}
            ]
          }
        };
      case '/api/my-clinic/overview':
        return {
          'counts': {}, 'months': List.filled(12, 0), 'year': 2026,
          'approvals': [], 'missing': [], 'recent': []
        };
      case '/api/orders':
        if (method == 'POST') {
          submitted = data;
          return {'order': {'order_id': 'ORD-1'}};
        }
        return {'orders': [], 'total': 0};
      default:
        throw StateError('Unexpected request $method $path');
    }
  }
}

void main() {
  testWidgets('clinician opens personal dashboard and creates an assigned order',
      (tester) async {
    final api = _ClinicianApi();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ClinicWorkspace(
      api: api, user: const {'role': 'clinician', 'username': 'doctor'}, onLogout: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('My dashboard'), findsOneWidget);
    expect(find.text('Add clinician'), findsNothing);
    expect(find.text('Clinicians'), findsNothing);
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create order'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Patient');
    await tester.enterText(fields.at(1), '5551234');
    await tester.tap(find.text('Submit order'));
    await tester.pumpAndSettle();
    expect(api.submitted?['clinic_id'], 2);
    expect(api.submitted?['clinician_id'], 9);
  });
}
