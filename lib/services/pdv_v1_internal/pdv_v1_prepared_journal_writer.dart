import 'pdv_v1_canonical_json.dart';
import 'pdv_v1_initial_prepared_journal_create_repository.dart';
import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_internal_models.dart';
import 'pdv_v1_journal_record.dart';
import 'pdv_v1_simple_sale_preparation.dart';

/// Outcomes fechados da escrita inicial de journal prepared.
enum PdvV1PreparedJournalWriteOutcomeKind {
  preparedJournalWritten,
  preparedJournalAlreadyExists,
  preparedJournalConflict,
  preparedJournalMalformedExisting,
  preparedJournalInvalid,
  preparedJournalWriteUnavailable,
}

/// Resultado tipado da escrita inicial — sem exceção bruta nem snapshot em falha.
class PdvV1PreparedJournalWriteOutcome {
  const PdvV1PreparedJournalWriteOutcome({
    required this.kind,
    required this.operationId,
    this.journalRevision,
    this.existingState,
    this.record,
  });

  final PdvV1PreparedJournalWriteOutcomeKind kind;
  final String operationId;
  final int? journalRevision;
  final PdvV1JournalState? existingState;
  final PdvV1JournalRecord? record;
}

/// Writer interno isolado — somente journal inicial em estado [prepared].
class PdvV1PreparedJournalWriter {
  PdvV1PreparedJournalWriter({
    required PdvV1InitialPreparedJournalCreateRepository
        initialPreparedJournalCreateRepository,
  }) : _initialPreparedJournalCreateRepository =
            initialPreparedJournalCreateRepository;

  final PdvV1InitialPreparedJournalCreateRepository
      _initialPreparedJournalCreateRepository;

  /// Predicado de entrada — exposto para testes de contrato (eligible + prepared).
  static bool acceptsPreparationInput({
    required bool isEligible,
    required PdvV1PreparedSnapshot? prepared,
  }) =>
      isEligible && prepared != null;

  /// Persiste journal inicial prepared revision 0 a partir de preparation elegível.
  Future<PdvV1PreparedJournalWriteOutcome> writeInitialPreparedJournal({
    required PdvV1SimpleSalePreparationResult preparation,
  }) async {
    if (!preparation.isEligible || preparation.prepared == null) {
      return PdvV1PreparedJournalWriteOutcome(
        kind: PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid,
        operationId: preparation.prepared?.operationId ?? '',
      );
    }

    final prepared = preparation.prepared!;
    if (!_validateCanonicalPrepared(prepared)) {
      return PdvV1PreparedJournalWriteOutcome(
        kind: PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid,
        operationId: prepared.operationId,
      );
    }

    try {
      prepared.validateForFoundation7AA();
    } on PdvV1ValidationError {
      return PdvV1PreparedJournalWriteOutcome(
        kind: PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid,
        operationId: prepared.operationId,
      );
    } on PdvV1ScopeNotSupportedError {
      return PdvV1PreparedJournalWriteOutcome(
        kind: PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid,
        operationId: prepared.operationId,
      );
    }

    final expectedInitial = PdvV1JournalRecord.createInitial(
      prepared: prepared,
      createdAtEpochMs: prepared.preparedAtEpochMs,
    );

    try {
      final casOutcome = await _initialPreparedJournalCreateRepository
          .createInitialPreparedIfAbsent(expectedInitial: expectedInitial);
      return _mapCasOutcome(
        casOutcome: casOutcome,
        expectedInitial: expectedInitial,
        operationId: prepared.operationId,
      );
    } catch (_) {
      return PdvV1PreparedJournalWriteOutcome(
        kind: PdvV1PreparedJournalWriteOutcomeKind
            .preparedJournalWriteUnavailable,
        operationId: prepared.operationId,
      );
    }
  }

  PdvV1PreparedJournalWriteOutcome _mapCasOutcome({
    required PdvV1JournalInitialCreateOutcome casOutcome,
    required PdvV1JournalRecord expectedInitial,
    required String operationId,
  }) {
    switch (casOutcome.kind) {
      case PdvV1JournalInitialCreateOutcomeKind.created:
      case PdvV1JournalInitialCreateOutcomeKind.alreadyExistsIdentical:
        return _mapSuccessCasOutcome(
          casOutcome: casOutcome,
          expectedInitial: expectedInitial,
          operationId: operationId,
        );
      case PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict:
        return PdvV1PreparedJournalWriteOutcome(
          kind: PdvV1PreparedJournalWriteOutcomeKind.preparedJournalConflict,
          operationId: operationId,
          journalRevision: casOutcome.journalRevision,
          existingState: casOutcome.existingState,
        );
      case PdvV1JournalInitialCreateOutcomeKind.existingMalformed:
        return PdvV1PreparedJournalWriteOutcome(
          kind: PdvV1PreparedJournalWriteOutcomeKind
              .preparedJournalMalformedExisting,
          operationId: operationId,
          existingState: casOutcome.existingState,
        );
      case PdvV1JournalInitialCreateOutcomeKind.unavailable:
        return PdvV1PreparedJournalWriteOutcome(
          kind: PdvV1PreparedJournalWriteOutcomeKind
              .preparedJournalWriteUnavailable,
          operationId: operationId,
        );
      case PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial:
        return PdvV1PreparedJournalWriteOutcome(
          kind: PdvV1PreparedJournalWriteOutcomeKind.preparedJournalInvalid,
          operationId: operationId,
        );
    }
  }

  PdvV1PreparedJournalWriteOutcome _mapSuccessCasOutcome({
    required PdvV1JournalInitialCreateOutcome casOutcome,
    required PdvV1JournalRecord expectedInitial,
    required String operationId,
  }) {
    final record = casOutcome.record;
    if (record == null ||
        record.operationId != expectedInitial.operationId ||
        !pdvV1InitialPreparedRecordSemanticallyIdentical(
          record,
          expectedInitial,
        )) {
      return PdvV1PreparedJournalWriteOutcome(
        kind: PdvV1PreparedJournalWriteOutcomeKind
            .preparedJournalWriteUnavailable,
        operationId: operationId,
      );
    }

    final kind = casOutcome.kind == PdvV1JournalInitialCreateOutcomeKind.created
        ? PdvV1PreparedJournalWriteOutcomeKind.preparedJournalWritten
        : PdvV1PreparedJournalWriteOutcomeKind.preparedJournalAlreadyExists;

    return PdvV1PreparedJournalWriteOutcome(
      kind: kind,
      operationId: operationId,
      journalRevision: 0,
      existingState: PdvV1JournalState.prepared,
      record: record,
    );
  }
}

const _innerRequiredKeys = <String>{
  'protocolVersion',
  'operationId',
  'saleId',
  'lojaId',
  'origem',
  'snapshotHash',
  'txItemsHash',
  'txItems',
};

const _payloadWithoutSnapshotHashKeys = <String>{
  'protocolVersion',
  'operationId',
  'saleId',
  'lojaId',
  'origem',
  'txItemsHash',
  'txItems',
};

const _txItemRequiredKeys = <String>{
  'productId',
  'quantidade',
};

final _sha256HexLower = RegExp(r'^[0-9a-f]{64}$');

bool _validateCanonicalPrepared(PdvV1PreparedSnapshot prepared) {
  if (prepared.protocolVersion != pdvV1ProtocolVersion) {
    return false;
  }
  if (prepared.origemProtocol != pdvV1OrigemProtocolValue) {
    return false;
  }
  if (!_isExactNonEmptyId(prepared.operationId)) {
    return false;
  }
  if (!_isExactNonEmptyId(prepared.saleId)) {
    return false;
  }
  if (prepared.operationId != prepared.saleId) {
    return false;
  }
  if (!_isExactNonEmptyId(prepared.lojaId)) {
    return false;
  }
  if (prepared.preparedAtEpochMs <= 0) {
    return false;
  }
  if (prepared.isFiado ||
      prepared.hasCombo ||
      prepared.isEdicao ||
      prepared.isCancelamento) {
    return false;
  }
  if (!_isSha256Hex(prepared.snapshotHash)) {
    return false;
  }
  if (!_isSha256Hex(prepared.txItemsHash)) {
    return false;
  }

  final inner = prepared.preparedSnapshot;
  final innerKeys = inner.keys.toSet();
  if (innerKeys.length != _innerRequiredKeys.length ||
      !innerKeys.containsAll(_innerRequiredKeys)) {
    return false;
  }

  if (inner['protocolVersion'] is! int ||
      inner['protocolVersion'] != pdvV1ProtocolVersion) {
    return false;
  }
  if (inner['operationId'] is! String ||
      inner['saleId'] is! String ||
      inner['lojaId'] is! String ||
      inner['origem'] is! String) {
    return false;
  }
  if (inner['origem'] != pdvV1OrigemProtocolValue) {
    return false;
  }
  if (inner['snapshotHash'] is! String || inner['txItemsHash'] is! String) {
    return false;
  }
  if (!_isSha256Hex(inner['snapshotHash'] as String)) {
    return false;
  }
  if (!_isSha256Hex(inner['txItemsHash'] as String)) {
    return false;
  }
  if (inner['txItems'] is! List) {
    return false;
  }

  if (inner['protocolVersion'] != prepared.protocolVersion ||
      inner['operationId'] != prepared.operationId ||
      inner['saleId'] != prepared.saleId ||
      inner['lojaId'] != prepared.lojaId ||
      inner['origem'] != prepared.origemProtocol ||
      inner['snapshotHash'] != prepared.snapshotHash ||
      inner['txItemsHash'] != prepared.txItemsHash) {
    return false;
  }

  final txItemsCanonical = _canonicalTxItemsFromInner(inner['txItems'] as List);
  if (txItemsCanonical == null) {
    return false;
  }

  final expectedTxItemsHash = pdvV1CanonicalSha256(txItemsCanonical);
  if (expectedTxItemsHash != prepared.txItemsHash ||
      expectedTxItemsHash != inner['txItemsHash']) {
    return false;
  }

  final payloadSemSnapshotHash = <String, Object>{
    'protocolVersion': pdvV1ProtocolVersion,
    'operationId': prepared.operationId,
    'saleId': prepared.saleId,
    'lojaId': prepared.lojaId,
    'origem': pdvV1OrigemProtocolValue,
    'txItemsHash': prepared.txItemsHash,
    'txItems': txItemsCanonical,
  };
  final payloadKeys = payloadSemSnapshotHash.keys.toSet();
  if (payloadKeys.length != _payloadWithoutSnapshotHashKeys.length ||
      !payloadKeys.containsAll(_payloadWithoutSnapshotHashKeys)) {
    return false;
  }

  final expectedSnapshotHash = pdvV1CanonicalSha256(payloadSemSnapshotHash);
  if (expectedSnapshotHash != prepared.snapshotHash ||
      expectedSnapshotHash != inner['snapshotHash']) {
    return false;
  }

  return true;
}

List<Map<String, Object>>? _canonicalTxItemsFromInner(List txItems) {
  if (txItems.length != 1) {
    return null;
  }
  final rawItem = txItems.single;
  if (rawItem is! Map) {
    return null;
  }
  final itemKeys = rawItem.keys.toSet();
  if (itemKeys.length != _txItemRequiredKeys.length ||
      !itemKeys.containsAll(_txItemRequiredKeys)) {
    return null;
  }
  final productId = rawItem['productId'];
  final quantidade = rawItem['quantidade'];
  if (productId is! String || !_isExactNonEmptyId(productId)) {
    return null;
  }
  if (quantidade is! int || quantidade <= 0) {
    return null;
  }
  return <Map<String, Object>>[
    <String, Object>{
      'productId': productId,
      'quantidade': quantidade,
    },
  ];
}

bool _isExactNonEmptyId(String value) =>
    value.isNotEmpty && value == value.trim();

bool _isSha256Hex(String value) => _sha256HexLower.hasMatch(value);

/// Validação canônica do prepared — exposta somente para testes de contrato.
bool pdvV1ValidateCanonicalPreparedForJournalWrite(
  PdvV1PreparedSnapshot prepared,
) =>
    _validateCanonicalPrepared(prepared);

/// Predicado de entrada para testes de contrato R2-C.3.
bool pdvV1PreparedJournalWriteAcceptsPreparationInput({
  required bool isEligible,
  required PdvV1PreparedSnapshot? prepared,
}) =>
    PdvV1PreparedJournalWriter.acceptsPreparationInput(
      isEligible: isEligible,
      prepared: prepared,
    );
