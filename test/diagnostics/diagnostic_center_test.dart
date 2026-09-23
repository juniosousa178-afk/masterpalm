import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/diagnostics/diagnostics.dart';

void main() {
  setUp(() {
    DiagnosticTraceService.clearAll();
    DiagnosticIncidentHistory.disableHive = true;
    DiagnosticIncidentHistory.clearAll();
  });

  group('DiagnosticErrorClassifier', () {
    test('permission-denied is CONFIRMED', () {
      final c = DiagnosticErrorClassifier.classify(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'denied',
        ),
      );
      expect(c.classification, DiagnosticClassification.firebasePermissionDenied);
      expect(c.rootCauseStatus, DiagnosticRootCauseStatus.confirmed);
    });

    test('failed-precondition already restored', () {
      final c = DiagnosticErrorClassifier.classify(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Sale already restored',
          details: {'reason': 'already restored'},
        ),
      );
      expect(
        c.classification,
        DiagnosticClassification.saleRestoreAlreadyApplied,
      );
      expect(c.rootCauseStatus, DiagnosticRootCauseStatus.confirmed);
    });

    test('network offline', () {
      final c = DiagnosticErrorClassifier.classify(
        Exception('SocketException: Failed host lookup'),
        online: false,
      );
      expect(c.classification, DiagnosticClassification.networkOffline);
    });

    test('unknown stays UNKNOWN root cause', () {
      final c = DiagnosticErrorClassifier.classify(Exception('weird'));
      expect(c.classification, DiagnosticClassification.unknownError);
      expect(c.rootCauseStatus, DiagnosticRootCauseStatus.unknown);
    });

    test('anomaly aggregate uses classified not confirmed unless forced', () {
      final c = DiagnosticErrorClassifier.fromAnomalyCode(
        DiagnosticClassification.stockAggregateMismatch,
      );
      expect(
        c.rootCauseStatus,
        DiagnosticRootCauseStatus.classifiedNotConfirmed,
      );
    });
  });

  group('DiagnosticTraceService', () {
    test('start stage success complete', () {
      final t = DiagnosticTraceService.start(
        storeId: 'store-a',
        module: DiagnosticModule.sales,
        operationType: 'sale',
      );
      DiagnosticTraceService.stage(DiagnosticStages.saleStart);
      DiagnosticTraceService.success(DiagnosticStages.stockCommandSuccess);
      DiagnosticTraceService.complete(
        stageName: DiagnosticStages.saleComplete,
      );
      expect(t.stages.length, greaterThanOrEqualTo(3));
      expect(t.completed, isTrue);
      expect(t.aborted, isFalse);
      expect(DiagnosticTraceService.activeTraceId, isNull);
    });

    test('tenant isolation of sections', () {
      DiagnosticTraceService.start(
        storeId: 'store-a',
        module: DiagnosticModule.stock,
        operationType: 'replace',
      );
      DiagnosticTraceService.complete();
      DiagnosticTraceService.start(
        storeId: 'store-b',
        module: DiagnosticModule.stock,
        operationType: 'replace',
      );
      DiagnosticTraceService.complete();
      final a = DiagnosticTraceService.toDiagnosticSection(storeId: 'store-a');
      final b = DiagnosticTraceService.toDiagnosticSection(storeId: 'store-b');
      expect(a.every((e) => e['storeId'] == 'store-a'), isTrue);
      expect(b.every((e) => e['storeId'] == 'store-b'), isTrue);
      expect(a.length, 1);
      expect(b.length, 1);
    });
  });

  group('PII redaction', () {
    test('redacts sensitive keys', () {
      final m = sanitizeDiagnosticMap({
        'password': 'secret123',
        'token': 'abc',
        'productId': 'p1',
        'clienteNome': 'Maria',
        'nested': {'apiKey': 'x', 'qty': 1},
      });
      expect(m['password'], kDiagnosticRedacted);
      expect(m['token'], kDiagnosticRedacted);
      expect(m['productId'], 'p1');
      expect(m['clienteNome'], kDiagnosticRedacted);
      expect((m['nested'] as Map)['apiKey'], kDiagnosticRedacted);
      expect((m['nested'] as Map)['qty'], 1);
    });

    test('export never includes raw password', () {
      final incident = DiagnosticIncident(
        incidentId: 'i1',
        traceId: 't1',
        storeId: 's1',
        timestamp: DateTime.now().toUtc(),
        severity: DiagnosticSeverity.warning,
        module: DiagnosticModule.auth,
        operationType: 'login',
        classification: DiagnosticClassification.unknownError,
        rootCauseStatus: DiagnosticRootCauseStatus.unknown,
        userTitle: 'x',
        userMessage: 'y',
        safeNextAction: 'z',
        metadataSanitized: {'password': 'nope', 'qty': 2},
      );
      final json = incident.toJson();
      final encoded = safeJsonEncode(json);
      expect(encoded.contains('nope'), isFalse);
      expect(encoded.contains(kDiagnosticRedacted), isTrue);
    });
  });

  group('Incident history bounds', () {
    test('keeps max and store filter', () async {
      for (var i = 0; i < 5; i++) {
        await DiagnosticIncidentHistory.record(
          DiagnosticIncident(
            incidentId: 'i$i',
            traceId: 't$i',
            storeId: i.isEven ? 'a' : 'b',
            timestamp: DateTime.now().toUtc(),
            severity: DiagnosticSeverity.warning,
            module: DiagnosticModule.stock,
            operationType: 'scan',
            classification:
                DiagnosticClassification.stockLocalRemoteMismatch,
            rootCauseStatus:
                DiagnosticRootCauseStatus.classifiedNotConfirmed,
            userTitle: 't',
            userMessage: 'm',
            safeNextAction: 'n',
          ),
        );
      }
      final a = DiagnosticIncidentHistory.recent(storeId: 'a');
      expect(a.every((e) => e.storeId == 'a'), isTrue);
      expect(a.length, 3);
    });
  });

  group('Health status', () {
    test('healthy warning critical', () {
      expect(
        DiagnosticHealthStatus.fromSeverities(const []),
        DiagnosticHealthStatus.healthy,
      );
      expect(
        DiagnosticHealthStatus.fromSeverities(
          [DiagnosticSeverity.warning],
        ),
        DiagnosticHealthStatus.warning,
      );
      expect(
        DiagnosticHealthStatus.fromSeverities([
          DiagnosticSeverity.warning,
          DiagnosticSeverity.critical,
        ]),
        DiagnosticHealthStatus.critical,
      );
    });
  });

  group('Export', () {
    test('file name format', () {
      final name = DiagnosticExportService.fileNameFor(
        storeId: 'nathy-pratas-e-folheados',
        at: DateTime.utc(2026, 9, 22, 12),
      );
      expect(name.startsWith('MASTERPALM_DIAGNOSTIC_NATHY'), isTrue);
      expect(name.endsWith('.json'), isTrue);
    });
  });

  group('Known classifications', () {
    test('all known list covers required codes', () {
      const required = [
        DiagnosticClassification.firebasePermissionDenied,
        DiagnosticClassification.stockLocalRemoteMismatch,
        DiagnosticClassification.stockAggregateMismatch,
        DiagnosticClassification.saleMissingStockOperationBinding,
        DiagnosticClassification.staleTombstoneLiveRemoteCell,
        DiagnosticClassification.cacheLocalUntrackedMutation,
        DiagnosticClassification.buildIdentityMismatch,
        DiagnosticClassification.unknownError,
      ];
      for (final c in required) {
        expect(DiagnosticClassification.allKnown.contains(c), isTrue);
      }
    });
  });
}
