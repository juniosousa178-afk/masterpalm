// Contrato final fiado V1 — fonte autoritativa Firestore-first (Fase 6.5 design).

import 'dart:convert';

enum PdvV1ReceivableAuthorityModel {
  /// Firestore contas_receber é autoritativo; Hive é projeção local.
  firestoreFirst,
}

enum PdvV1ReceivableRecoveryDecision {
  upsertFirestoreThenProjectHive,
  reuseBoth,
  importFirestoreToHive,
  manualInterventionRequired,
}

class PdvV1ReceivableParcelContext {
  const PdvV1ReceivableParcelContext({
    required this.journalIntegro,
    required this.saleId,
    required this.parcela,
    required this.receivableSnapshotHash,
    required this.vendaHiveExiste,
    this.crHiveExiste = false,
    this.crFirestoreExiste = false,
    this.existingHash,
    this.existingValor,
    this.requestedValor,
  });

  final bool journalIntegro;
  final String saleId;
  final int parcela;
  final String receivableSnapshotHash;
  final bool vendaHiveExiste;
  final bool crHiveExiste;
  final bool crFirestoreExiste;
  final String? existingHash;
  final double? existingValor;
  final double? requestedValor;
}

String pdvV1ReceivableId({
  required String saleId,
  required int parcela,
}) =>
    '$saleId:conta_receber:p${parcela.clamp(1, 999)}';

/// Campos incluídos no hash canônico da parcela.
Map<String, dynamic> pdvV1ReceivableHashPayload({
  required String saleId,
  required int parcela,
  required double valor,
  required String vencimentoIso,
  required String clienteNomeNorm,
  required int parcelaTotal,
}) {
  return {
    'saleId': saleId.trim(),
    'parcela': parcela,
    'parcelaTotal': parcelaTotal,
    'valorCents': (valor * 100).round(),
    'vencimento': vencimentoIso,
    'clienteNome': clienteNomeNorm.trim().toLowerCase(),
  };
}

String pdvV1ReceivableSnapshotHash(Map<String, dynamic> payload) {
  final keys = payload.keys.toList()..sort();
  final sorted = <String, dynamic>{};
  for (final k in keys) {
    sorted[k] = payload[k];
  }
  return utf8.encode(jsonEncode(sorted)).length.toRadixString(16);
}

PdvV1ReceivableRecoveryDecision pdvV1DecidirReceivableAuthority(
  PdvV1ReceivableParcelContext ctx,
) {
  if (!ctx.journalIntegro ||
      !ctx.vendaHiveExiste ||
      ctx.saleId.trim().isEmpty) {
    return PdvV1ReceivableRecoveryDecision.manualInterventionRequired;
  }
  if (ctx.existingHash != null &&
      ctx.existingHash != ctx.receivableSnapshotHash) {
    return PdvV1ReceivableRecoveryDecision.manualInterventionRequired;
  }
  if (ctx.existingValor != null &&
      ctx.requestedValor != null &&
      (ctx.existingValor! - ctx.requestedValor!).abs() > 0.01) {
    return PdvV1ReceivableRecoveryDecision.manualInterventionRequired;
  }
  if (ctx.crHiveExiste && ctx.crFirestoreExiste) {
    return PdvV1ReceivableRecoveryDecision.reuseBoth;
  }
  if (ctx.crFirestoreExiste && !ctx.crHiveExiste) {
    return PdvV1ReceivableRecoveryDecision.importFirestoreToHive;
  }
  if (!ctx.crFirestoreExiste && !ctx.crHiveExiste) {
    return PdvV1ReceivableRecoveryDecision.upsertFirestoreThenProjectHive;
  }
  if (!ctx.crFirestoreExiste && ctx.crHiveExiste) {
    return PdvV1ReceivableRecoveryDecision.upsertFirestoreThenProjectHive;
  }
  return PdvV1ReceivableRecoveryDecision.manualInterventionRequired;
}

/// Dedup Hive: mesma chave + mesmo hash → não cria segunda parcela.
bool pdvV1ReceivableRecoveryDuplicadoSeguro({
  required Set<String> chavesProcessadas,
  required String receivableId,
  required String hash,
  required String hashExistente,
}) {
  final key = '$receivableId:$hash';
  if (chavesProcessadas.contains(key)) return true;
  if (hashExistente == hash) {
    chavesProcessadas.add(key);
    return true;
  }
  chavesProcessadas.add(key);
  return false;
}

const pdvV1ReceivableAuthorityModelEscolhido =
    PdvV1ReceivableAuthorityModel.firestoreFirst;
