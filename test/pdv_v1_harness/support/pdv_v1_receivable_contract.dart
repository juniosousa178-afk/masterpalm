// Contrato de idempotência fiado/conta a receber — Fase 6.4 (design only).
// Espelha mecanismos existentes em conta_receber_identity.dart e conta_receber_dedup.dart.
// NÃO é implementação de produção nem chama Hive/Firestore real.

const pdvV1ReceivableKeySeparator = ':';

/// Chave V1 mínima: saleId + parcela (espelha contaReceberStableId + doc id).
String pdvV1ReceivableIdempotencyKey({
  required String saleId,
  required int parcelaNumero,
}) {
  final sid = saleId.trim();
  if (sid.isEmpty) return '';
  return '$sid${pdvV1ReceivableKeySeparator}conta_receber${pdvV1ReceivableKeySeparator}p${parcelaNumero.clamp(1, 999)}';
}

String pdvV1ReceivableFirestoreDocId(String idempotencyKey) {
  if (idempotencyKey.isEmpty) return '';
  return 'cr_${idempotencyKey.replaceAll('/', '_').replaceAll(':', '_')}';
}

enum PdvV1ReceivableUpsertDecision {
  insertOnce,
  reuseExisting,
  manualInterventionRequired,
}

class PdvV1ReceivableRecoveryContext {
  const PdvV1ReceivableRecoveryContext({
    required this.journalIntegro,
    required this.saleId,
    required this.parcelaNumero,
    this.hiveContaExiste = false,
    this.firestoreContaExiste = false,
    this.existingKey,
    this.existingParcelaValor,
    this.requestedParcelaValor,
    this.vendaHiveExiste = false,
  });

  final bool journalIntegro;
  final String saleId;
  final int parcelaNumero;
  final bool hiveContaExiste;
  final bool firestoreContaExiste;
  final String? existingKey;
  final double? existingParcelaValor;
  final double? requestedParcelaValor;
  final bool vendaHiveExiste;
}

PdvV1ReceivableUpsertDecision pdvV1DecidirReceivableUpsert(
  PdvV1ReceivableRecoveryContext ctx,
) {
  if (!ctx.journalIntegro || ctx.saleId.trim().isEmpty) {
    return PdvV1ReceivableUpsertDecision.manualInterventionRequired;
  }
  if (!ctx.vendaHiveExiste) {
    return PdvV1ReceivableUpsertDecision.manualInterventionRequired;
  }
  if (ctx.hiveContaExiste || ctx.firestoreContaExiste) {
    if (ctx.existingParcelaValor != null &&
        ctx.requestedParcelaValor != null &&
        (ctx.existingParcelaValor! - ctx.requestedParcelaValor!).abs() > 0.01) {
      return PdvV1ReceivableUpsertDecision.manualInterventionRequired;
    }
    return PdvV1ReceivableUpsertDecision.reuseExisting;
  }
  return PdvV1ReceivableUpsertDecision.insertOnce;
}

/// Simula create duplicado bloqueado pelo contrato (não pelo código atual de vendas_service).
bool pdvV1ContratoBloqueiaCreateDuplicado({
  required Set<String> chavesJaCriadas,
  required String saleId,
  required int parcela,
}) {
  final key =
      pdvV1ReceivableIdempotencyKey(saleId: saleId, parcelaNumero: parcela);
  if (key.isEmpty) return true;
  if (chavesJaCriadas.contains(key)) return true;
  chavesJaCriadas.add(key);
  return false;
}
