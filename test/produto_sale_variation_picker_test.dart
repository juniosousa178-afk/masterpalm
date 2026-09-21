import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_sale_variation_picker.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';

Produto _base({
  Map<String, dynamic>? variacoes,
  Map<String, int> estoquePorTamanho = const {},
  List<String> tamanhos = const [],
  int quantidade = 0,
}) {
  return Produto(
    nome: 'Produto Var Teste',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: quantidade,
    precoUnitario: 50,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 9, 1),
    descricao: 'teste',
    lojaId: 'loja-teste',
    idFirebase: 'prod-var-sale',
    slug: 'prod-var-sale',
    variacoes: variacoes,
    estoquePorTamanho: estoquePorTamanho,
    tamanhos: tamanhos,
  );
}

Map<String, dynamic> _cell(int qty) => {
      ProdutoVariacaoExtra.kSemExtraKey: qty,
    };

void main() {
  group('sale variation picker — qty > 0 only', () {
    test('tamanhos 13-19 todos qty 0 → configuração necessária', () {
      final p = _base(
        quantidade: 0,
        tamanhos: const ['13', '14', '15', '16', '17', '18', '19'],
        variacoes: {
          for (final t in ['13', '14', '15', '16', '17', '18', '19'])
            t: {'sem-cor': _cell(0)},
        },
      );
      expect(produtoVariationStockNeedsConfiguration(p), isTrue);
      expect(produtoSaleVariationPickerOptions(p), isEmpty);
      expect(
        kProdutoVariationStockUnconfiguredMessage,
        contains('não configurado'),
      );
    });

    test('13=1 / 14=0 / 15=2 → picker só 13 e 15; aggregate=3', () {
      final p = _base(
        quantidade: 3,
        variacoes: {
          '13': {'sem-cor': _cell(1)},
          '14': {'sem-cor': _cell(0)},
          '15': {'sem-cor': _cell(2)},
        },
      );
      final opts = produtoSaleVariationPickerOptions(p);
      expect(opts.map((o) => o.tamanho).toList(), ['13', '15']);
      expect(opts.map((o) => o.qty).toList(), [1, 2]);
      expect(produtoVariationCellSum(p), 3);
      expect(produtoSaleTamanhosComEstoque(p).keys.toList(), ['13', '15']);
      expect(produtoVariationStockNeedsConfiguration(p), isFalse);
    });

    test('venda 13 qty1 reduz célula; 15 permanece; aggregate 2', () {
      final p = _base(
        quantidade: 3,
        variacoes: {
          '13': {'sem-cor': _cell(1)},
          '15': {'sem-cor': _cell(2)},
        },
      );
      p.debitarEstoqueVariacao('13', 'sem-cor', 1);
      expect(p.obterEstoqueVariacao('13', 'sem-cor'), 0);
      expect(p.obterEstoqueVariacao('15', 'sem-cor'), 2);
      expect(produtoVariationCellSum(p), 2);
      expect(p.quantidade, 2);
      final opts = produtoSaleVariationPickerOptions(p);
      expect(opts.map((o) => o.tamanho).toList(), ['15']);
    });

    test('grade P/Dourado P/Prata M/Dourado M/Prata — só >0 na venda', () {
      final p = _base(
        quantidade: 5,
        variacoes: {
          'P': {
            'Dourado': _cell(2),
            'Prata': _cell(0),
          },
          'M': {
            'Dourado': _cell(1),
            'Prata': _cell(2),
          },
        },
      );
      final opts = produtoSaleVariationPickerOptions(p);
      expect(opts.length, 3);
      expect(
        opts.map((o) => '${o.tamanho}/${o.cor}:${o.qty}').toList(),
        ['P/Dourado:2', 'M/Dourado:1', 'M/Prata:2'],
      );
      expect(produtoVariationCellSum(p), 5);
    });

    test('14=1 15=0 18=1 21=1 → sale options 14/18/21; sum=3', () {
      final p = _base(
        quantidade: 3,
        variacoes: {
          '14': {'sem-cor': _cell(1)},
          '15': {'sem-cor': _cell(0)},
          '18': {'sem-cor': _cell(1)},
          '21': {'sem-cor': _cell(1)},
        },
      );
      expect(produtoVariationCellSum(p), 3);
      final opts = produtoSaleVariationPickerOptions(p);
      expect(opts.map((o) => o.label).toList(), [
        '14 (1)',
        '18 (1)',
        '21 (1)',
      ]);
      expect(opts.any((o) => o.tamanho == '15'), isFalse);
      expect(p.quantidade, 3);
    });
  });
}
