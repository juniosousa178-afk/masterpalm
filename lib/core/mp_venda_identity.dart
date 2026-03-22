// Identidade canônica de venda Mercado Pago ↔ Firestore estoque_vendas.
// Origem da duplicidade corrigida: webhook gravava `mp_${orderId}_${paymentId}` e o app
// gerava UUID em syncVenda — dois documentos para o mesmo pagamento.
//
// Estratégia: um único docId determinístico `mp_${orderId}_${paymentId}`; app e webhook alinham.
// Retrocompatível: docs UUID ou legados continuam válidos; só fluxos com paymentId+order usam mp_*.

/// Prefixo documento estoque_vendas criado pelo webhook / consolidado MP.
const String kMpVendaDocPrefix = 'mp_';

/// Monta o ID de documento Firestore para venda paga via MP (idempotente por pagamento).
String mpVendaFirestoreDocumentId({
  required String orderId,
  required String paymentId,
}) {
  final o = orderId.trim();
  final p = paymentId.trim();
  return '$kMpVendaDocPrefix${o}_$p';
}

/// `true` se [docId] segue o padrão canônico MP (não é UUID).
bool isMpCanonicalVendaDocId(String? docId) {
  final s = docId?.trim() ?? '';
  if (s.length < 8) return false;
  if (!s.startsWith(kMpVendaDocPrefix)) return false;
  // mp_<orderId>_<paymentId> — evita confundir com outros prefixos
  return s.substring(kMpVendaDocPrefix.length).contains('_');
}
