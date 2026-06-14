// IDs estáveis de contas a receber (Hive + Firestore).

import '../models/conta_receber.dart';
import 'conta_receber_lancamento_vinculo.dart';

const int kContaReceberSchemaVersion = 1;

/// FNV-1a 32-bit — hash determinístico sem dependência extra.
int fnv1a32(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

String _normalizarNomeCliente(String nome) =>
    nome.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Entrada estável para contas manuais sem [vendaIdFirebase].
String legacyContaReceberHashInput(ContaReceber conta) {
  final loja = conta.lojaId.trim();
  final nome = _normalizarNomeCliente(conta.clienteNome);
  if (loja.isEmpty || nome.isEmpty) return '';
  final cents = ((conta.valorOriginal > 1e-9 ? conta.valorOriginal : conta.valor) *
          100)
      .round();
  if (cents <= 0) return '';
  final venda =
      '${conta.dataVenda.year}-${conta.dataVenda.month.toString().padLeft(2, '0')}-${conta.dataVenda.day.toString().padLeft(2, '0')}';
  final venc =
      '${conta.dataVencimento.year}-${conta.dataVencimento.month.toString().padLeft(2, '0')}-${conta.dataVencimento.day.toString().padLeft(2, '0')}';
  final p = conta.parcelaNumero.clamp(1, 999);
  final pt = conta.parcelaTotal.clamp(1, 999);
  return '$loja|$nome|$cents|$venda|$venc|$p|$pt';
}

String legacyContaReceberDocId(ContaReceber conta) {
  final input = legacyContaReceberHashInput(conta);
  if (input.isEmpty) return '';
  final hex = fnv1a32(input).toRadixString(16).padLeft(8, '0');
  return 'cr_legacy_$hex';
}

/// Conta pode receber doc id determinístico (venda fiada ou legado seguro).
bool contaReceberDocIdDeterministico(ContaReceber conta) {
  if ((conta.idFirebase ?? '').trim().isNotEmpty) return true;
  if (conta.vendaIdFirebase.trim().isNotEmpty) return true;
  return legacyContaReceberHashInput(conta).isNotEmpty;
}

/// ID canônico do documento em `lojas/{lojaId}/contas_receber/{id}`.
String resolveContaReceberDocId(ContaReceber conta) {
  final existente = (conta.idFirebase ?? '').trim();
  if (existente.isNotEmpty) return existente;

  final stable = contaReceberStableId(conta);
  if (stable.isNotEmpty) {
    return 'cr_${stable.replaceAll('/', '_').replaceAll(':', '_')}';
  }

  final legacy = legacyContaReceberDocId(conta);
  if (legacy.isNotEmpty) return legacy;

  return '';
}

/// Garante [idFirebase] com id estável quando possível.
void normalizarContaReceberId(ContaReceber conta) {
  final docId = resolveContaReceberDocId(conta);
  if (docId.isEmpty) return;
  conta.garantirDocIdFirestore(docId);
}

String baixaIdDeterministico({
  required String contaReceberId,
  required double valor,
  required DateTime dataRecebimento,
  required String formaPagamento,
}) {
  final id = contaReceberId.trim();
  final cents = (valor.abs() * 100).round();
  final d = dataRecebimento;
  final dia =
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  final forma = formaPagamento.trim().toLowerCase().replaceAll(' ', '_');
  return 'bx_${id}_${cents}_${dia}_$forma';
}

/// Alias legível pedido na spec.
String resolveBaixaIdDeterministico({
  required ContaReceber conta,
  required double valor,
  required String formaPagamento,
  required DateTime dataRecebimento,
}) {
  final docId = resolveContaReceberDocId(conta);
  return baixaIdDeterministico(
    contaReceberId: docId,
    valor: valor,
    dataRecebimento: dataRecebimento,
    formaPagamento: formaPagamento,
  );
}
