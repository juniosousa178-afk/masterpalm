// M2.3-R6.1 — cópia profunda e imutabilidade de CatalogProductAddSeed.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_product_add_seed.dart';

void main() {
  test('mutações profundas após seed não alteram linha do carrinho', () {
    final imagens = <String>['imagem-b', 'imagem-b-alt'];
    final estoquePorTamanho = <String, int>{'variacao-b': 5};
    final estoquePorCor = <String, int>{'cor-b': 2};
    final precoPorTamanho = <String, double>{'variacao-b': 79.90};
    final variacoes = <String, dynamic>{
      'variacao-b': {
        'cor-b': 2,
        'opcoes': <String>['a', 'b'],
      },
      'sem-tamanho': <String, dynamic>{'cor-x': 1},
    };
    final variacoesExtraTipo = <String, dynamic>{
      'tipo1': {'labels': <String>['x', 'y']},
    };

    final seed = CatalogProductAddSeed(
      productId: 'produto-b',
      name: 'Colar Ponto de Luz Gota 45cm',
      price: 79.90,
      slug: 'colar-gota',
      percentualDescontoPix: 5,
      divideSemJuros: false,
      maxParcelas: 3,
      peso: 12,
      tipoEmbalagem: 'padrao',
      imagens: catalogProductAddSeedCopyStringList(imagens),
      imageUrl: 'imagem-b',
      minimalLayout: false,
      emPromocao: false,
      mostrarQuantidadeNoCatalogo: true,
      estoquePorTamanho: catalogProductAddSeedCopyIntMap(estoquePorTamanho),
      estoquePorCor: catalogProductAddSeedCopyIntMap(estoquePorCor),
      precoPorTamanho: catalogProductAddSeedCopyDoubleMap(precoPorTamanho),
      variacoes: catalogProductAddSeedCopyDynamicMap(variacoes),
      variacoesExtraTipo: catalogProductAddSeedCopyDynamicMap(variacoesExtraTipo),
    );

    final lineBefore = seed.buildCartLine(
      tamanho: 'variacao-b',
      cor: 'cor-b',
      preco: 79.90,
      extraValor: '',
      extraTipo: '',
      resumoExtra: '',
    );

    imagens[0] = 'mutada';
    imagens.add('nova');
    estoquePorTamanho['variacao-b'] = 0;
    estoquePorTamanho['novo'] = 99;
    estoquePorCor['cor-b'] = 0;
    precoPorTamanho['variacao-b'] = 1.0;
    (variacoes['variacao-b'] as Map)['cor-b'] = 999;
    ((variacoes['variacao-b'] as Map)['opcoes'] as List).add('c');
    variacoes['novo'] = 'x';
    (variacoesExtraTipo['tipo1'] as Map)['labels'] = <String>['z'];

    expect(seed.imagens.first, 'imagem-b');
    expect(seed.estoquePorTamanho['variacao-b'], 5);
    expect(seed.estoquePorCor['cor-b'], 2);
    expect(seed.precoPorTamanho!['variacao-b'], 79.90);
    expect(seed.variacoes!['variacao-b']['cor-b'], 2);
    expect((seed.variacoes!['variacao-b']['opcoes'] as List).length, 2);
    expect(seed.variacoesExtraTipo!['tipo1']['labels'], ['x', 'y']);

    final lineAfter = seed.buildCartLine(
      tamanho: 'variacao-b',
      cor: 'cor-b',
      preco: 79.90,
      extraValor: '',
      extraTipo: '',
      resumoExtra: '',
    );
    expect(lineAfter, lineBefore);
    expect(lineAfter['nome'], 'Colar Ponto de Luz Gota 45cm');
    expect(lineAfter['id'], 'produto-b');
  });
}
