// Idempotência: recebimento de conta a receber → lançamento financeiro vinculado.

import '../financeiro/financeiro_constants.dart';
import '../models/lancamento_financeiro.dart';

/// Documento canônico em `lancamentos_financeiros` para um recebimento.
/// Inclui valor (centavos) e dia para permitir parcelas parciais distintas.
String lancamentoFinanceiroDocIdParaContaReceber({
  required int contaHiveKey,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
}) {
  final key = contaHiveKey;
  if (key < 0) return 'mp_cr_invalido';
  final cents = (valor.abs() * 100).round();
  final d = dataRecebimento;
  final dia =
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  return 'mp_cr_${key}_${parcelaNumero.clamp(1, 999)}_${cents}_$dia';
}

String referenciaExternaContaReceber({
  required int contaHiveKey,
  required int parcelaNumero,
  required double valor,
  required DateTime dataRecebimento,
}) {
  final cents = (valor.abs() * 100).round();
  final d = dataRecebimento;
  final dia =
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  return 'cr_receb:$contaHiveKey:$parcelaNumero:$cents:$dia';
}

bool lancamentoVinculadoAContaReceber(LancamentoFinanceiro l) {
  if (l.origem == FinanceiroOrigemLancamento.contaReceberFiado) return true;
  return l.referenciaExterna.trim().startsWith('cr_receb:');
}

bool lancamentoIdContaReceber(String id) {
  return id.trim().startsWith('mp_cr_');
}
