// Diff de linhas de estoque canônicas para edição de venda (delta baixa/devolução).

import 'dart:convert';

import 'package:collection/collection.dart';

import '../models/venda_item.dart';

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
}
