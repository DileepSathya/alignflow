import 'package:alignflow/role_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all roles use the same desktop navigation width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: RoleShell(
      sidebar: Text('Role navigation'), content: Text('Role content'), title: 'Orders')));
    expect(find.text('Role navigation'), findsOneWidget);
    expect(find.text('Role content'), findsOneWidget);
    expect(tester.getSize(find.ancestor(of: find.text('Role navigation'), matching: find.byType(SizedBox)).first).width,
      RoleShell.navigationWidth);
  });
  testWidgets('shared mobile drawer opens for role navigation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: RoleShell(
      sidebar: Text('Role navigation'), content: Text('Role content'), title: 'Orders')));
    expect(find.text('Role navigation'), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Role navigation'), findsOneWidget);
  });
}
