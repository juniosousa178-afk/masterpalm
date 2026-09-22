import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/client_build_identity.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/produto_pending_stock_reconciliation.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/sale_forensic_trace.dart';
import 'package:master_palm/core/produto_untracked_stock_conflict.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/mirjoias_client_stock_diagnostic_export.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

Produto _lacinhoGenericPending() {
  // Generic pending only (no structured cells) — Lacinho false-stale shape.
  return Produto(
    nome: 'Anel Lacinho Encanto',
    custoReal: 0,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 52.9,
    quantidade: 2,
    precoUnitario: 52.9,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 1, 1),
    codigoBarras: 'LACINHO',
    idFirebase: 'nathy-pratas-e-folheados-anel-lacinho-encanto',
    lojaId: 'nathy-pratas-e-folheados',
    stockRevision: 8,
    confirmedStockOperationId: 'old-local-confirmed',
    pendingStockOperationId: 'stale-editorial-pending',
    pendingStockBaseRevision: 8,
    tamanhos: const ['15', '22'],
    estoquePorTamanho: const {},
    variacoes: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SaleForensicTraceStore.disableHive = true;
    SaleForensicTraceStore.clearAll();
    UntrackedStockConflictStore.disableHive = true;
    UntrackedStockConflictStore.clearAll();
    StockCatalogBackendService.debugTransport = null;
  });

  tearDown(() {
    SaleForensicTraceStore.clearAll();
    SaleForensicTraceStore.disableHive = false;
    UntrackedStockConflictStore.clearAll();
    UntrackedStockConflictStore.disableHive = false;
    StockCatalogBackendService.debugTransport = null;
  });

  group('failed-precondition raw capture', () {
    test('UX amigável + JSON raw preservado', () async {
      final trace = await SaleForensicTraceStore.start();
      final err = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'variation stock unavailable',
        details: {
          'productId': 'nathy-pratas-e-folheados-lacinho',
          'size': '15',
          'color': 'sem-cor',
          'availableQty': 0,
          'authToken': 'SECRET_SHOULD_REDACT',
          'customerName': 'Cliente X',
        },
      );
      SaleForensicTraceStore.captureRawCallableError(
        error: err,
        stack: StackTrace.current,
        errorCaughtAt: 'stockCatalogCommand.call',
      );
      final ux = formatSalvarVendaErrorForUser(err);
      expect(ux.toLowerCase(), isNot(contains('variation stock unavailable')));
      expect(ux.toLowerCase(), contains('estoque'));

      final events = trace.events.where((e) => e['event'] == 'SALE_COMMAND_ERROR');
      expect(events, isNotEmpty);
      final raw = events.last;
      expect(raw['RAW_FIREBASE_CODE'], 'failed-precondition');
      expect(raw['RAW_FIREBASE_MESSAGE'], 'variation stock unavailable');
      final details = raw['RAW_FIREBASE_DETAILS_SANITIZED'] as Map;
      expect(details['size'], '15');
      expect(details['color'], 'sem-cor');
      expect(details['availableQty'], 0);
      expect(details['authToken'], 'REDACTED');
      expect(details['customerName'], 'REDACTED');
    });
  });

  group('aborted raw capture', () {
    test('UX mapping intacto + raw não se perde', () async {
      await SaleForensicTraceStore.start();
      final err = FirebaseFunctionsException(
        code: 'aborted',
        message: 'Stock revision conflict',
        details: {
          'expectedRevision': 8,
          'actualRevision': 9,
          'productId': 'p1',
        },
      );
      SaleForensicTraceStore.captureRawCallableError(
        error: err,
        stack: StackTrace.current,
        errorCaughtAt: 'stockCatalogCommand.call',
      );
      final ux = formatSalvarVendaErrorForUser(err);
      expect(ux.toLowerCase(), contains('atualize'));
      final section = SaleForensicTraceStore.toDiagnosticSection();
      final traces = section['traces'] as List;
      expect(traces, isNotEmpty);
      final events = (traces.first as Map)['events'] as List;
      final errEv = events.cast<Map>().lastWhere(
            (e) => e['event'] == 'SALE_COMMAND_ERROR',
          );
      expect(errEv['RAW_FIREBASE_CODE'], 'aborted');
      expect(
        (errEv['RAW_FIREBASE_DETAILS_SANITIZED'] as Map)['expectedRevision'],
        8,
      );
    });
  });

  group('build proof', () {
    test('export contém CLIENT_BUILD_ID do bundle (não só version.json)', () {
      final section = SaleForensicTraceStore.toDiagnosticSection();
      expect(section['clientBuildId'], kClientBuildId);
      expect(section['CLIENT_BUILD_ID'], isNull); // top section uses camelCase
      // After exporter merge keys exist via Mirjoias export:
      expect(kClientBuildId, isNot(equals('')));
      expect(kClientBuildId.toLowerCase(), isNot(equals('dev')));
      expect(kClientBuildId, contains('1.0.'));
      expect(section['clientGitCommit'], kClientGitCommit);
      expect(section['appVersion'], kClientAppVersion);
    });

    test('diagnostic payload saleForensics section', () async {
      await SaleForensicTraceStore.start();
      final exporter = MirjoiasClientStockDiagnosticExport(
        liveBuildId: 'ignored-for-bundle-proof',
        liveGitCommit: '',
        appVersion: '',
        remoteDocReader: (loja, id) async => null,
      );
      final result = await exporter.build(
        storeId: 'nathy-pratas-e-folheados',
        hiveProducts: const [],
      );
      final forensics = result.payload['saleForensics'] as Map;
      expect(forensics['CLIENT_BUILD_ID'], kClientBuildId);
      expect(forensics['CLIENT_GIT_COMMIT'], kClientGitCommit);
      expect(forensics['APP_VERSION'], kClientAppVersion);
      expect(forensics['READ_ONLY_EXPORT'], isTrue);
      expect(forensics['traces'], isA<List>());
      expect(exporter.writeAttempts, 0);
    });
  });

  group('Lacinho prep forensic expectations', () {
    test('STALE_STRUCTURAL classification + selected cell 15', () async {
      final local = _lacinhoGenericPending();
      final remote = <String, dynamic>{
        'quantidade': 2,
        'stockRevision': 8,
        'stockOperationId': 'a8f4df1a-3b8f-4412-b470-be4ee5b3d6a0',
        'stockKind': 'variation',
        'variacoes': {
          '15': {'sem-cor': 1},
          '22': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'15': 1, '22': 1},
        'tamanhos': ['15', '22'],
      };
      final decision = classifyPendingAgainstRemote(
        local: local,
        remote: remote,
      );
      expect(
        decision.classification.wire,
        'STALE_STRUCTURAL_PENDING',
      );
      expect(decision.classification.mustNeverFlush, isTrue);

      final trace = await SaleForensicTraceStore.start(initialPrep: {
        'productId': local.idFirebase,
        'productName': local.nome,
        'selectedSize': '15',
        'selectedColor': 'sem-cor',
        'selectedVariationKey': '15|sem-cor',
      });
      SaleForensicTraceStore.append('PENDING_RECONCILIATION', {
        'PENDING_BEFORE_PRESENT': true,
        'PENDING_CLASSIFICATION': decision.classification.wire,
        'MUST_NEVER_FLUSH': decision.classification.mustNeverFlush,
        'FLUSH_ATTEMPTED': false,
        'PENDING_CLEAR_ATTEMPTED': true,
        'PENDING_CLEAR_SUCCEEDED': true,
        'PENDING_AFTER_PRESENT': false,
      });
      SaleForensicTraceStore.append('REMOTE_REFRESH_SUCCESS', {
        'REMOTE_REFRESH_SUCCESS': true,
        'REMOTE_QTY': 2,
        'REMOTE_REVISION': 8,
        'SELECTED_CELL_KEY': '15|sem-cor',
        'SELECTED_CELL_QTY': 1,
        'REMOTE_CANONICAL_CELLS': {'15|sem-cor': 1, '22|sem-cor': 1},
      });
      SaleForensicTraceStore.captureSalePayload(
        storeId: 'nathy-pratas-e-folheados',
        operationId: 'sale-op-1',
        items: [
          {
            'productId': local.idFirebase,
            'quantity': 1,
            'size': '15',
            'color': 'sem-cor',
          },
        ],
      );

      final events = {for (final e in trace.events) e['event'] as String: e};
      expect(events['PENDING_RECONCILIATION']!['PENDING_CLASSIFICATION'],
          'STALE_STRUCTURAL_PENDING');
      expect(events['PENDING_RECONCILIATION']!['MUST_NEVER_FLUSH'], isTrue);
      expect(events['PENDING_RECONCILIATION']!['FLUSH_ATTEMPTED'], isFalse);
      expect(events['PENDING_RECONCILIATION']!['PENDING_AFTER_PRESENT'], isFalse);
      expect(events['REMOTE_REFRESH_SUCCESS']!['REMOTE_REFRESH_SUCCESS'], isTrue);
      expect(events['REMOTE_REFRESH_SUCCESS']!['SELECTED_CELL_KEY'], '15|sem-cor');
      expect(events['REMOTE_REFRESH_SUCCESS']!['SELECTED_CELL_QTY'], 1);
      expect(events['SALE_PAYLOAD']!['COMMAND_KIND'], 'sale');
      expect(events['SALE_PAYLOAD']!['COMMAND_NAME'], 'stockCatalogCommand');
    });
  });

  group('callable hook', () {
    test('sale command records payload + success without mutating business',
        () async {
      await SaleForensicTraceStore.start();
      StockCatalogBackendService.debugTransport = (name, data) async {
        expect(name, 'stockCatalogCommand');
        return {
          'operationId': data['operationId'],
          'alreadyApplied': false,
          'results': [
            {
              'productId': 'p1',
              'quantidade': 1,
              'stockRevision': 9,
              'stockOperationId': data['operationId'],
            }
          ],
        };
      };
      final res = await StockCatalogBackendService.command(
        lojaId: 'nathy-pratas-e-folheados',
        operationId: 'op-test-1',
        kind: 'sale',
        items: [
          {'productId': 'p1', 'quantity': 1, 'size': '15', 'color': 'sem-cor'},
        ],
      );
      expect(res['operationId'], 'op-test-1');
      final t = SaleForensicTraceStore.tracesNewestFirst.single;
      expect(
        t.events.any((e) => e['event'] == 'SALE_PAYLOAD'),
        isTrue,
      );
      expect(
        t.events.any((e) => e['event'] == 'SALE_COMMAND_SUCCESS'),
        isTrue,
      );
    });

    test('sale command captures failed-precondition from transport', () async {
      await SaleForensicTraceStore.start();
      StockCatalogBackendService.debugTransport = (name, data) async {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'variation stock unavailable',
          details: {'availableQty': 0, 'size': '15'},
        );
      };
      await expectLater(
        StockCatalogBackendService.command(
          lojaId: 'nathy-pratas-e-folheados',
          operationId: 'op-fail',
          kind: 'sale',
          items: [
            {'productId': 'p1', 'quantity': 1, 'size': '15'},
          ],
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      final t = SaleForensicTraceStore.tracesNewestFirst.single;
      final err = t.events.lastWhere((e) => e['event'] == 'SALE_COMMAND_ERROR');
      expect(err['RAW_FIREBASE_CODE'], 'failed-precondition');
      expect(err['ERROR_CAUGHT_AT'], 'stockCatalogCommand.call');
    });
  });

  group('dedup + ring', () {
    test('mesmo SALE_TRACE_ID não duplica entrada', () async {
      final a = await SaleForensicTraceStore.start(saleTraceId: 'fixed-id-1');
      final b = await SaleForensicTraceStore.start(saleTraceId: 'fixed-id-1');
      expect(identical(a, b), isTrue);
      expect(SaleForensicTraceStore.tracesNewestFirst.length, 1);
    });
  });

  group('diagnostic short code', () {
    test('appendDiagnosticCodeToUserMessage', () async {
      final t = await SaleForensicTraceStore.start(saleTraceId: 'abcd1234-ffff');
      final msg = SaleForensicTraceStore.appendDiagnosticCodeToUserMessage(
        'Estoque atualizado. Tente novamente.',
      );
      expect(msg, contains('Código de diagnóstico:'));
      expect(msg, contains(t.shortCode));
    });
  });
}
