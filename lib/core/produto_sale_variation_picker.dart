// Opções elegíveis do seletor de variação na venda (somente qty > 0).

import '../models/produto.dart';
import 'produto_variacao_extra.dart';

/// Célula vendável (qty > 0) para o picker de Nova Venda.
class ProdutoSaleVariationOption {
  const ProdutoSaleVariationOption({
    required this.tamanho,
    required this.cor,
    required this.qty,
    this.extraValor = '',
  });

  final String tamanho;
  final String cor;
  final int qty;
  final String extraValor;

  String get variationKey {
    final tam = tamanho.isEmpty ? 'sem-tamanho' : tamanho;
    final c = cor.isEmpty ? 'sem-cor' : cor;
    if (extraValor.trim().isEmpty) return '$tam|$c';
    return '$tam|$c|${extraValor.trim()}';
  }

  /// Ex.: `13 (1)`, `P/Dourado (2)`.
  String get label {
    final parts = <String>[
      if (tamanho.isNotEmpty && tamanho != 'sem-tamanho') tamanho,
      if (cor.isNotEmpty && cor != 'sem-cor') cor,
      if (extraValor.trim().isNotEmpty) extraValor.trim(),
    ];
    final head = parts.isEmpty ? 'Único' : parts.join('/');
    return '$head ($qty)';
  }
}

/// Soma canônica das células de variação (0 se não houver grade).
int produtoVariationCellSum(Produto p) {
  if (p.usaVariacoes && p.variacoes != null) {
    var sum = 0;
    p.variacoes!.forEach((_, cores) {
      if (cores is! Map) return;
      for (final cell in cores.values) {
        sum += ProdutoVariacaoExtra.somarCelula(cell);
      }
    });
    return sum;
  }
  if (p.estoquePorTamanho.isNotEmpty) {
    return p.estoquePorTamanho.values.fold<int>(0, (a, b) => a + b);
  }
  return 0;
}

/// Identidades de variação conhecidas (tamanhos/cores/células), independente de qty.
bool produtoHasVariationIdentities(Produto p) {
  if (p.usaVariacoes) return true;
  if (p.estoquePorTamanho.isNotEmpty) return true;
  if (p.tamanhos.any((t) => t.trim().isNotEmpty)) return true;
  return false;
}

/// Tamanhos com qty > 0 (mesma regra do sheet de venda).
Map<String, int> produtoSaleTamanhosComEstoque(Produto p) {
  if (p.usaVariacoes && p.variacoes != null) {
    final result = <String, int>{};
    p.variacoes!.forEach((tamanho, cores) {
      if (tamanho == 'sem-tamanho') return;
      if (cores is! Map) return;
      var total = 0;
      for (final qtd in cores.values) {
        total += ProdutoVariacaoExtra.somarCelula(qtd);
      }
      if (total > 0) result[tamanho.toString()] = total;
    });
    if (result.isNotEmpty) return result;
  }
  final fromEstoque = <String, int>{};
  p.estoquePorTamanho.forEach((k, v) {
    if (v > 0) fromEstoque[k.toString()] = v;
  });
  return fromEstoque;
}

/// Opções do picker: somente células com qty > 0.
List<ProdutoSaleVariationOption> produtoSaleVariationPickerOptions(Produto p) {
  final out = <ProdutoSaleVariationOption>[];
  if (p.usaVariacoes && p.variacoes != null) {
    p.variacoes!.forEach((tamanho, cores) {
      if (cores is! Map) return;
      cores.forEach((cor, cell) {
        if (ProdutoVariacaoExtra.isMetaKey(cor.toString())) return;
        final qty = ProdutoVariacaoExtra.somarCelula(cell);
        if (qty <= 0) return;
        if (cell is Map) {
          for (final e in cell.entries) {
            final key = e.key.toString();
            if (ProdutoVariacaoExtra.isMetaKey(key)) continue;
            final q = e.value is num
                ? (e.value as num).toInt()
                : int.tryParse(e.value?.toString() ?? '') ?? 0;
            if (q <= 0) continue;
            final ev = ProdutoVariacaoExtra.isSemExtraMapKey(key) ? '' : key;
            out.add(
              ProdutoSaleVariationOption(
                tamanho: tamanho.toString(),
                cor: cor.toString(),
                qty: q,
                extraValor: ev,
              ),
            );
          }
        } else {
          out.add(
            ProdutoSaleVariationOption(
              tamanho: tamanho.toString(),
              cor: cor.toString(),
              qty: qty,
            ),
          );
        }
      });
    });
    return out;
  }
  p.estoquePorTamanho.forEach((k, v) {
    if (v <= 0) return;
    out.add(ProdutoSaleVariationOption(tamanho: k.toString(), cor: '', qty: v));
  });
  return out;
}

/// Variações cadastradas mas nenhuma com quantidade > 0 → mensagem de configuração.
bool produtoVariationStockNeedsConfiguration(Produto p) {
  if (!produtoHasVariationIdentities(p)) return false;
  return produtoSaleVariationPickerOptions(p).isEmpty;
}

const kProdutoVariationStockUnconfiguredMessage =
    'Estoque por variação não configurado. Confira as quantidades dos tamanhos/cores.';
