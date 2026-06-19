// Regras para identificar contas a receber recuperadas/manuais elegíveis à exclusão.

import '../models/conta_receber.dart';

/// Marcadores de recuperação assistida / script / manual pós-perda.
bool contaReceberTemMarcadorRecuperacao(ContaReceber conta) {
  final texto =
      '${conta.observacao} ${conta.clienteNome}'.toLowerCase().trim();
  if (texto.isEmpty) return false;
  if (texto.contains('venda recuperada manualmente')) return true;
  if (texto.contains('recuperação assistida')) return true;
  if (texto.contains('recuperacao assistida')) return true;
  if (texto.contains('recuperacao_script')) return true;
  if (texto.contains('recuperacao')) return true;
  return false;
}

/// Conta criada manualmente na tela (sem vínculo de venda fiada).
bool contaReceberEhManualSemVenda(ContaReceber conta) {
  return conta.vendaIdFirebase.trim().isEmpty && conta.vendaKey <= 0;
}

/// Conta recuperada ou manual — candidata à exclusão segura na tela CR.
bool contaReceberEhRecuperadaOuManual(ContaReceber conta) {
  return contaReceberTemMarcadorRecuperacao(conta) ||
      contaReceberEhManualSemVenda(conta);
}

/// Exibe botão "Excluir conta" no card (heurística síncrona; confirmação async no clique).
bool contaReceberMostrarAcaoExcluir(ContaReceber conta) {
  if (conta.status.trim().toLowerCase() == 'cancelada') return false;
  return contaReceberEhRecuperadaOuManual(conta);
}
