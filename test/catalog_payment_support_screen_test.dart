import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/catalog_payment_support_screen.dart';
import 'package:master_palm/services/catalog_payment_support_service.dart';

void main() {
  group('CatalogPaymentSupportRouteParams.merge', () {
    test('lê argumentos de rota e autoQuery', () {
      final p = CatalogPaymentSupportRouteParams.merge(
        routeArguments: <String, dynamic>{
          'lojaId': ' L1 ',
          'orderId': 'ord1',
          'autoQuery': 'true',
        },
      );
      expect(p.lojaId, 'L1');
      expect(p.orderId, 'ord1');
      expect(p.autoQuery, isTrue);
    });

    test('externalReference tem prioridade implícita no pedido', () {
      final p = CatalogPaymentSupportRouteParams.merge(
        routeArguments: {
          'externalReference': 'ext1',
          'orderId': 'ord1',
        },
      );
      expect(p.externalReference, 'ext1');
      expect(p.orderId, 'ord1');
    });

    test('ignora chaves desconhecidas', () {
      final p = CatalogPaymentSupportRouteParams.merge(
        routeArguments: {'lojaId': 'L', 'foo': 'bar'},
      );
      expect(p.lojaId, 'L');
    });
  });

  group('CatalogPaymentSupportService.buildPayload', () {
    test('paymentId sozinho', () {
      final p = CatalogPaymentSupportService.buildPayload(paymentId: '  pay1  ');
      expect(p, {'paymentId': 'pay1'});
    });

    test('lojaId + orderId', () {
      final p = CatalogPaymentSupportService.buildPayload(
        lojaId: 'L1',
        orderId: 'ord1',
      );
      expect(p, {'lojaId': 'L1', 'orderId': 'ord1'});
    });

    test('omitir vazios', () {
      final p = CatalogPaymentSupportService.buildPayload(
        lojaId: '',
        orderId: 'x',
      );
      expect(p, {'orderId': 'x'});
    });

    test('combinação paymentId + loja coerente com callable', () {
      final p = CatalogPaymentSupportService.buildPayload(
        lojaId: 'L',
        orderId: 'O',
        paymentId: 'P',
      );
      expect(p.length, 3);
    });
  });

  group('userFacingMessageForSnapshot', () {
    test('not_found', () {
      expect(
        userFacingMessageForSnapshot({'status': 'not_found'}),
        isNotNull,
      );
    });
    test('insufficient_data', () {
      expect(
        userFacingMessageForSnapshot({'status': 'insufficient_data'}),
        isNotNull,
      );
    });
    test('ok sem mensagem extra', () {
      expect(userFacingMessageForSnapshot({'status': 'ok'}), isNull);
    });
  });

  group('CatalogPaymentSupportScreen', () {
    testWidgets('empty state: mostra Como consultar antes da primeira busca', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
          ),
        ),
      );
      expect(find.textContaining('Como consultar'), findsOneWidget);
    });

    testWidgets('loading: botão desabilitado durante consulta', (tester) async {
      final c = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            fetcher: (_) => c.future,
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('field_loja')), 'L');
      await tester.enterText(find.byKey(const Key('field_order')), 'O1');
      await tester.tap(find.text('Consultar'));
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      c.complete(_okSnapshot());
      await tester.pumpAndSettle();
      expect(find.textContaining('lojaId'), findsWidgets);
    });

    testWidgets('copiar campo: botão de copiar aciona sem erro', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CatalogPaymentSupportScreen(bypassRootCheck: true),
        ),
      );
      expect(find.byTooltip('Copiar valor do campo'), findsNWidgets(3));
      await tester.enterText(find.byKey(const Key('field_loja')), 'lojaX');
      await tester.tap(find.byTooltip('Copiar valor do campo').first);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Limpar remove resultado e campos', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            fetcher: (_) async => _okSnapshot(),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('field_order')), 'O');
      await tester.tap(find.text('Consultar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Resumo'), findsOneWidget);

      await tester.tap(find.text('Limpar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Como consultar'), findsOneWidget);
      expect(find.textContaining('Resumo'), findsNothing);
      final loja = tester.widget<TextField>(find.byKey(const Key('field_loja')));
      expect(loja.controller?.text ?? '', '');
    });

    testWidgets('argumentos iniciais preenchem campos', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            routeArguments: {
              'lojaId': 'L9',
              'orderId': 'P99',
              'paymentId': 'pay9',
            },
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('field_loja'))).controller?.text,
        'L9',
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('field_order'))).controller?.text,
        'P99',
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('field_payment'))).controller?.text,
        'pay9',
      );
    });

    testWidgets('autoQuery dispara uma consulta quando payload válido', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            routeArguments: {
              'lojaId': 'L',
              'orderId': 'O',
              'autoQuery': 'true',
            },
            fetcher: (_) async {
              calls++;
              return _okSnapshot();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('Resumo'), findsOneWidget);
    });

    testWidgets('not_found: mensagem objetiva', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            fetcher: (_) async => {
              'status': 'not_found',
              'reason': 'pedido não encontrado',
            },
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('field_order')), 'x');
      await tester.tap(find.text('Consultar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pedido não encontrado'), findsOneWidget);
    });

    testWidgets('timeline renderiza eventos', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            fetcher: (_) async => {
              'status': 'ok',
              'summary': {
                'lojaId': 'L',
                'orderId': 'O',
                'externalReference': 'O',
                'paymentId': 'P',
                'provider': 'mercadopago',
                'tipo': null,
                'statusLocal': null,
                'paymentStatusMpDoc': null,
                'totalExpected': null,
                'createdAtMs': null,
                'paidAtMs': null,
                'updatedAtMs': null,
              },
              'indicators': <String, dynamic>{},
              'timeline': [
                {'event': 'webhook_processed_record', 'atMs': 5000},
              ],
              'webhookProcessed': {'exists': false},
              'validationRejection': {'recordExists': false},
            },
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('field_order')), 'O');
      await tester.tap(find.text('Consultar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('webhook_processed_record'), findsOneWidget);
    });

    testWidgets('UI não exibe campo raw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPaymentSupportScreen(
            bypassRootCheck: true,
            fetcher: (_) async => {
              'status': 'ok',
              'summary': {
                'lojaId': 'L',
                'orderId': 'O',
                'externalReference': 'O',
                'paymentId': 'P',
                'provider': 'mercadopago',
              },
              'indicators': <String, dynamic>{},
              'timeline': <dynamic>[],
              'webhookProcessed': {'exists': false},
              'validationRejection': {'recordExists': false},
              'paymentsAudit': {'raw': {'secret': true}, 'status': 'approved'},
            },
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('field_order')), 'O');
      await tester.tap(find.text('Consultar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('secret'), findsNothing);
    });
  });
}

Map<String, dynamic> _okSnapshot() => {
      'status': 'ok',
      'summary': {
        'lojaId': 'L',
        'orderId': 'O1',
        'externalReference': 'O1',
        'paymentId': 'P1',
        'provider': 'mercadopago',
        'tipo': 'pix',
        'statusLocal': 'paid',
        'paymentStatusMpDoc': 'approved',
        'totalExpected': 10.0,
        'createdAtMs': 1000,
        'paidAtMs': 2000,
        'updatedAtMs': 2000,
      },
      'indicators': {
        'hasProviderSuccess': true,
        'hasPersistSuccess': true,
        'hasPersistError': false,
        'hasWebhookProcessed': true,
        'hasWebhookApproved': true,
        'hasValidationFailure': false,
        'hasDuplicateIgnored': false,
        'hasMaterialNewEffect': true,
        'hasNoopAlreadyPaid': false,
        'webhookProcessedOutcome': 'applied_order_paid_new_effect',
      },
      'timeline': [
        {'event': 'order_document_created', 'atMs': 1000},
      ],
      'webhookProcessed': {
        'exists': true,
        'status': 'done',
        'effectiveOutcome': 'applied_order_paid_new_effect',
        'processedAtMs': 1500,
      },
      'validationRejection': {'recordExists': false},
    };
