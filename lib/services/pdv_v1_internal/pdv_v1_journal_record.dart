import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_internal_models.dart';

/// Estados mínimos do journal PDV V1 interno.
enum PdvV1JournalState {
  prepared,
  remoteStockPending,
  remoteStockApplied,
  hiveSalePending,
  hiveSaleCompleted,
  saleSyncPending,
  saleSyncCompleted,
  effectsPending,
  effectsCompleted,
  operationCompleted,
  manualInterventionRequired,
}

String pdvV1JournalStateToJson(PdvV1JournalState state) => state.name;

PdvV1JournalState? pdvV1JournalStateFromJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  for (final s in PdvV1JournalState.values) {
    if (s.name == raw) return s;
  }
  return null;
}

bool pdvV1JournalStateIsTerminal(PdvV1JournalState state) {
  return state == PdvV1JournalState.operationCompleted ||
      state == PdvV1JournalState.manualInterventionRequired;
}

/// Evidência sanitizada de journal malformado — payload limitado.
class PdvV1MalformedJournalEvidence {
  const PdvV1MalformedJournalEvidence({
    required this.reasonCode,
    this.operationIdCandidate = '',
    this.saleIdCandidate = '',
    this.lojaIdCandidate = '',
    this.protocolVersionCandidate = 0,
    required this.rawPayloadType,
    required this.rawPayloadSanitized,
    this.notAutomaticallyRecoverable = true,
    this.wasTruncated = false,
    this.estimatedPayloadSize = 0,
    this.redactedKeyCount = 0,
    this.rejectedNodeCount = 0,
  });

  final String reasonCode;
  final String operationIdCandidate;
  final String saleIdCandidate;
  final String lojaIdCandidate;
  final int protocolVersionCandidate;
  final String rawPayloadType;
  final dynamic rawPayloadSanitized;
  final bool notAutomaticallyRecoverable;
  final bool wasTruncated;
  final int estimatedPayloadSize;
  final int redactedKeyCount;
  final int rejectedNodeCount;

  Map<String, dynamic> toJson() => {
        'reasonCode': reasonCode,
        'operationIdCandidate': operationIdCandidate,
        'saleIdCandidate': saleIdCandidate,
        'lojaIdCandidate': lojaIdCandidate,
        'protocolVersionCandidate': protocolVersionCandidate,
        'rawPayloadType': rawPayloadType,
        'rawPayloadSanitized': rawPayloadSanitized,
        'notAutomaticallyRecoverable': notAutomaticallyRecoverable,
        'wasTruncated': wasTruncated,
        'estimatedPayloadSize': estimatedPayloadSize,
        'redactedKeyCount': redactedKeyCount,
        'rejectedNodeCount': rejectedNodeCount,
      };
}

/// Resultado de leitura — não grava no armazenamento.
class PdvV1JournalReadOutcome {
  const PdvV1JournalReadOutcome({
    required this.record,
    this.isMalformedReadOnly = false,
    this.malformedEvidence,
  });

  final PdvV1JournalRecord record;
  final bool isMalformedReadOnly;
  final PdvV1MalformedJournalEvidence? malformedEvidence;
}

/// Resultado serializável de persistência CAS condicional.
class PdvV1JournalPersistCasOutcome {
  const PdvV1JournalPersistCasOutcome({
    required this.accepted,
    required this.expectedRevision,
    required this.storedRevisionBefore,
    required this.storedRevisionAfter,
    required this.rejectionReasonCode,
    required this.operationId,
    required this.stateBefore,
    required this.stateAfter,
    required this.recordPersisted,
    required this.persistedOnlyToInjectedBox,
    this.storedSnapshot,
  });

  final bool accepted;
  final int expectedRevision;
  final int storedRevisionBefore;
  final int storedRevisionAfter;
  final String rejectionReasonCode;
  final String operationId;
  final PdvV1JournalState stateBefore;
  final PdvV1JournalState stateAfter;
  final bool recordPersisted;
  final bool persistedOnlyToInjectedBox;
  final Map<String, dynamic>? storedSnapshot;

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'expectedRevision': expectedRevision,
        'storedRevisionBefore': storedRevisionBefore,
        'storedRevisionAfter': storedRevisionAfter,
        'rejectionReasonCode': rejectionReasonCode,
        'operationId': operationId,
        'stateBefore': stateBefore.name,
        'stateAfter': stateAfter.name,
        'recordPersisted': recordPersisted,
        'persistedOnlyToInjectedBox': persistedOnlyToInjectedBox,
        if (storedSnapshot != null) 'storedSnapshot': storedSnapshot,
      };
}

const pdvV1MaxRetryableStageFailureAttempts = 3;

/// Patch same-state fechado — somente [recordRetryableStageFailure] nesta fase.
enum PdvV1JournalSameStatePatchKind {
  recordRetryableStageFailure,
}

/// Códigos canônicos fechados de falha retryable por stage.
enum PdvV1RetryableStageFailureCode {
  hiveSaleUpsertUnavailable('hive_sale_upsert_unavailable'),
  saleSyncUnavailable('sale_sync_unavailable'),
  effectsUnavailable('effects_unavailable');

  const PdvV1RetryableStageFailureCode(this.canonicalCode);

  final String canonicalCode;
}

/// Patch tipado — não aceita campos extras.
class PdvV1JournalSameStatePatch {
  const PdvV1JournalSameStatePatch({
    required this.patchKind,
    required this.expectedState,
    required this.expectedAttempts,
    required this.stageName,
    required this.failureCode,
  });

  final PdvV1JournalSameStatePatchKind patchKind;
  final PdvV1JournalState expectedState;
  final int expectedAttempts;
  final String stageName;
  final PdvV1RetryableStageFailureCode failureCode;

  Map<String, dynamic> toJson() => {
        'patchKind': patchKind.name,
        'expectedState': expectedState.name,
        'expectedAttempts': expectedAttempts,
        'stageName': stageName,
        'failureCode': failureCode.canonicalCode,
      };
}

/// Resultado de persistência CAS de patch same-state autorizado.
class PdvV1JournalSameStatePatchPersistOutcome {
  const PdvV1JournalSameStatePatchPersistOutcome({
    required this.accepted,
    required this.expectedRevision,
    required this.storedRevisionBefore,
    required this.storedRevisionAfter,
    required this.rejectionReasonCode,
    required this.operationId,
    required this.stateBefore,
    required this.stateAfter,
    required this.recordPersisted,
    required this.persistedOnlyToInjectedBox,
    this.storedSnapshot,
  });

  final bool accepted;
  final int expectedRevision;
  final int storedRevisionBefore;
  final int storedRevisionAfter;
  final String rejectionReasonCode;
  final String operationId;
  final PdvV1JournalState stateBefore;
  final PdvV1JournalState stateAfter;
  final bool recordPersisted;
  final bool persistedOnlyToInjectedBox;
  final Map<String, dynamic>? storedSnapshot;

  Map<String, dynamic> toJson() => {
        'accepted': accepted,
        'expectedRevision': expectedRevision,
        'storedRevisionBefore': storedRevisionBefore,
        'storedRevisionAfter': storedRevisionAfter,
        'rejectionReasonCode': rejectionReasonCode,
        'operationId': operationId,
        'stateBefore': stateBefore.name,
        'stateAfter': stateAfter.name,
        'recordPersisted': recordPersisted,
        'persistedOnlyToInjectedBox': persistedOnlyToInjectedBox,
        if (storedSnapshot != null) 'storedSnapshot': storedSnapshot,
      };
}

PdvV1JournalState? pdvV1JournalStateForRetryablePatchStageName(
    String stageName) {
  switch (stageName) {
    case 'hiveSaleUpsert':
      return PdvV1JournalState.hiveSalePending;
    case 'saleSync':
      return PdvV1JournalState.saleSyncPending;
    case 'effects':
      return PdvV1JournalState.effectsPending;
    default:
      return null;
  }
}

PdvV1RetryableStageFailureCode? pdvV1RetryableFailureCodeForPatchStageName(
  String stageName,
) {
  switch (stageName) {
    case 'hiveSaleUpsert':
      return PdvV1RetryableStageFailureCode.hiveSaleUpsertUnavailable;
    case 'saleSync':
      return PdvV1RetryableStageFailureCode.saleSyncUnavailable;
    case 'effects':
      return PdvV1RetryableStageFailureCode.effectsUnavailable;
    default:
      return null;
  }
}

PdvV1JournalRecord pdvV1JournalRecordApplyRetryableStageFailurePatch(
  PdvV1JournalRecord stored,
  PdvV1RetryableStageFailureCode failureCode,
) {
  return stored.copyWith(
    attempts: stored.attempts + 1,
    ultimoErroSanitizado: failureCode.canonicalCode,
    journalRevision: stored.journalRevision + 1,
  );
}

bool pdvV1JournalPreparedIdentityMatches(
  PdvV1PreparedSnapshot stored,
  PdvV1PreparedSnapshot candidate,
) {
  return stored.operationId == candidate.operationId &&
      stored.saleId == candidate.saleId &&
      stored.lojaId == candidate.lojaId &&
      stored.origemProtocol == candidate.origemProtocol &&
      stored.protocolVersion == candidate.protocolVersion &&
      stored.snapshotHash == candidate.snapshotHash &&
      stored.txItemsHash == candidate.txItemsHash;
}

bool pdvV1DeepJsonStructuralEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    final aMap = Map<String, dynamic>.from(a);
    final bMap = Map<String, dynamic>.from(b);
    if (aMap.length != bMap.length) return false;
    final keys = aMap.keys.toList()..sort();
    for (final key in keys) {
      if (!bMap.containsKey(key)) return false;
      if (!pdvV1DeepJsonStructuralEquals(aMap[key], bMap[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!pdvV1DeepJsonStructuralEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

bool pdvV1JournalPreparedSnapshotContentEquals(
  PdvV1PreparedSnapshot stored,
  PdvV1PreparedSnapshot candidate,
) {
  return pdvV1DeepJsonStructuralEquals(
    stored.preparedSnapshot,
    candidate.preparedSnapshot,
  );
}

/// Comparação estrutural determinística para persistência CAS.
bool pdvV1JournalRecordPersistStructurallyIdentical(
  PdvV1JournalRecord stored,
  PdvV1JournalRecord candidate,
) {
  if (stored.state != candidate.state) return false;
  if (stored.journalRevision != candidate.journalRevision) return false;
  if (stored.createdAtEpochMs != candidate.createdAtEpochMs) return false;
  if (stored.updatedAtEpochMs != candidate.updatedAtEpochMs) return false;
  if (stored.ultimoErroSanitizado != candidate.ultimoErroSanitizado) {
    return false;
  }
  if (stored.vendaHiveKey != candidate.vendaHiveKey) return false;
  if (stored.attempts != candidate.attempts) return false;
  if (stored.isMalformedReadOnly != candidate.isMalformedReadOnly) return false;
  if (!pdvV1JournalPreparedIdentityMatches(
      stored.prepared, candidate.prepared)) {
    return false;
  }
  if (!pdvV1JournalPreparedSnapshotContentEquals(
    stored.prepared,
    candidate.prepared,
  )) {
    return false;
  }
  return pdvV1DeepJsonStructuralEquals(stored.subestados, candidate.subestados);
}

/// Comparação fail-closed para idempotência de journal initial prepared rev0.
bool pdvV1InitialPreparedRecordSemanticallyIdentical(
  PdvV1JournalRecord existing,
  PdvV1JournalRecord expected,
) {
  if (existing.isMalformedReadOnly || expected.isMalformedReadOnly) {
    return false;
  }
  if (existing.malformedEvidence != null ||
      expected.malformedEvidence != null) {
    return false;
  }
  if (existing.state != PdvV1JournalState.prepared ||
      expected.state != PdvV1JournalState.prepared) {
    return false;
  }
  if (existing.journalRevision != 0 || expected.journalRevision != 0) {
    return false;
  }

  final existingPrepared = existing.prepared;
  final expectedPrepared = expected.prepared;

  if (existingPrepared.operationId != expectedPrepared.operationId) {
    return false;
  }
  if (existingPrepared.saleId != expectedPrepared.saleId) {
    return false;
  }
  if (existingPrepared.lojaId != expectedPrepared.lojaId) {
    return false;
  }
  if (existingPrepared.protocolVersion != expectedPrepared.protocolVersion) {
    return false;
  }
  if (existingPrepared.origemProtocol != expectedPrepared.origemProtocol) {
    return false;
  }
  if (existingPrepared.preparedAtEpochMs !=
      expectedPrepared.preparedAtEpochMs) {
    return false;
  }
  if (existingPrepared.snapshotHash != expectedPrepared.snapshotHash) {
    return false;
  }
  if (existingPrepared.txItemsHash != expectedPrepared.txItemsHash) {
    return false;
  }
  if (existingPrepared.isFiado ||
      existingPrepared.hasCombo ||
      existingPrepared.isEdicao ||
      existingPrepared.isCancelamento) {
    return false;
  }
  if (expectedPrepared.isFiado ||
      expectedPrepared.hasCombo ||
      expectedPrepared.isEdicao ||
      expectedPrepared.isCancelamento) {
    return false;
  }
  if (existingPrepared.isFiado != expectedPrepared.isFiado ||
      existingPrepared.hasCombo != expectedPrepared.hasCombo ||
      existingPrepared.isEdicao != expectedPrepared.isEdicao ||
      existingPrepared.isCancelamento != expectedPrepared.isCancelamento) {
    return false;
  }
  if (!pdvV1JournalPreparedSnapshotContentEquals(
    existingPrepared,
    expectedPrepared,
  )) {
    return false;
  }
  if (existing.createdAtEpochMs != expected.createdAtEpochMs) {
    return false;
  }
  if (existing.updatedAtEpochMs != expected.updatedAtEpochMs) {
    return false;
  }
  if (existing.attempts != expected.attempts) {
    return false;
  }
  if (existing.vendaHiveKey != expected.vendaHiveKey) {
    return false;
  }
  if (existing.ultimoErroSanitizado != expected.ultimoErroSanitizado) {
    return false;
  }
  if (!pdvV1DeepJsonStructuralEquals(
      existing.subestados, expected.subestados)) {
    return false;
  }

  return true;
}

/// Registro durável do journal — serializável.
class PdvV1JournalRecord {
  PdvV1JournalRecord({
    required this.prepared,
    required this.state,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
    this.journalRevision = 0,
    this.ultimoErroSanitizado = '',
    this.vendaHiveKey,
    Map<String, dynamic>? subestados,
    this.attempts = 0,
    this.isMalformedReadOnly = false,
    this.malformedEvidence,
  }) : subestados = subestados == null
            ? const {}
            : Map<String, dynamic>.unmodifiable(
                Map<String, dynamic>.from(subestados),
              );

  final PdvV1PreparedSnapshot prepared;
  final PdvV1JournalState state;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;
  final int journalRevision;
  final String ultimoErroSanitizado;
  final int? vendaHiveKey;
  final Map<String, dynamic> subestados;
  final int attempts;
  final bool isMalformedReadOnly;
  final PdvV1MalformedJournalEvidence? malformedEvidence;

  String get operationId =>
      malformedEvidence?.operationIdCandidate ?? prepared.operationId;

  String get saleId => malformedEvidence?.saleIdCandidate ?? prepared.saleId;

  String get lojaId => malformedEvidence?.lojaIdCandidate ?? prepared.lojaId;

  bool get isTerminal => pdvV1JournalStateIsTerminal(state);

  PdvV1JournalRecord copyWith({
    PdvV1PreparedSnapshot? prepared,
    PdvV1JournalState? state,
    int? updatedAtEpochMs,
    int? journalRevision,
    String? ultimoErroSanitizado,
    int? vendaHiveKey,
    Map<String, dynamic>? subestados,
    int? attempts,
    bool? isMalformedReadOnly,
    PdvV1MalformedJournalEvidence? malformedEvidence,
  }) {
    return PdvV1JournalRecord(
      prepared: prepared ?? this.prepared,
      state: state ?? this.state,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
      journalRevision: journalRevision ?? this.journalRevision,
      ultimoErroSanitizado: ultimoErroSanitizado ?? this.ultimoErroSanitizado,
      vendaHiveKey: vendaHiveKey ?? this.vendaHiveKey,
      subestados: subestados ?? this.subestados,
      attempts: attempts ?? this.attempts,
      isMalformedReadOnly: isMalformedReadOnly ?? this.isMalformedReadOnly,
      malformedEvidence: malformedEvidence ?? this.malformedEvidence,
    );
  }

  Map<String, dynamic> toJson() => {
        'prepared': prepared.toJson(),
        'state': pdvV1JournalStateToJson(state),
        'createdAtEpochMs': createdAtEpochMs,
        'updatedAtEpochMs': updatedAtEpochMs,
        'journalRevision': journalRevision,
        'ultimoErroSanitizado': ultimoErroSanitizado,
        if (vendaHiveKey != null) 'vendaHiveKey': vendaHiveKey,
        'subestados': Map<String, dynamic>.from(subestados),
        'attempts': attempts,
        if (isMalformedReadOnly) 'isMalformedReadOnly': true,
        if (malformedEvidence != null)
          'malformedEvidence': malformedEvidence!.toJson(),
      };

  static PdvV1JournalRecord fromJson(Map<String, dynamic> json) {
    final preparedRaw = json['prepared'];
    if (preparedRaw is! Map) {
      throw PdvV1MalformedJournalError('Campo prepared ausente ou inválido.');
    }
    final state = pdvV1JournalStateFromJson(json['state']?.toString());
    if (state == null) {
      throw PdvV1MalformedJournalError('Estado journal inválido.');
    }
    final prepared = PdvV1PreparedSnapshot.fromJson(
      Map<String, dynamic>.from(preparedRaw),
    );
    final subRaw = json['subestados'];
    final subestados =
        subRaw is Map ? Map<String, dynamic>.from(subRaw) : <String, dynamic>{};
    if (!json.containsKey('journalRevision')) {
      throw PdvV1InternalError(
        'journal_revision_ausente',
        'journal_revision_ausente',
      );
    }
    return PdvV1JournalRecord(
      prepared: prepared,
      state: state,
      createdAtEpochMs: _asInt(json['createdAtEpochMs']),
      updatedAtEpochMs: _asInt(json['updatedAtEpochMs']),
      journalRevision: _asInt(json['journalRevision']),
      ultimoErroSanitizado: (json['ultimoErroSanitizado'] ?? '').toString(),
      vendaHiveKey: json['vendaHiveKey'] is int
          ? json['vendaHiveKey'] as int
          : int.tryParse('${json['vendaHiveKey']}'),
      subestados: subestados,
      attempts: _asInt(json['attempts']),
    );
  }

  /// Leitura fail-closed — não grava; malformado preserva evidência bruta.
  static PdvV1JournalReadOutcome readOutcomeFromRaw({
    required dynamic rawPayload,
    String storageKey = '',
  }) {
    if (rawPayload == null) {
      return _malformedOutcome(
        reasonCode: 'journal_ausente',
        rawPayloadType: 'null',
        rawPayloadFrozen: null,
        storageKey: storageKey,
        message: 'journal ausente',
      );
    }

    if (rawPayload is! Map) {
      return _malformedOutcome(
        reasonCode: 'payload_tipo_invalido',
        rawPayloadType: rawPayload.runtimeType.toString(),
        rawPayloadFrozen: rawPayload,
        storageKey: storageKey,
        message: 'tipo de payload inválido',
      );
    }

    final json = Map<String, dynamic>.from(rawPayload);
    try {
      final record = fromJson(json);
      return PdvV1JournalReadOutcome(record: record);
    } on PdvV1InternalError catch (e) {
      return _malformedOutcome(
        reasonCode: e.code,
        rawPayloadType: 'Map',
        rawPayloadFrozen: json,
        storageKey: storageKey,
        message: e.message,
        json: json,
      );
    } catch (_) {
      return _malformedOutcome(
        reasonCode: 'journal_malformado',
        rawPayloadType: 'Map',
        rawPayloadFrozen: json,
        storageKey: storageKey,
        message: 'journal malformado',
        json: json,
      );
    }
  }

  static PdvV1JournalReadOutcome _malformedOutcome({
    required String reasonCode,
    required String rawPayloadType,
    required dynamic rawPayloadFrozen,
    required String storageKey,
    required String message,
    Map<String, dynamic>? json,
  }) {
    final candidates = _extractCandidates(json, storageKey);
    final sanitized = pdvV1SanitizeMalformedPayload(rawPayloadFrozen);
    final evidence = PdvV1MalformedJournalEvidence(
      reasonCode: reasonCode,
      operationIdCandidate: candidates.operationId,
      saleIdCandidate: candidates.saleId,
      lojaIdCandidate: candidates.lojaId,
      protocolVersionCandidate: candidates.protocolVersion,
      rawPayloadType: rawPayloadType,
      rawPayloadSanitized: sanitized.payload,
      wasTruncated: sanitized.wasTruncated,
      estimatedPayloadSize: sanitized.estimatedPayloadSize,
      redactedKeyCount: sanitized.redactedKeyCount,
      rejectedNodeCount: sanitized.rejectedNodeCount,
    );
    final placeholder = PdvV1PreparedSnapshot(
      protocolVersion: candidates.protocolVersion > 0
          ? candidates.protocolVersion
          : pdvV1ProtocolVersion,
      operationId: candidates.operationId,
      saleId: candidates.saleId,
      lojaId: candidates.lojaId,
      origem: PdvV1InternalOrigin.novaVendaPdvFuture,
      preparedAtEpochMs: 1,
      preparedSnapshot: const {'_malformed': true},
      snapshotHash: 'malformed',
      txItemsHash: 'malformed',
      isFiado: false,
      hasCombo: false,
      isEdicao: false,
      isCancelamento: false,
    );
    final record = PdvV1JournalRecord(
      prepared: placeholder,
      state: PdvV1JournalState.manualInterventionRequired,
      createdAtEpochMs: 1,
      updatedAtEpochMs: 1,
      ultimoErroSanitizado: message,
      isMalformedReadOnly: true,
      malformedEvidence: evidence,
    );
    return PdvV1JournalReadOutcome(
      record: record,
      isMalformedReadOnly: true,
      malformedEvidence: evidence,
    );
  }

  static ({
    String operationId,
    String saleId,
    String lojaId,
    int protocolVersion
  }) _extractCandidates(Map<String, dynamic>? json, String storageKey) {
    var operationId = storageKey.trim();
    var saleId = '';
    var lojaId = '';
    var protocolVersion = 0;

    if (json != null) {
      final topOp = (json['operationId'] ?? '').toString().trim();
      if (topOp.isNotEmpty) operationId = topOp;

      final preparedRaw = json['prepared'];
      if (preparedRaw is Map) {
        final prepared = Map<String, dynamic>.from(preparedRaw);
        final prepOp = (prepared['operationId'] ?? '').toString().trim();
        if (prepOp.isNotEmpty) operationId = prepOp;
        saleId = (prepared['saleId'] ?? '').toString().trim();
        lojaId = (prepared['lojaId'] ?? '').toString().trim();
        protocolVersion = _asInt(prepared['protocolVersion']);
      }
      if (protocolVersion == 0) {
        protocolVersion = _asInt(json['protocolVersion']);
      }
    }

    return (
      operationId: operationId,
      saleId: saleId,
      lojaId: lojaId,
      protocolVersion: protocolVersion,
    );
  }

  static PdvV1JournalRecord createInitial({
    required PdvV1PreparedSnapshot prepared,
    required int createdAtEpochMs,
  }) {
    prepared.validateForFoundation7AA();
    return PdvV1JournalRecord(
      prepared: prepared,
      state: PdvV1JournalState.prepared,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: createdAtEpochMs,
      journalRevision: 0,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

const _pdvV1MalformedMaxDepth = 16;
const _pdvV1MalformedMaxNodes = 1000;
const _pdvV1MalformedMaxPayloadBytes = 32 * 1024;
const _pdvV1MalformedMaxStringLen = 256;
const _pdvV1MalformedMaxMapKeys = 100;
const _pdvV1MalformedMaxListItems = 100;

const _pdvV1SensitiveKeyFragments = [
  'token',
  'jwt',
  'authorization',
  'secret',
  'password',
  'access',
  'refresh',
  'card',
  'cvv',
  'email',
  'e-mail',
  'telefone',
  'phone',
  'uid',
];

class PdvV1MalformedPayloadSanitizeResult {
  const PdvV1MalformedPayloadSanitizeResult({
    required this.payload,
    required this.wasTruncated,
    required this.estimatedPayloadSize,
    required this.redactedKeyCount,
    required this.rejectedNodeCount,
  });

  final dynamic payload;
  final bool wasTruncated;
  final int estimatedPayloadSize;
  final int redactedKeyCount;
  final int rejectedNodeCount;
}

PdvV1MalformedPayloadSanitizeResult pdvV1SanitizeMalformedPayload(
  dynamic raw,
) {
  final state = _MalformedSanitizeState();
  final payload = state.sanitizeValue(raw, depth: 0, ancestors: {});
  final encoded = '$payload';
  return PdvV1MalformedPayloadSanitizeResult(
    payload: payload,
    wasTruncated: state.wasTruncated,
    estimatedPayloadSize: encoded.length,
    redactedKeyCount: state.redactedKeyCount,
    rejectedNodeCount: state.rejectedNodeCount,
  );
}

class _MalformedSanitizeState {
  var nodeCount = 0;
  var wasTruncated = false;
  var redactedKeyCount = 0;
  var rejectedNodeCount = 0;

  dynamic sanitizeValue(
    dynamic value, {
    required int depth,
    required Set<int> ancestors,
  }) {
    if (depth > _pdvV1MalformedMaxDepth) {
      wasTruncated = true;
      rejectedNodeCount++;
      return '[depth_truncated]';
    }
    if (nodeCount >= _pdvV1MalformedMaxNodes) {
      wasTruncated = true;
      rejectedNodeCount++;
      return '[nodes_truncated]';
    }
    nodeCount++;

    if (value == null || value is bool || value is num) {
      return value;
    }
    if (value is String) {
      if (value.length > _pdvV1MalformedMaxStringLen) {
        wasTruncated = true;
        return value.substring(0, _pdvV1MalformedMaxStringLen);
      }
      return value;
    }
    if (value is List) {
      final out = <dynamic>[];
      final limit = value.length > _pdvV1MalformedMaxListItems
          ? _pdvV1MalformedMaxListItems
          : value.length;
      if (value.length > _pdvV1MalformedMaxListItems) {
        wasTruncated = true;
        rejectedNodeCount += value.length - limit;
      }
      for (var i = 0; i < limit; i++) {
        out.add(
            sanitizeValue(value[i], depth: depth + 1, ancestors: ancestors));
        if ('$out'.length > _pdvV1MalformedMaxPayloadBytes) {
          wasTruncated = true;
          break;
        }
      }
      return out;
    }
    if (value is Map) {
      final identity = identityHashCode(value);
      if (ancestors.contains(identity)) {
        wasTruncated = true;
        rejectedNodeCount++;
        return '[cycle]';
      }
      final nextAncestors = Set<int>.from(ancestors)..add(identity);
      final out = <String, dynamic>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= _pdvV1MalformedMaxMapKeys) {
          wasTruncated = true;
          rejectedNodeCount += value.length - count;
          break;
        }
        final key = entry.key.toString();
        if (_isSensitiveKey(key)) {
          redactedKeyCount++;
          out[key] = '[redacted]';
        } else {
          out[key] = sanitizeValue(
            entry.value,
            depth: depth + 1,
            ancestors: nextAncestors,
          );
        }
        count++;
        if ('$out'.length > _pdvV1MalformedMaxPayloadBytes) {
          wasTruncated = true;
          break;
        }
      }
      return out;
    }
    rejectedNodeCount++;
    return value.runtimeType.toString();
  }
}

bool _isSensitiveKey(String key) {
  final lower = key.toLowerCase();
  for (final frag in _pdvV1SensitiveKeyFragments) {
    if (lower.contains(frag)) return true;
  }
  return false;
}
