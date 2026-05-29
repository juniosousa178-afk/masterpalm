// Idempotência: uma conta a pagar = no máximo um lançamento financeiro vinculado.

import '../financeiro/financeiro_constants.dart';
import '../models/lancamento_financeiro.dart';

String lancamentoFinanceiroDocIdParaContaPagar(String contaPagarId) {
  final c = contaPagarId.trim();
  if (c.isEmpty) return 'mp_cp_invalido';
  return 'mp_cp_$c';
}

String referenciaExternaContaPagar({
  required String contaPagarId,
  required String compraId,
}) {
  final cp = contaPagarId.trim();
  final cid = compraId.trim();
  return 'cp_pag:$cp:compra:$cid';
}

/// Lançamento gerado ao pagar parcela em Contas a Pagar.
bool lancamentoVinculadoAContaPagar(LancamentoFinanceiro l) {
  if (l.origem == FinanceiroOrigemLancamento.contaPagarCompra) return true;
  final id = l.id.trim();
  if (id.startsWith('mp_cp_')) return true;
  if (l.referenciaExterna.trim().startsWith('cp_pag:')) return true;
  return false;
}

/// Resolve o id da [ContaPagar] a partir do lançamento vinculado.
String? contaPagarIdFromLancamento(LancamentoFinanceiro l) {
  final id = l.id.trim();
  if (id.startsWith('mp_cp_')) {
    final cpId = id.substring('mp_cp_'.length).trim();
    if (cpId.isNotEmpty) return cpId;
  }
  final ref = l.referenciaExterna.trim();
  if (!ref.startsWith('cp_pag:')) return null;
  final parts = ref.split(':');
  if (parts.length >= 2 && parts[1].trim().isNotEmpty) {
    return parts[1].trim();
  }
  return null;
}
