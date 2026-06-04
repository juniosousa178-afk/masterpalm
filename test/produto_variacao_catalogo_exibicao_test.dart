import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/core/produto_variacao_normalizer.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';

void main() {
  group('catálogo — variações reconstruídas', () {
    test('applyToCatalogProductMap cria variacoes a partir de estoquePorTamanho',
        () {
      final m = <String, dynamic>{
        'nome': 'Anel Aparador Cravejado',
        'quantidade': 12,
        'estoquePorTamanho': {
          '14': 2,
          '15': 1,
          '18': 3,
          '20': 2,
          '22': 1,
          '15/16': 3,
        },
      };

      ProdutoVariacaoNormalizer.applyToCatalogProductMap(m);

      final vars = m['variacoes'];
      expect(vars, isA<Map>());
      expect((vars as Map).keys, containsAll(['14', '15', '18', '20']));
      expect(m['estoquePorTamanho'], isA<Map>());
    });

    test('processStockFromFirestoreMap expõe variacoes para o seletor', () {
      final m = <String, dynamic>{
        'nome': 'Anel',
        'quantidade': 5,
        'estoquePorTamanho': {'14': 2, '16': 3},
        'publicadoNoCatalogo': true,
      };

      final stock = CatalogEstoqueHelper.processStockFromFirestoreMap(
        m,
        isCombo: false,
      );

      expect(stock.variacoes, isNotNull);
      expect(stock.variacoes!.keys, containsAll(['14', '16']));
      expect(stock.incluirNoCatalogo, isTrue);
    });

    test('variacoes existentes não são substituídas por estrutura pobre', () {
      final m = <String, dynamic>{
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
          },
        },
        'estoquePorTamanho': {'M': 5},
      };

      ProdutoVariacaoNormalizer.applyToCatalogProductMap(m);
      final azul = (m['variacoes'] as Map)['M'] as Map;
      expect(azul.containsKey('Azul'), isTrue);
    });

    test('produto simples sem estoque por tamanho não ganha variacoes fantasmas',
        () {
      final m = <String, dynamic>{
        'nome': 'Colar único',
        'quantidade': 3,
      };

      ProdutoVariacaoNormalizer.applyToCatalogProductMap(m);
      expect(m.containsKey('variacoes'), isFalse);
    });

    test('tamanhos com estoque zero entram no mapa quando não há estoque positivo',
        () {
      final m = <String, dynamic>{
        'estoquePorTamanho': {'14': 0, '16': 0},
        'tamanhos': ['14', '16'],
      };
      ProdutoVariacaoNormalizer.applyToCatalogProductMap(m);
      final vars = m['variacoes'] as Map?;
      expect(vars, isNotNull);
      expect(vars!.containsKey('14'), isTrue);
      expect(vars.containsKey('16'), isTrue);
    });
  });
}
