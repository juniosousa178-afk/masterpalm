import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/core/produto_variacao_normalizer.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';

Produto _produto({
  Map<String, int>? estoquePorTamanho,
  List<String>? tamanhos,
  Map<String, dynamic>? variacoes,
}) {
  return Produto(
    nome: 'Anel Aparador Cravejado',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: 8,
    precoUnitario: 50,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: 'nathy_pratas_e_folheados',
    estoquePorTamanho: estoquePorTamanho ?? const {},
    tamanhos: tamanhos ?? const [],
    variacoes: variacoes,
  );
}

void main() {
  group('quantidade reidratada — ProdutoVariacaoNormalizer', () {
    test('estoquePorTamanho mapa simples gera grade com qtd real', () {
      final p = _produto(
        estoquePorTamanho: const {'14': 2, '15': 3},
      );
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 2);
      expect(rows.firstWhere((r) => r['tamanho'] == '14')['qtd'], '2');
      expect(rows.firstWhere((r) => r['tamanho'] == '15')['qtd'], '3');
    });

    test('estoquePorTamanho com string numérica gera qtd correta', () {
      final est = ProdutoVariacaoNormalizer.parseEstoquePorTamanhoRaw({
        '14': '2',
        '15': '3',
      });
      expect(est['14'], 2);
      expect(est['15'], 3);

      final p = _produto(estoquePorTamanho: est);
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.firstWhere((r) => r['tamanho'] == '14')['qtd'], '2');
    });

    test('estoquePorTamanho mapa aninhado quantidade', () {
      final est = ProdutoVariacaoNormalizer.parseEstoquePorTamanhoRaw({
        '14': {'quantidade': 2},
        '15': {'qtd': 3},
      });
      expect(est['14'], 2);
      expect(est['15'], 3);
    });

    test('estoquePorTamanho mapa aninhado estoque/saldo', () {
      final est = ProdutoVariacaoNormalizer.parseEstoquePorTamanhoRaw({
        '18': {'estoque': 1},
        '20': {'saldo': 4},
      });
      expect(est['18'], 1);
      expect(est['20'], 4);
    });

    test('tamanho 15/16 mantém chave e quantidade', () {
      final p = _produto(estoquePorTamanho: const {'15/16': 1});
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.single['tamanho'], '15/16');
      expect(rows.single['qtd'], '1');
    });

    test('chave composta 14|Prata preserva cor e quantidade', () {
      final est = ProdutoVariacaoNormalizer.parseEstoquePorTamanhoRaw({
        '14|Prata': 1,
        '14|Ouro': 2,
      });
      expect(est.containsKey('14|Prata'), isTrue);
      expect(est.containsKey('14|Ouro'), isTrue);
      expect(est['14|Prata'], 1);
      expect(est['14|Ouro'], 2);

      final p = _produto(estoquePorTamanho: est);
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 2);
      expect(
        rows.firstWhere((r) => r['cor'] == 'Prata')['qtd'],
        '1',
      );
      expect(
        rows.firstWhere((r) => r['cor'] == 'Ouro')['qtd'],
        '2',
      );
    });

    test('chave 15/16|Prata preserva tamanho com barra', () {
      final p = _produto(estoquePorTamanho: const {'15/16|Prata': 3});
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.single['tamanho'], '15/16');
      expect(rows.single['cor'], 'Prata');
      expect(rows.single['qtd'], '3');
    });

    test('chave 14|Prata|Letra|A preserva extraTipo e extraValor', () {
      final rebuilt = ProdutoVariacaoNormalizer.rebuildVariacoesFromEstoqueRaw(
        const {'14|Prata|Letra|A': 2},
      );
      expect(rebuilt.variacoes['14'], isNotNull);
      final prata = (rebuilt.variacoes['14'] as Map)['Prata'];
      expect(ProdutoVariacaoExtra.somarCelula(prata), 2);
      expect(
        (rebuilt.variacoesExtraTipo!['14'] as Map)['Prata']['A'],
        'Letra',
      );

      final p = _produto(estoquePorTamanho: const {'14|Prata|Letra|A': 2});
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.single['tamanho'], '14');
      expect(rows.single['cor'], 'Prata');
      expect(rows.single['extraTipo'], 'Letra');
      expect(rows.single['extraValor'], 'A');
      expect(rows.single['qtd'], '2');
    });

    test('precoPorTamanho do produto não é apagado na normalização', () {
      final p = _produto(estoquePorTamanho: const {'14': 2});
      p.precoPorTamanho = const {'14': 45.0};
      ProdutoVariacaoNormalizer.applyToProduto(p);
      expect(p.precoPorTamanho?['14'], 45.0);
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.single['qtd'], '2');
    });

    test('com estoquePorTamanho positivo não cai em tamanhos com qtd 0', () {
      final p = _produto(
        estoquePorTamanho: const {'14': 2},
        tamanhos: const ['14', '15', '18'],
      );
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 1);
      expect(rows.single['qtd'], '2');
    });

    test('somente tamanhos reidrata com qtd 0', () {
      final p = _produto(tamanhos: const ['14', '15']);
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 2);
      expect(rows.every((r) => r['qtd'] == '0'), isTrue);
    });

    test('variacoes esqueleto com qtd 0 usa estoquePorTamanho real', () {
      final p = _produto(
        estoquePorTamanho: const {'14': 2, '15': 1},
        variacoes: {
          '14': {
            'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 0},
          },
          '15': {
            'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 0},
          },
        },
      );
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.firstWhere((r) => r['tamanho'] == '14')['qtd'], '2');
      expect(rows.firstWhere((r) => r['tamanho'] == '15')['qtd'], '1');
    });

    test('applyToProduto não sobrescreve estoque positivo com zeros', () {
      final p = _produto(
        estoquePorTamanho: const {'14': 2},
        variacoes: {
          '14': {
            'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 0},
          },
        },
      );
      ProdutoVariacaoNormalizer.applyToProduto(p);
      expect(p.estoquePorTamanho['14'], 2);
      expect(
        ProdutoVariacaoExtra.somarCelula(
          (p.variacoes!['14'] as Map)['sem-cor'],
        ),
        2,
      );
    });

    test('catálogo expõe variacoes com estoque real', () {
      final m = <String, dynamic>{
        'nome': 'Anel',
        'estoquePorTamanho': {'14': '2', '15': 3},
      };
      ProdutoVariacaoNormalizer.applyToCatalogProductMap(m);
      final stock = CatalogEstoqueHelper.processStockFromFirestoreMap(
        m,
        isCombo: false,
      );
      expect(stock.variacoes, isNotNull);
      expect(
        ProdutoVariacaoExtra.somarCelula(
          (stock.variacoes!['14'] as Map)['sem-cor'],
        ),
        2,
      );
    });

    test('catálogo bloqueia compra quando qtd 0', () {
      final qtd = CatalogEstoqueHelper.parseQtd(0);
      expect(qtd > 0, isFalse);
      // UI usa hasStock = qtd > 0 em catalog_product_variation_pick_body
      expect(CatalogEstoqueHelper.parseQtd('0') > 0, isFalse);
    });

    test('produto simples continua simples', () {
      final p = Produto(
        nome: 'Colar',
        custoReal: 5,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 30,
        quantidade: 2,
        precoUnitario: 30,
        categoria: 'Colares',
        dataEntrada: DateTime(2026, 1, 1),
        lojaId: 'loja',
      );
      expect(ProdutoVariacaoNormalizer.gradeRowsFromProduto(p), isEmpty);
    });
  });
}
