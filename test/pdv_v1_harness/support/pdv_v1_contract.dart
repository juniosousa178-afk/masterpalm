// Contrato conceitual PDV V1 — harness isolado (não é implementação de produção).
// Fase 6.3: validação de premissas, recovery e subestados.

import 'dart:convert';

const pdvV1ProtocolVersion = 1;
const pdvV1Origem = 'pdv';
const pdvV1HarnessLojaFicticia = 'loja-demo-pdv-v1-harness';

/// Subestados obrigatórios de efeitos pós-baixa (journal V1).
enum PdvV1EffectSubstate {
  hiveSalePending,
  hiveSaleCompleted,
  productCacheRefreshPending,
  productCacheRefreshCompleted,
  comboCapPending,
  comboCapCompleted,
  receivablePending,
  receivableCompleted,
  syncQueuePending,
  syncQueueCompleted,
  syncRemotePending,
  syncRemoteCompleted,
  catalogProjectionPending,
  catalogProjectionCompleted,
  movementPending,
  movementCompleted,
}

enum PdvV1RecoveryDecision {
  reconstructHiveFromJournal,
  importFromRemoteSale,
  resumeIdempotentEffect,
  manualInterventionRequired,
  noAction,
}

enum PdvV1EffectClass {
  /// Parte da transação principal estoque + marcador.
  criticalInTransaction,

  /// Recomputável deterministicamente a partir de fonte de verdade.
  derivedRecomputable,

  /// Pós-processamento com subestado rastreado.
  postProcessIdempotent,

  /// Não recuperável automaticamente.
  manualOnly,
}

class PdvV1JournalSnapshot {
  const PdvV1JournalSnapshot({
    required this.integro,
    required this.protocolVersion,
    required this.operationId,
    required this.saleId,
    required this.lojaId,
    required this.origem,
    required this.txItemsHash,
    required this.snapshotHash,
    required this.preparedSnapshotCompleto,
    this.vendaHiveKey,
    this.substates = const {},
  });

  final bool integro;
  final int protocolVersion;
  final String operationId;
  final String saleId;
  final String lojaId;
  final String origem;
  final String txItemsHash;
  final String snapshotHash;
  final bool preparedSnapshotCompleto;
  final int? vendaHiveKey;
  final Map<PdvV1EffectSubstate, bool> substates;

  bool get origemPdv =>
      origem == pdvV1Origem && protocolVersion == pdvV1ProtocolVersion;
}

class PdvV1RemoteMarker {
  const PdvV1RemoteMarker({
    required this.presente,
    required this.validoV1,
    required this.baixaAplicada,
    required this.estornoAplicado,
    required this.txItemsHash,
    required this.lojaId,
    required this.origem,
    required this.protocolVersion,
  });

  const PdvV1RemoteMarker.ausente()
      : presente = false,
        validoV1 = false,
        baixaAplicada = false,
        estornoAplicado = false,
        txItemsHash = '',
        lojaId = '',
        origem = '',
        protocolVersion = 0;

  final bool presente;
  final bool validoV1;
  final bool baixaAplicada;
  final bool estornoAplicado;
  final String txItemsHash;
  final String lojaId;
  final String origem;
  final int protocolVersion;

  bool get legado =>
      presente &&
      (protocolVersion < pdvV1ProtocolVersion || origem != pdvV1Origem);
}

class PdvV1RecoveryContext {
  const PdvV1RecoveryContext({
    this.journal,
    this.marcador = const PdvV1RemoteMarker.ausente(),
    this.vendaFirestoreExiste = false,
    this.vendaHiveExiste = false,
    this.vendaHiveKeysDuplicadasSaleId = 0,
    this.hashCompativel = true,
    this.lojaAtivaCompativel = true,
    this.online = true,
  });

  final PdvV1JournalSnapshot? journal;
  final PdvV1RemoteMarker marcador;
  final bool vendaFirestoreExiste;
  final bool vendaHiveExiste;
  final int vendaHiveKeysDuplicadasSaleId;
  final bool hashCompativel;
  final bool lojaAtivaCompativel;
  final bool online;
}

/// Recovery automático exige journal íntegro + 9 condições (Fase 6.3).
bool pdvV1JournalPermiteRecoveryAutomatico(PdvV1JournalSnapshot j) {
  return j.integro &&
      j.origemPdv &&
      j.preparedSnapshotCompleto &&
      j.operationId.isNotEmpty &&
      j.saleId.isNotEmpty &&
      j.lojaId.isNotEmpty &&
      j.txItemsHash.isNotEmpty &&
      j.snapshotHash.isNotEmpty;
}

PdvV1RecoveryDecision pdvV1DecidirRecovery(PdvV1RecoveryContext ctx) {
  final j = ctx.journal;

  if (j == null || !j.integro || !j.preparedSnapshotCompleto) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (!pdvV1JournalPermiteRecoveryAutomatico(j)) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (!ctx.lojaAtivaCompativel) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (!ctx.hashCompativel) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (ctx.vendaHiveKeysDuplicadasSaleId > 1) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (!ctx.marcador.presente ||
      !ctx.marcador.validoV1 ||
      ctx.marcador.legado ||
      !ctx.marcador.baixaAplicada) {
    if (!ctx.online && j.substates.isEmpty) {
      return PdvV1RecoveryDecision.noAction;
    }
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (ctx.marcador.txItemsHash != j.txItemsHash) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (ctx.marcador.lojaId != j.lojaId) {
    return PdvV1RecoveryDecision.manualInterventionRequired;
  }

  if (!ctx.vendaHiveExiste) {
    return PdvV1RecoveryDecision.reconstructHiveFromJournal;
  }

  if (ctx.vendaFirestoreExiste && ctx.vendaHiveExiste) {
    return PdvV1RecoveryDecision.resumeIdempotentEffect;
  }

  if (ctx.vendaFirestoreExiste && !ctx.vendaHiveExiste) {
    return PdvV1RecoveryDecision.importFromRemoteSale;
  }

  return PdvV1RecoveryDecision.resumeIdempotentEffect;
}

/// Marcador isolado sem journal nunca reconstrói venda.
PdvV1RecoveryDecision pdvV1DecidirSemJournal(PdvV1RemoteMarker marcador) {
  if (!marcador.presente) return PdvV1RecoveryDecision.noAction;
  return PdvV1RecoveryDecision.manualInterventionRequired;
}

enum PdvV1HiveUpsertDecision {
  insertOnce,
  reuseExisting,
  manualInterventionRequired,
}

class PdvV1HiveUpsertContext {
  const PdvV1HiveUpsertContext({
    required this.saleId,
    required this.snapshotHash,
    this.existingHiveKey,
    this.existingSnapshotHash,
    this.duplicateCount = 0,
  });

  final String saleId;
  final String snapshotHash;
  final int? existingHiveKey;
  final String? existingSnapshotHash;
  final int duplicateCount;
}

PdvV1HiveUpsertDecision pdvV1DecidirHiveUpsert(PdvV1HiveUpsertContext ctx) {
  if (ctx.duplicateCount > 1) {
    return PdvV1HiveUpsertDecision.manualInterventionRequired;
  }
  if (ctx.existingHiveKey != null) {
    if (ctx.existingSnapshotHash == ctx.snapshotHash) {
      return PdvV1HiveUpsertDecision.reuseExisting;
    }
    return PdvV1HiveUpsertDecision.manualInterventionRequired;
  }
  return PdvV1HiveUpsertDecision.insertOnce;
}

bool pdvV1PodeIniciarTransacaoRemota(PdvV1JournalSnapshot? j) {
  if (j == null || !j.integro) return false;
  return j.preparedSnapshotCompleto &&
      j.snapshotHash.isNotEmpty &&
      j.txItemsHash.isNotEmpty;
}

bool pdvV1PodeMarcarSyncCompleted(Map<PdvV1EffectSubstate, bool> substates) {
  const obrigatorios = [
    PdvV1EffectSubstate.hiveSaleCompleted,
    PdvV1EffectSubstate.productCacheRefreshCompleted,
    PdvV1EffectSubstate.comboCapCompleted,
    PdvV1EffectSubstate.syncRemoteCompleted,
  ];
  for (final s in obrigatorios) {
    if (substates[s] != true) return false;
  }
  return true;
}

String pdvV1CanonicalJsonHash(Map<String, dynamic> map) {
  final canonical = _sortMap(map);
  return sha256Like(utf8.encode(jsonEncode(canonical)));
}

Map<String, dynamic> _sortMap(Map<String, dynamic> m) {
  final keys = m.keys.toList()..sort();
  final out = <String, dynamic>{};
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      out[k] = _sortMap(Map<String, dynamic>.from(v));
    } else if (v is List) {
      out[k] = v;
    } else {
      out[k] = v;
    }
  }
  return out;
}

/// Hash determinístico leve para harness (não substitui crypto em produção).
String sha256Like(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
