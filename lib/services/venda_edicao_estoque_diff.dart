// Diff de linhas de estoque canônicas para edição de venda (delta baixa/devolução).

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

import '../models/venda_item.dart';
import 'estoque_transaction_service.dart';

/// Resultado do diff: itens a baixar (+) e devolver (-) em relação à venda original.
class VendaEdicaoDeltaEstoque {
  final List<Map<String, dynamic>> baixar;
  final List<Map<String, dynamic>> devolver;

  const VendaEdicaoDeltaEstoque({
    required this.baixar,
    required this.devolver,
  });

  bool get semMovimento => baixar.isEmpty && devolver.isEmpty;
}

/// Compara itens de venda e calcula delta de estoque após expansão canônica (combo/variação).
class VendaEdicaoEstoqueDiff {
  VendaEdicaoEstoqueDiff._();

  static const _deepEq = DeepCollectionEquality();

  /// Linhas de venda + seleção de combo iguais → nenhuma movimentação de estoque.
  static bool itensVendaEquivalentes({
    required List<VendaItem> antigos,
    required List<VendaItem> novos,
    required String? comboJsonAntigo,
    required String? comboJsonNovo,
  }) {
    if (antigos.length != novos.length) return false;
    for (var i = 0; i < antigos.length; i++) {
      if (!_itemEquivale(antigos[i], novos[i])) return false;
    }
    return _comboJsonEquivalente(comboJsonAntigo, comboJsonNovo);
  }

  static bool _itemEquivale(VendaItem a, VendaItem b) {
    return a.produtoNome.trim().toLowerCase() ==
            b.produtoNome.trim().toLowerCase() &&
        (a.productId ?? '').trim() == (b.productId ?? '').trim() &&
        a.quantidade == b.quantidade &&
        a.tamanho.trim() == b.tamanho.trim() &&
        a.cor.trim() == b.cor.trim() &&
        a.extraValor.trim() == b.extraValor.trim();
  }

  static bool _comboJsonEquivalente(String? a, String? b) {
    final na = (a ?? '').trim();
    final nb = (b ?? '').trim();
    if (na.isEmpty && nb.isEmpty) return true;
    if (na.isEmpty || nb.isEmpty) return false;
    try {
      final da = jsonDecode(na);
      final db = jsonDecode(nb);
      return _deepEq.equals(da, db);
    } catch (_) {
      return na == nb;
    }
  }

  static String _chaveLinha(Map<String, dynamic> m) {
    final pid = (m['productId'] ?? '').toString().trim();
    final slug = (m['slug'] ?? '').toString().trim().toLowerCase();
    final nome = (m['nome'] ?? '').toString().trim().toLowerCase();
    final tam = (m['tamanho'] ?? '').toString().trim();
    final cor = (m['cor'] ?? '').toString().trim();
    final extra = (m['extraValor'] ?? '').toString().trim();
    return '$pid\x00$slug\x00$nome\x00$tam\x00$cor\x00$extra';
  }

  /// Calcula delta entre mapas canônicos (mesmo formato de baixa/devolução Firestore).
  static VendaEdicaoDeltaEstoque calcularDelta({
    required List<Map<String, dynamic>> linhasAntigas,
    required List<Map<String, dynamic>> linhasNovas,
  }) {
    final antigo = <String, int>{};
    final novo = <String, int>{};
    final meta = <String, Map<String, dynamic>>{};

    void acumular(List<Map<String, dynamic>> linhas, Map<String, int> alvo) {
      for (final m in linhas) {
        final q = (m['quantidade'] as num?)?.toInt() ?? 0;
        if (q <= 0) continue;
        final k = _chaveLinha(m);
        alvo[k] = (alvo[k] ?? 0) + q;
        meta.putIfAbsent(
          k,
          () {
            final base = Map<String, dynamic>.from(m);
            base.remove('quantidade');
            return base;
          },
        );
      }
    }

    acumular(linhasAntigas, antigo);
    acumular(linhasNovas, novo);

    final baixar = <Map<String, dynamic>>[];
    final devolver = <Map<String, dynamic>>[];
    for (final k in {...antigo.keys, ...novo.keys}) {
      final delta = (novo[k] ?? 0) - (antigo[k] ?? 0);
      if (delta == 0) continue;
      final base = Map<String, dynamic>.from(meta[k] ?? {});
      if (delta > 0) {
        baixar.add({...base, 'quantidade': delta});
      } else {
        devolver.add({...base, 'quantidade': -delta});
      }
    }

    return VendaEdicaoDeltaEstoque(baixar: baixar, devolver: devolver);
  }

  /// Delta assinado canônico: `+` devolve estoque, `-` baixa. Agrega e remove zeros.
  /// Ordenação determinística por [_chaveLinha] (hash estável independente da ordem de entrada).
  static List<Map<String, dynamic>> linhasAssinadasCanonicas(
    VendaEdicaoDeltaEstoque delta,
  ) {
    final acc = <String, Map<String, dynamic>>{};

    void acumular(Map<String, dynamic> m, int signedQty) {
      if (signedQty == 0) return;
      final k = _chaveLinha(m);
      final existing = acc[k];
      if (existing == null) {
        final base = Map<String, dynamic>.from(m);
        base['quantidade'] = signedQty;
        acc[k] = base;
      } else {
        final novo = (existing['quantidade'] as num).toInt() + signedQty;
        if (novo == 0) {
          acc.remove(k);
        } else {
          existing['quantidade'] = novo;
        }
      }
    }

    for (final m in delta.devolver) {
      final q = (m['quantidade'] as num?)?.toInt() ?? 0;
      acumular(m, q);
    }
    for (final m in delta.baixar) {
      final q = (m['quantidade'] as num?)?.toInt() ?? 0;
      acumular(m, -q);
    }

    final lines = acc.values.toList()
      ..sort((a, b) => _chaveLinha(a).compareTo(_chaveLinha(b)));
    return lines;
  }

  /// Hash determinístico do delta assinado (família de [EstoqueTransactionService.computeTxItemsHashForIdempotencia]).
  static String computeCanonicalDeltaHash(VendaEdicaoDeltaEstoque delta) {
    return EstoqueTransactionService.computeSignedTxItemsHashForIdempotencia(
      linhasAssinadasCanonicas(delta),
    );
  }

  static String buildEditStockOperationId({
    required String vendaId,
    required String deltaHash,
  }) {
    final vid = vendaId.trim();
    final hash = deltaHash.trim();
    return 'editstock_${vid}_$hash';
  }

  /// Chave de journal: `loja|deltaHash|edit|{vendaId}` via [saleIntentId].
  static String buildEditStockJournalSaleIntentId(String vendaId) =>
      'edit|${vendaId.trim()}';

  static final _espacos = RegExp(r'\s+', unicode: true);

  static String _normKey(Object? v) =>
      (v ?? '').toString().trim().toLowerCase().replaceAll(_espacos, ' ');

  /// Identidade de estoque de uma linha (espelho de `lineKey` no servidor).
  static List<String> saleEditLineKey({
    required String? productId,
    required String produtoNome,
    required String tamanho,
    required String cor,
    required String extraValor,
  }) {
    final pid = (productId ?? '').trim();
    return [
      pid,
      pid.isNotEmpty ? '' : _normKey(produtoNome),
      _normKey(tamanho),
      _normKey(cor),
      _normKey(extraValor),
    ];
  }

  /// Hash CAS das linhas da venda, independente da ordem.
  /// Deve produzir o mesmo valor que `saleLinesHash` em `functions/src/stockCatalogSaleEdit.js`.
  static String saleEditLinesHash(List<VendaItem> itens) {
    final qtyPorChave = <String, int>{};
    final chaves = <String, List<String>>{};
    for (final it in itens) {
      if (it.quantidade <= 0) continue;
      final key = saleEditLineKey(
        productId: it.productId,
        produtoNome: it.produtoNome,
        tamanho: it.tamanho,
        cor: it.cor,
        extraValor: it.extraValor,
      );
      final id = jsonEncode(key);
      chaves.putIfAbsent(id, () => key);
      qtyPorChave[id] = (qtyPorChave[id] ?? 0) + it.quantidade;
    }
    final ids = qtyPorChave.keys.where((id) => qtyPorChave[id]! > 0).toList()
      ..sort();
    final rows = [
      for (final id in ids) [...chaves[id]!, qtyPorChave[id]!],
    ];
    return sha256.convert(utf8.encode(jsonEncode(rows))).toString();
  }

  /// Delta líquido por produto entre linhas salvas e editadas (`+` baixa, `-` devolve).
  /// Só linhas com productId; usado para o histórico de movimentações (derivado).
  static Map<String, ({int quantidade, String produtoNome})>
      saleEditDeltaPorProduto({
    required List<VendaItem> antigos,
    required List<VendaItem> novos,
  }) {
    final out = <String, ({int quantidade, String produtoNome})>{};
    void somar(List<VendaItem> itens, int sinal) {
      for (final it in itens) {
        final pid = (it.productId ?? '').trim();
        if (pid.isEmpty || it.quantidade <= 0) continue;
        final prev = out[pid];
        out[pid] = (
          quantidade: (prev?.quantidade ?? 0) + sinal * it.quantidade,
          produtoNome: prev?.produtoNome ?? it.produtoNome,
        );
      }
    }

    somar(novos, 1);
    somar(antigos, -1);
    out.removeWhere((_, v) => v.quantidade == 0);
    return out;
  }

  /// Id determinístico do comando `saleEdit`: o mesmo pedido de edição (sessão + conteúdo)
  /// reenviado após falha de rede é idempotente; outra sessão gera outro id.
  static String buildSaleEditOperationId({
    required String lojaId,
    required String saleId,
    required String editIntentId,
    required String originalLinesHash,
    required Map<String, dynamic> salePayload,
  }) {
    final payloadHash =
        sha256.convert(utf8.encode(jsonEncode(salePayload))).toString();
    final raw = [
      lojaId.trim(),
      saleId.trim(),
      editIntentId.trim(),
      originalLinesHash,
      payloadHash,
    ].join('|');
    return 'saleedit_${sha256.convert(utf8.encode(raw))}';
  }
}

/// Resultado da validação pré-salvamento na UI (edição de venda).
class VendaEdicaoValidacaoPreSalvamentoUi {
  /// `true` = edição administrativa; não validar estoque na tela.
  final bool pularValidacaoEstoque;

  /// Linhas canônicas cuja baixa (delta) exige checagem de estoque disponível.
  final List<Map<String, dynamic>> linhasValidarBaixa;

  const VendaEdicaoValidacaoPreSalvamentoUi({
    required this.pularValidacaoEstoque,
    required this.linhasValidarBaixa,
  });
}
