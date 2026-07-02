import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_transaction_planner.dart';

PdvV1PreparedSnapshot _prepared() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-planner-1',
    saleId: 'sale-planner-1',
    lojaId: 'loja-planner-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1,
    preparedSnapshot: const {'x': 1},
    snapshotHash: 'snap-abc',
    txItemsHash: 'tx-abc',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

const _txItems = [
  PdvV1TxItemFrozen(productId: 'p1', quantidade: 2),
];

void main() {
  const planner = PdvV1TransactionPlanner();

  group('PdvV1TransactionPlanner', () {
    test('marker ausente → applyNewMarkerAndStock', () {
      final result = planner.plan(
        prepared: _prepared(),
        marker: const PdvV1RemoteMarkerInput.ausente(),
        txItems: _txItems,
        txItemsHash: 'tx-abc',
        snapshotHash: 'snap-abc',
        lojaId: 'loja-planner-1',
      );
      expect(
        result.decision,
        PdvV1TransactionPlannerDecision.applyNewMarkerAndStock,
      );
    });

    test('marker compatível → alreadyAppliedSkipStock', () {
      final result = planner.plan(
        prepared: _prepared(),
        marker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-planner-1',
          operationId: 'op-planner-1',
          saleId: 'sale-planner-1',
          baixaAplicada: true,
          txItemsHash: 'tx-abc',
        ),
        txItems: _txItems,
        txItemsHash: 'tx-abc',
        snapshotHash: 'snap-abc',
        lojaId: 'loja-planner-1',
      );
      expect(
        result.decision,
        PdvV1TransactionPlannerDecision.alreadyAppliedSkipStock,
      );
    });

    test('hash divergente → manualInterventionRequired', () {
      final result = planner.plan(
        prepared: _prepared(),
        marker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-planner-1',
          operationId: 'op-planner-1',
          saleId: 'sale-planner-1',
          baixaAplicada: true,
          txItemsHash: 'tx-DIVERGENTE',
        ),
        txItems: _txItems,
        txItemsHash: 'tx-abc',
        snapshotHash: 'snap-abc',
        lojaId: 'loja-planner-1',
      );
      expect(
        result.decision,
        PdvV1TransactionPlannerDecision.manualInterventionRequired,
      );
    });

    test('três execuções idênticas → mesmo resultado', () {
      final inputs = (
        prepared: _prepared(),
        marker: const PdvV1RemoteMarkerInput.ausente(),
        txItems: _txItems,
        txItemsHash: 'tx-abc',
        snapshotHash: 'snap-abc',
        lojaId: 'loja-planner-1',
      );
      final r1 = planner.plan(
        prepared: inputs.prepared,
        marker: inputs.marker,
        txItems: inputs.txItems,
        txItemsHash: inputs.txItemsHash,
        snapshotHash: inputs.snapshotHash,
        lojaId: inputs.lojaId,
      );
      final r2 = planner.plan(
        prepared: inputs.prepared,
        marker: inputs.marker,
        txItems: inputs.txItems,
        txItemsHash: inputs.txItemsHash,
        snapshotHash: inputs.snapshotHash,
        lojaId: inputs.lojaId,
      );
      final r3 = planner.plan(
        prepared: inputs.prepared,
        marker: inputs.marker,
        txItems: inputs.txItems,
        txItemsHash: inputs.txItemsHash,
        snapshotHash: inputs.snapshotHash,
        lojaId: inputs.lojaId,
      );
      expect(r1, r2);
      expect(r2, r3);
      expect(r1.toJson(), r3.toJson());
    });
  });
}
