// M2.3-R8.4.26 — resolvedor fail-closed do build do cliente.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_stock_write_enforcement.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';

void main() {
  tearDown(StockRevisionOperationGate.resetDebugOverrides);

  group('R8426 resolver parsing', () {
    void expectParsed(String raw, int expected) {
      StockRevisionClientBuildResolver.instance.initializeFromRawForTest(raw);
      expect(
        StockRevisionClientBuildResolver.instance.requireBuildNumber(),
        expected,
      );
      expect(
        StockRevisionClientBuildResolver.instance.currentState.rawBuildNumber,
        raw,
      );
    }

    void expectFailClosed(String raw) {
      StockRevisionClientBuildResolver.instance.initializeFromRawForTest(raw);
      expect(
        () => StockRevisionClientBuildResolver.instance.requireBuildNumber(),
        throwsA(isA<Exception>()),
      );
    }

    test('1 raw 95 parsed and UPDATE_REQUIRED on gate', () {
      expectParsed('95', 95);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('2 raw 283 blocked', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(283);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('3 raw 284 allowed', () {
      expectParsed('284', 284);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        returnsNormally,
      );
    });

    test('4 raw 285 allowed', () {
      expectParsed('285', 285);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        returnsNormally,
      );
    });

    test('5 raw empty fail-closed', () {
      expectFailClosed('');
    });

    test('6 raw spaces fail-closed', () {
      expectFailClosed('   ');
    });

    test('7 raw abc fail-closed', () {
      expectFailClosed('abc');
    });

    test('8 raw 284.0 fail-closed', () {
      expectFailClosed('284.0');
    });

    test('9 raw 0 fail-closed', () {
      expectFailClosed('0');
    });

    test('10 raw -1 fail-closed', () {
      expectFailClosed('-1');
    });

    test('11 PackageInfo error path fail-closed', () {
      StockRevisionClientBuildResolver.instance.resetForTest();
      StockRevisionClientBuildResolver.instance.initializeFromRawForTest('');
      expect(
        StockRevisionClientBuildResolver.instance.currentState.source,
        StockRevisionClientBuildSource.invalid,
      );
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.venda,
        ),
        throwsA(isA<StockRevisionClientBuildInvalidException>()),
      );
    });

    test('12 resolver not initialized fail-closed', () {
      StockRevisionClientBuildResolver.instance.resetForTest(
        leaveUninitialized: true,
      );
      expect(
        () => StockRevisionClientBuildResolver.instance.requireBuildNumber(),
        throwsA(isA<StockRevisionClientBuildUnavailableException>()),
      );
    });

    test('13 test override 95 blocked', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(95);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.entradaManual,
        ),
        throwsA(isA<StockRevisionUpdateRequiredException>()),
      );
    });

    test('14 test override 285 allowed', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.combo,
        ),
        returnsNormally,
      );
    });

    test('15 override cleared returns uninitialized', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
      StockRevisionClientBuildResolver.instance.resetForTest(
        leaveUninitialized: true,
      );
      expect(
        StockRevisionClientBuildResolver.instance.isInitialized,
        isFalse,
      );
    });
  });

  group('R8426 enforceStockRevisionWriteContract uses resolver', () {
    test('build 95 blocks write contract', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(95);
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 5,
            'stockRevision': 1,
            'stockOperationId': 'op',
          },
          existingData: null,
        ),
        throwsA(
          isA<StockRevisionWriteRejectedException>().having(
            (e) => e.code,
            'code',
            'LEGACY_CLIENT_FORCED_UPDATE',
          ),
        ),
      );
    });

    test('build 285 allows write contract with revision fields', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
      expect(
        () => enforceStockRevisionWriteContract(
          updateData: {
            'quantidade': 5,
            'stockRevision': 1,
            'stockOperationId': 'op',
          },
          existingData: null,
        ),
        returnsNormally,
      );
    });
  });
}
