// M2.3-R8.4.26 — build 95 bloqueado no gate (unitário; PackageInfo real em integration_test).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';

import 'support/stock_revision_client_build_test_support.dart';

void main() {
  tearDown(resetStockClientBuildForTest);

  test('UNIT_BUILD_95_BLOCKED_BY_GATE', () {
    initializeStockClientBuildFromRawForTest('95');
    expect(
      () => StockRevisionOperationGate.assertAllowed(
        StockRevisionOperationKind.venda,
      ),
      throwsA(isA<StockRevisionUpdateRequiredException>()),
    );
  });
}
