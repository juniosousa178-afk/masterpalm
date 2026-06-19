// Regras para identificar contas a receber recuperadas/manuais elegíveis à exclusão.

import '../models/conta_receber.dart';

/// Marcadores amplos de recuperação (inclui texto genérico "recuperacao").
bool contaReceberTemMarcadorRecuperacao(ContaReceber conta) {
  final texto =
      '${conta.observacao} ${conta.clienteNome}'.toLowerCase().trim();
  if (texto.isEmpty) return false;
  if (texto.contains('venda recuperada manualmente')) return true;
  if (texto.contains('recuperação assistida')) return true;
  if (texto.contains('recuperacao assistida')) return true;
  if (texto.contains('recuperacao_script')) return true;
  if (texto.contains('sem baixa de estoque')) return true;
  if (texto.contains('perda durante edição')) return true;
  if (texto.contains('perda durante edicao')) return true;
  if (texto.contains('recuperacao')) return true;
  return false;
}

/// Marcadores fortes — permitem excluir somente a CR mesmo com vendaId/vendaKey antigo.
bool contaReceberTemMarcadorForteRecuperacao(ContaReceber conta) {
  final texto =
      '${conta.observacao} ${conta.clienteNome}'.toLowerCase().trim();
  if (texto.isEmpty) return false;
  if (texto.contains('venda recuperada manualmente')) return true;
  if (texto.contains('recuperação assistida')) return true;
  if (texto.contains('recuperacao assistida')) return true;
  if (texto.contains('recuperacao_script')) return true;
  if (texto.contains('sem baixa de estoque')) return true;
  if (texto.contains('perda durante edição')) return true;
  if (texto.contains('perda durante edicao')) return true;
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

/// Modal específico para contas com marcador forte de recuperação.
bool contaReceberUsarModalRecuperada(ContaReceber conta) =>
    contaReceberTemMarcadorForteRecuperacao(conta);
