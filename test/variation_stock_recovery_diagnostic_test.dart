import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/sync_queue_recovery_mode.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:master_palm/services/variation_stock_recovery_diagnostic.dart';

void main() {
  tearDown(() {
    SyncQueueRecoveryMode.resetForTests();
  });

  group('VariationStockRecoveryDiagnostic guards', () {
    test('RECOVERY_GUARD: unavailable in normal mode', () {
      expect(SyncQueueRecoveryMode.isActive, isFalse);
      final svc = VariationStockRecoveryDiagnosticService(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => svc.assertRecoveryModeActive(),
        throwsA(isA<VariationStockDiagnosticGuardException>()),
      );
    });

    test('RECOVERY_GUARD: available after recovery activation', () {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      expect(SyncQueueRecoveryMode.isActive, isTrue);
      expect(SyncQueueRecoveryMode.allowsAutomaticQueueProcessing, isFalse);
      final svc = VariationStockRecoveryDiagnosticService(
        httpClient: MockClient((_) async => http.Response(
              '{"buildId":"web-server-test"}',
              200,
            )),
      );
      expect(() => svc.assertRecoveryModeActive(), returnsNormally);
    });
  });

  group('VariationStockRecoveryDiagnostic extraction', () {
    test('VARIATION_MISMATCH: zero qty + positive stock map + price key', () {
      final p = VariationStockRecoveryDiagnosticBuilder.fromProdutoFields(
        productId: 'prod_a',
        nome: 'Brinco Teste',
        stockRevision: 3,
        usaVariacoes: true,
        baseEstoque: 0,
        variacoes: {
          'P': {'sem-cor': 0},
          'M': {'sem-cor': 0},
        },
        estoquePorTamanho: {'P': 5, 'M': 2},
        precoPorTamanho: {'P': 32.0, 'M': 41.0, 'G': 50.0},
      );
      expect(p.hasZeroVariationQty, isTrue);
      expect(p.hasStockMapWithPositiveQty, isTrue);
      expect(p.hasPriceKeyWithoutStockKey, isTrue);
      expect(p.representationMismatch, isTrue);
      expect(p.precoPorTamanhoKeys, containsAll(['G', 'M', 'P']));
      // price values excluded from export shape
      expect(p.toJson().containsKey('precoPorTamanho'), isFalse);
      expect(p.toJson()['precoPorTamanhoKeys'], isA<List>());
    });

    test('LOCAL_QTY_EXPORT: positive quantities preserved exactly', () {
      final p = VariationStockRecoveryDiagnosticBuilder.fromProdutoFields(
        productId: 'prod_b',
        nome: 'Anel Rubi',
        stockRevision: 1,
        usaVariacoes: true,
        baseEstoque: 7,
        variacoes: {
          'unico': {
            'RUBI': 4,
            'TURQUESA': 3,
          },
        },
        estoquePorTamanho: {'unico': 7},
        precoPorTamanho: null,
      );
      expect(p.variations.map((c) => c.quantity).toList(), containsAll([4, 3]));
      expect(p.hasZeroVariationQty, isFalse);
      expect(p.baseEstoque, 7);
    });

    test('STALE_INTENT: expectedRevision < local flags without executing',
        () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final produto = Produto(
        nome: 'Produto Stale',
        custoReal: 0,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 0,
        precoUnitario: 10,
        categoria: 'x',
        dataEntrada: DateTime.utc(2026, 1, 1),
        descricao: '',
        imagens: const [],
        publicadoNoCatalogo: false,
        slug: 'prod-stale',
        tamanhos: const ['P'],
        subcategoria: '',
        estoquePorTamanho: const {'P': 0},
        lojaId: 'loja_test',
        idFirebase: 'prod_stale',
      )
        ..variacoes = {
          'P': {'sem-cor': 0},
        }
        ..stockRevision = 5;

      final queueItem = SyncQueueItem(
        id: 'q1',
        type: SyncOperationType.upsertProduto,
        lojaId: 'loja_test',
        boxName: 'produtos_loja_test',
        entityKey: 42,
        createdAt: 1000,
        stockIntentJson: jsonEncode({
          'operationId': 'op_test',
          'kind': 'replace',
          'items': [
            {'productId': 'prod_stale', 'expectedRevision': 2},
          ],
          'editorial': {'nome': 'should_not_appear_as_customer_field'},
          'definition': {
            'variacoes': {
              'P': {'sem-cor': 0},
            },
          },
          'expectedRevision': 2,
        }),
      );

      final svc = VariationStockRecoveryDiagnosticService(
        httpClient: MockClient(
          (_) async => http.Response('{"buildId":"web-21ec609"}', 200),
        ),
        clientWebVersion: 'web-local-test',
      );

      final snap = await svc.generate(
        storeId: 'loja_test',
        productsOverride: [produto],
        queueOverride: [queueItem],
        baseUri: Uri.parse('https://app.mastepalm.com.br/'),
      );

      expect(snap.recoveryMode, isTrue);
      expect(snap.clientWebVersion, 'web-local-test');
      expect(snap.serverWebVersion, 'web-21ec609');
      expect(snap.queue, isNotEmpty);
      final q = snap.queue.first;
      expect(q.productId, 'prod_stale');
      expect(q.expectedStockRevision, 2);
      expect(q.localStockRevision, 5);
      expect(q.staleVsLocalRevision, isTrue);
      expect(q.kind, 'replace');
      expect(q.operationId, 'op_test');
      final pretty = snap.toPrettyJson();
      expect(pretty.contains('should_not_appear_as_customer_field'), isFalse);
      expect(pretty.contains('editorial'), isFalse);
    });
  });

  group('redaction', () {
    test('PII_REDACTION / AUTH_SECRET_REDACTION', () {
      final dirty = {
        'ok': true,
        'email': 'a@b.com',
        'token': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'access_token': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'clienteNome': 'Maria',
        'nested': {
          'refreshToken': 'cccccccccccccccccccccccccccccccc',
          'quantity': 3,
        },
        'jwt':
            'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturepartlongenough',
      };
      final clean =
          VariationStockRecoveryDiagnosticBuilder.redactSecrets(dirty)
              as Map<String, dynamic>;
      expect(clean.containsKey('email'), isFalse);
      expect(clean.containsKey('token'), isFalse);
      expect(clean.containsKey('access_token'), isFalse);
      expect(clean.containsKey('clienteNome'), isFalse);
      expect(clean['nested'], isA<Map>());
      final nested = clean['nested'] as Map;
      expect(nested.containsKey('refreshToken'), isFalse);
      expect(nested['quantity'], 3);
      expect(clean['jwt'], '[REDACTED]');
      expect(clean['ok'], isTrue);
    });
  });

  group('generate read-only contract', () {
    test('DIAGNOSTIC_READ_ONLY / QUEUE_SUPPRESSION: no mutation APIs called',
        () async {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      var httpGets = 0;
      final svc = VariationStockRecoveryDiagnosticService(
        httpClient: MockClient((req) async {
          httpGets++;
          expect(req.method, 'GET');
          return http.Response('{"buildId":"web-21ec609"}', 200);
        }),
        clientWebVersion: 'web-fixture',
      );

      final produto = Produto(
        nome: 'Fixture',
        custoReal: 0,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 1,
        quantidade: 0,
        precoUnitario: 1,
        categoria: 'c',
        dataEntrada: DateTime.utc(2026, 1, 1),
        descricao: '',
        imagens: const [],
        publicadoNoCatalogo: false,
        slug: 'fix',
        tamanhos: const ['P'],
        subcategoria: '',
        estoquePorTamanho: const {'P': 0},
        lojaId: 'loja_x',
        idFirebase: 'fix',
      )..variacoes = {
          'P': {'sem-cor': 0},
        };

      final snap = await svc.generate(
        storeId: 'loja_x',
        productsOverride: [produto],
        queueOverride: const [],
        baseUri: Uri.parse('https://app.mastepalm.com.br/'),
      );
      expect(snap.summary.variableProductCount, 1);
      expect(snap.summary.zeroQtyProductCount, 1);
      expect(httpGets, 1); // version.json only
      expect(SyncQueueRecoveryMode.allowsAutomaticQueueProcessing, isFalse);
    });
  });

  group('iOS export text', () {
    test('IOS_EXPORT_FALLBACK: pretty JSON is clipboard-ready UTF-8 text', () {
      SyncQueueRecoveryMode.activateForSession(source: 'test');
      final p = VariationStockRecoveryDiagnosticBuilder.fromProdutoFields(
        productId: 'p1',
        nome: 'Test',
        stockRevision: 1,
        usaVariacoes: true,
        baseEstoque: 0,
        variacoes: {
          'P': {'sem-cor': 0},
        },
        estoquePorTamanho: const {},
        precoPorTamanho: const {'P': 10},
      );
      final snap = VariationStockRecoveryDiagnosticSnapshot(
        diagnosticVersion: '1.0.0',
        capturedAtUtc: '2026-09-18T00:00:00Z',
        recoveryMode: true,
        clientWebVersion: 'web-test',
        serverWebVersion: 'web-21ec609',
        storeId: 'loja',
        products: [p],
        queue: const [],
        summary: const VariationStockDiagnosticSummary(
          variableProductCount: 1,
          zeroQtyProductCount: 1,
          missingQtyProductCount: 0,
          representationMismatchCount: 0,
          priceKeyWithoutStockKeyCount: 1,
          pendingProductIntentCount: 0,
          staleIntentCount: 0,
        ),
      );
      final text = snap.toPrettyJson();
      expect(text.contains('clientWebVersion'), isTrue);
      expect(text.contains('serverWebVersion'), isTrue);
      expect(text.contains('"recoveryMode": true'), isTrue);
      expect(utf8.encode(text), isNotEmpty);
    });
  });
}
