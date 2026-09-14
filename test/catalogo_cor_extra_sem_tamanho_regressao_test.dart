import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';

void main() {
  test('cor independente continua compravel com bucket sem-tamanho', () {
    final p = <String, dynamic>{
      'variacoes': {'sem-tamanho': {'Azul': 0}},
      'estoquePorCor': {'Rosa': 2},
      'quantidade': 2,
    };
    final stock = CatalogEstoqueHelper.processStockFromFirestoreMap(p, isCombo: false);
    expect(stock.quantidadeTotal, 2);
    expect(stock.incluirNoCatalogo, isTrue);
    expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, '', 'Rosa'), 2);
    expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, 'sem-tamanho', 'Rosa'), 2);
    expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, 'P', 'Rosa'), 0);
    expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, '', 'Rosa', 'invalido'), 0);
  });

  test('cor zerada na grade nao herda agregado nem com caixa diferente', () {
    final p = <String, dynamic>{
      'variacoes': {'sem-tamanho': {'Azul': 0}},
      'estoquePorCor': {'Azul': 2},
      'quantidade': 2,
    };
    for (final tamanho in ['', 'sem-tamanho']) {
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, tamanho, 'Azul'), 0);
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, tamanho, 'azul'), 0);
    }
  });
}
