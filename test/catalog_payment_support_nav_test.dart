import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/catalog_payment_support_screen.dart';
import 'package:master_palm/utils/catalog_payment_support_nav.dart';

void main() {
  test('mensagem de cópia única e estável', () {
    expect(kCatalogPaymentSupportCopyMessage, 'ID copiado');
  });

  testWidgets('showCatalogPaymentSupportCopyFeedback usa mensagem padronizada', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showCatalogPaymentSupportCopyFeedback(ctx),
              child: const Text('tap'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(kCatalogPaymentSupportCopyMessage), findsOneWidget);
  });

  testWidgets('openCatalogPaymentSupport envia arguments na rota', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (_) => Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => openCatalogPaymentSupport(
                    ctx,
                    lojaId: 'L1',
                    orderId: 'O1',
                    autoQuery: false,
                  ),
                  child: const Text('go'),
                ),
              ),
          '/catalog_payment_support': (ctx) => CatalogPaymentSupportScreen(
                routeArguments: ModalRoute.of(ctx)?.settings.arguments,
                bypassRootCheck: true,
              ),
        },
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const Key('field_loja'))).controller?.text,
      'L1',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('field_order'))).controller?.text,
      'O1',
    );
  });

  testWidgets('helper não altera backend — só navegação', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (_) => Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => openCatalogPaymentSupport(ctx),
                  child: const Text('open'),
                ),
              ),
          '/catalog_payment_support': (_) => const CatalogPaymentSupportScreen(
                bypassRootCheck: true,
              ),
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogPaymentSupportScreen), findsOneWidget);
  });
}
