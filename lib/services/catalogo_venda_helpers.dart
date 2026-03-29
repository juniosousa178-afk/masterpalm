/// Helpers puros de texto e formatação usados por `CatalogoVendaService`.
/// Não fazem I/O nem acessam Firestore/Hive.
library;

import '../core/produto_variacao_extra.dart';

/// Gera descrição dos produtos para o campo `produtosDescricao`
/// a partir da lista de itens do catálogo.
String gerarDescricaoProdutos(List<Map<String, dynamic>> items) {
  final buffer = StringBuffer();
  for (int i = 0; i < items.length; i++) {
    final item = items[i];
    final name = (item['nome'] ?? item['name'] ?? '').toString();
    final qty = (item['quantidade'] as int?) ?? (item['qty'] as int?) ?? 1;
    final tamanho = (item['tamanho'] ?? item['size'] ?? '').toString().trim();
    final cor = (item['cor'] ?? item['color'] ?? '').toString().trim();
    final extra =
        ProdutoVariacaoExtra.resumoExtraLinhaDeItemMap(item);

    buffer.write('$name x$qty');

    // Adicionar variações se existirem
    if (tamanho.isNotEmpty || cor.isNotEmpty || extra.isNotEmpty) {
      final variacoes = <String>[];
      if (tamanho.isNotEmpty) variacoes.add('Tam: $tamanho');
      if (cor.isNotEmpty) variacoes.add('Cor: $cor');
      if (extra.isNotEmpty) variacoes.add(extra);
      buffer.write(' (${variacoes.join(', ')})');
    }

    if (i < items.length - 1) {
      buffer.write(', ');
    }
  }
  return buffer.toString();
}

/// Determina o tipo de prêmio da roleta a partir da descrição/código/desconto.
String determinarTipoPremio(String? descricao, String? codigo, double? desconto) {
  if (descricao == null && codigo == null) return 'nenhum';

  final desc = (descricao ?? '').toLowerCase();

  // Verificar se é brinde
  if (desc.contains('brinde') ||
      desc.contains('mimo') ||
      desc.contains('chaveiro') ||
      desc.contains('presente') ||
      desc.contains('adesivo')) {
    return 'brinde';
  }

  // Verificar se é frete grátis
  if (desc.contains('frete') && desc.contains('gr')) {
    return 'frete_gratis';
  }

  // Verificar se é desconto
  if (codigo != null && desconto != null && desconto > 0) {
    return 'desconto';
  }

  // Se tem cupom mas não identificou o tipo, assume desconto
  if (codigo != null) {
    return 'desconto';
  }

  return 'nenhum';
}

/// Gera descrição dos produtos a partir dos itens do pedido (pós-processado).
String gerarDescricaoProdutosFromItens(List<Map<String, dynamic>> itens) {
  final buffer = StringBuffer();
  for (int i = 0; i < itens.length; i++) {
    final item = itens[i];
    final name = (item['nome'] ?? '').toString();
    final qty = (item['quantidade'] as num?)?.toInt() ?? 1;
    final tamanho = (item['tamanho'] ?? '').toString().trim();
    final cor = (item['cor'] ?? '').toString().trim();
    final extra =
        ProdutoVariacaoExtra.resumoExtraLinhaDeItemMap(item);

    buffer.write('$name x$qty');

    // Adicionar variações se existirem
    if (tamanho.isNotEmpty || cor.isNotEmpty || extra.isNotEmpty) {
      final variacoes = <String>[];
      if (tamanho.isNotEmpty) variacoes.add('Tam: $tamanho');
      if (cor.isNotEmpty) variacoes.add('Cor: $cor');
      if (extra.isNotEmpty) variacoes.add(extra);
      buffer.write(' (${variacoes.join(', ')})');
    }

    if (i < itens.length - 1) {
      buffer.write(', ');
    }
  }
  return buffer.toString();
}

