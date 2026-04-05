// lib/core/compra_financeiro_vinculo.dart
//
// Política ativa: `lib/services/compra_financeiro_integracao_service.dart`.
//
// Fase 3 (integração financeira): usar SEMPRE este id como documento em
// `lojas/{lojaId}/lancamentos_financeiros/{id}` com SetOptions(merge: true).
//
// Regra: nunca `collection.add()` para compra — apenas upsert por id fixo.
// Se [CompraFornecedor.idLancamentoFinanceiro] estiver preenchido, deve ser
// igual a [lancamentoFinanceiroDocIdParaCompra] salvo na primeira gravação.
//
// Idempotência: uma compra = no máximo um lançamento financeiro vinculado.

String lancamentoFinanceiroDocIdParaCompra(String compraId) {
  final c = compraId.trim();
  if (c.isEmpty) return 'mp_compra_invalido';
  return 'mp_compra_$c';
}
