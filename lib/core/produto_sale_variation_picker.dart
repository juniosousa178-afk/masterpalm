// Opções elegíveis do seletor de variação na venda (somente qty > 0).

import '../models/produto.dart';
import 'produto_effective_stock.dart';
import 'produto_estoque_grade_snapshot.dart';
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

/// Soma canônica das células de variação (aliases sem-cor normalizados).
int produtoVariationCellSum(Produto p) {
  final cells = normalizeSemCorAliasCells(
    ProdutoEstoqueGradeSnapshot.fromProduto(p).cells,
  );
  return sumNormalizedCells(cells);
}

/// Identidades de variação cadastradas (inclui qty 0 — para “não configurado”).
/// Não basta lista `tamanhos`. Célula agregada `sem-tamanho|sem-cor` NÃO conta.
bool produtoHasVariationIdentities(Produto p) {
  // Usar células brutas: normalizeSemCorAliasCells descarta qty<=0 e apagaria
  // o sinal de “variação cadastrada sem estoque”.
  final cells = ProdutoEstoqueGradeSnapshot.fromProduto(p).cells;
  for (final key in cells.keys) {
    final parts = key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : '';
    final cor = parts.length > 1 ? parts[1] : '';
    final realTam = tam.isNotEmpty && tam != 'sem-tamanho';
    final realCor = cor.isNotEmpty && cor != 'sem-cor';
    if (realTam || realCor) return true;
  }
  return false;
}

/// Tamanhos com qty > 0 (mesma regra do sheet de venda).
Map<String, int> produtoSaleTamanhosComEstoque(Produto p) {
  final normalized = normalizeSemCorAliasCells(
    ProdutoEstoqueGradeSnapshot.fromProduto(p).cells,
  );
  final result = <String, int>{};
  for (final e in normalized.entries) {
    if (e.value <= 0) continue;
    final parts = e.key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : '';
    if (tam.isEmpty || tam == 'sem-tamanho') continue;
    result[tam] = (result[tam] ?? 0) + e.value;
  }
  return result;
}

/// Opções do picker: somente células com qty > 0 (aliases sem-cor normalizados).
List<ProdutoSaleVariationOption> produtoSaleVariationPickerOptions(Produto p) {
  final normalized = normalizeSemCorAliasCells(
    ProdutoEstoqueGradeSnapshot.fromProduto(p).cells,
  );
  final out = <ProdutoSaleVariationOption>[];
  for (final opt in saleOptionsFromNormalizedCells(normalized)) {
    out.add(
      ProdutoSaleVariationOption(
        tamanho: opt.tamanho,
        cor: opt.cor,
        qty: opt.qty,
      ),
    );
  }
  return out;
}

/// Variações cadastradas mas nenhuma com quantidade > 0 → mensagem de configuração.
bool produtoVariationStockNeedsConfiguration(Produto p) {
  if (!produtoHasVariationIdentities(p)) return false;
  return produtoSaleVariationPickerOptions(p).isEmpty;
}

const kProdutoVariationStockUnconfiguredMessage =
    'Estoque por variação não configurado. Confira as quantidades dos tamanhos/cores.';
