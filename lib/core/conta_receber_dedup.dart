// Dedupe semântico de contas a receber (legado vs canônico, Hive antigo vs remoto).

import '../models/conta_receber.dart';
import 'conta_receber_identity.dart';
import 'conta_receber_lancamento_vinculo.dart';

/// Chave semântica única por parcela/título (exibição e anti-duplicata).
String contaReceberChaveSemantica(ContaReceber conta) {
  final stable = contaReceberStableId(conta);
  if (stable.isNotEmpty) return 'v:$stable';

  final legacyInput = legacyContaReceberHashInput(conta);
  if (legacyInput.isNotEmpty) return 'l:${fnv1a32(legacyInput)}';

  final docId = resolveContaReceberDocId(conta);
  if (docId.isNotEmpty) return 'd:$docId';

  return '';
}

/// Chave fraca: cliente + valor + vencimento + parcela (casa legado sem vendaId vs canônico).
String contaReceberChaveFraca(ContaReceber conta) {
  final loja = conta.lojaId.trim();
  if (loja.isEmpty) return '';
  final nome = conta.clienteNome.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (nome.isEmpty) return '';
  final cents = ((conta.valorOriginal > 1e-9 ? conta.valorOriginal : conta.valor) * 100)
      .round();
  if (cents <= 0) return '';
  final venc = conta.dataVencimento;
  final vencStr =
      '${venc.year}-${venc.month.toString().padLeft(2, '0')}-${venc.day.toString().padLeft(2, '0')}';
  final p = conta.parcelaNumero.clamp(1, 999);
  return 'f:$loja|$nome|$cents|$vencStr|$p';
}

/// Conta quitada, cancelada ou sem saldo — não republicar nem backfill.
bool contaReceberInativaParaSync(ContaReceber conta) {
  conta.normalizarCamposFinanceiros();
  if (conta.pago || conta.saldoRestante < 0.01) return true;
  final st = conta.status.trim().toLowerCase();
  return st == ContaReceberStatus.paga ||
      st == ContaReceberStatus.cancelada ||
      st == ContaReceberStatus.estornada;
}

bool contaReceberElegivelParaPublicarHive(ContaReceber conta) {
  if (contaReceberInativaParaSync(conta)) return false;
  return contaReceberDocIdDeterministico(conta);
}

/// Preferência: canônico (vendaId+parcela) > id estável > legado.
int _scorePreferenciaExibicao(ContaReceber conta) {
  var score = 0;
  if (conta.vendaIdFirebase.trim().isNotEmpty) score += 100;
  final id = (conta.idFirebase ?? '').trim();
  if (id.isNotEmpty) score += 20;
  if (id.startsWith('cr_') && !id.startsWith('cr_legacy_')) score += 50;
  if (conta.valorPago > 0.01) score += 5;
  return score;
}

/// Remove duplicatas semânticas (legado + canônico da mesma parcela).
List<ContaReceber> deduplicarContasReceber(List<ContaReceber> contas) {
  final porChave = <String, ContaReceber>{};
  for (final c in contas) {
    final fraca = contaReceberChaveFraca(c);
    final chave = fraca.isNotEmpty ? fraca : contaReceberChaveSemantica(c);
    if (chave.isEmpty) {
      porChave['__orphan_${porChave.length}_${c.hashCode}'] = c;
      continue;
    }
    final existente = porChave[chave];
    if (existente == null ||
        _scorePreferenciaExibicao(c) > _scorePreferenciaExibicao(existente)) {
      porChave[chave] = c;
    }
  }
  return porChave.values.toList();
}

/// Verifica se já existe conta local para a mesma parcela (doc, stable ou legado).
bool hiveJaTemContaSemantica({
  required Iterable<ContaReceber> contas,
  required String lojaId,
  required ContaReceber candidata,
}) {
  final docAlvo = resolveContaReceberDocId(candidata);
  final chaveAlvo = contaReceberChaveSemantica(candidata);
  for (final c in contas) {
    if (c.lojaId.trim() != lojaId.trim() && c.lojaId.trim().isNotEmpty) {
      continue;
    }
    if (docAlvo.isNotEmpty && resolveContaReceberDocId(c) == docAlvo) {
      return true;
    }
    if (chaveAlvo.isNotEmpty && contaReceberChaveSemantica(c) == chaveAlvo) {
      return true;
    }
  }
  return false;
}
