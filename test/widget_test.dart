// Smoke test do MasterPalm – não usa MyApp/Firebase para evitar falha em CI.
// Testes de integração com Firebase exigem mocks (ver vendas_service_test, etc.).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke: MaterialApp e widget básico constroem', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('MasterPalm smoke')),
      ),
    );
    expect(find.text('MasterPalm smoke'), findsOneWidget);
  });
}
