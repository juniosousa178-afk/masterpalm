import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';

PdvV1PreparedSnapshot _prep({
  String operationId = 'op-ev-1',
  String saleId = 'sale-ev-1',
  String lojaId = 'loja-ev-1',
  String txHash = 'tx-ev-1',
}) {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: operationId,
    saleId: saleId,
    lojaId: lojaId,
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'item': 1},
    snapshotHash: 'snap-ev-1',
    txItemsHash: txHash,
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

PdvV1JournalRecord _record(PdvV1JournalState state) {
  return PdvV1JournalRecord(
    prepared: _prep(),
    state: state,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
}

PdvV1RemoteVerificationEvidence _evidence({
  PdvV1RemoteVerificationStatus status =
      PdvV1RemoteVerificationStatus.markerAbsentVerified,
  String operationId = 'op-ev-1',
  String saleId = 'sale-ev-1',
  String lojaId = 'loja-ev-1',
  String txHash = 'tx-ev-1',
  PdvV1RemoteMarkerInput marker = const PdvV1RemoteMarkerInput.ausente(),
  String divergentReason = '',
}) {
  return PdvV1RemoteVerificationEvidence(
    requestedOperationId: operationId,
    requestedSaleId: saleId,
    requestedLojaId: lojaId,
    requestedOrigin: pdvV1OrigemProtocolValue,
    requestedProtocolVersion: pdvV1ProtocolVersion,
    requestedTxItemsHash: txHash,
    verificationStatus: status,
    optionalMarker: marker,
    verificationSource: 'synthetic-test',
    verifiedAtEpochMs: 1700000000001,
    divergentReason: divergentReason,
  );
}

void main() {
  group('PdvV1RemoteVerificationEvidence', () {
    test('markerAbsentVerified rejeita requestedOperationId divergente', () {
      final ev = _evidence(operationId: 'op-OUTRO');
      final result = ev.validateAgainstJournal(
        _record(PdvV1JournalState.remoteStockPending),
      );
      expect(result.valid, isFalse);
      expect(result.reasonCode, 'identity_mismatch');
    });

    test('markerAbsentVerified rejeita loja divergente', () {
      final ev = _evidence(lojaId: 'loja-OUTRA');
      final result = ev.validateAgainstJournal(
        _record(PdvV1JournalState.remoteStockPending),
      );
      expect(result.valid, isFalse);
    });

    test('markerAppliedCompatible rejeita marker sem baixaAplicada', () {
      final ev = _evidence(
        status: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        marker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-ev-1',
          operationId: 'op-ev-1',
          saleId: 'sale-ev-1',
          baixaAplicada: false,
          txItemsHash: 'tx-ev-1',
        ),
      );
      final result = ev.validateAgainstJournal(
        _record(PdvV1JournalState.remoteStockPending),
      );
      expect(result.valid, isFalse);
      expect(result.reasonCode, 'baixa_not_applied');
    });

    test('markerAppliedCompatible rejeita txItemsHash divergente', () {
      final ev = _evidence(
        status: PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        marker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-ev-1',
          operationId: 'op-ev-1',
          saleId: 'sale-ev-1',
          baixaAplicada: true,
          txItemsHash: 'tx-DIVERGENTE',
        ),
      );
      final result = ev.validateAgainstJournal(
        _record(PdvV1JournalState.remoteStockPending),
      );
      expect(result.valid, isFalse);
      expect(result.reasonCode, 'marker_incompatible');
    });

    test('indisponível não é tratada como ausência', () {
      final evAbsent = _evidence();
      final evUnavailable = _evidence(
        status: PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
      );
      final record = _record(PdvV1JournalState.remoteStockPending);
      expect(evAbsent.validateAgainstJournal(record).valid, isTrue);
      expect(evUnavailable.validateAgainstJournal(record).valid, isTrue);
      expect(
        evAbsent.verificationStatus,
        isNot(PdvV1RemoteVerificationStatus.markerVerificationUnavailable),
      );
    });

    test('indisponível rejeita marcador confiável embutido', () {
      final ev = _evidence(
        status: PdvV1RemoteVerificationStatus.markerVerificationUnavailable,
        marker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-ev-1',
          operationId: 'op-ev-1',
          saleId: 'sale-ev-1',
          baixaAplicada: true,
          txItemsHash: 'tx-ev-1',
        ),
      );
      final result = ev.validateAgainstJournal(
        _record(PdvV1JournalState.remoteStockPending),
      );
      expect(result.valid, isFalse);
      expect(result.reasonCode, 'unavailable_with_trusted_marker');
    });
  });
}
