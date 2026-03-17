// test/vendas_service_test.dart
// Testes unitários para VendasService: resolução de produto, productId/slug/nome, modo estrito.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:master_palm/core/strict_product_resolution.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/vendas_service.dart';

void main() {
  late String hivePath;
  late Box<Produto> box;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_test_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    setStrictResolutionTestOverride(false); // produção: fallback por nome permitido
    final boxName = 'test_produtos_${DateTime.now().millisecondsSinceEpoch}';
    box = await Hive.openBox<Produto>(boxName);
  });

  tearDown(() async {
    setStrictResolutionTestOverride(null);
    await box.close();
  });

  Produto produto({
    String nome = 'Produto Teste',
    String slug = 'produto-teste',
    String lojaId = 'loja_a',
    String idFirebase = '',
  }) {
    final p = Produto.vazio();
    p.nome = nome;
    p.slug = slug;
    p.lojaId = lojaId;
    p.idFirebase = idFirebase;
    return p;
  }

  group('VendasService.encontrarProdutoNoEstoque', () {
    test('retorna null quando box vazia', () {
      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        slug: 'qualquer',
        lojaId: 'loja_a',
      );
      expect(r, isNull);
    });

    test('encontra por slug com lojaId filtrado', () {
      box.add(produto(nome: 'Camiseta', slug: 'camiseta', lojaId: 'loja_a'));
      box.add(produto(nome: 'Calça', slug: 'calca', lojaId: 'loja_b'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        slug: 'camiseta',
        lojaId: 'loja_a',
      );
      expect(r, isNotNull);
      expect(r!.nome, 'Camiseta');
      expect(r.slug, 'camiseta');
      expect(r.lojaId, 'loja_a');
    });

    test('não retorna produto de outra loja ao buscar por slug', () {
      box.add(produto(nome: 'Item A', slug: 'item-a', lojaId: 'loja_b'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        slug: 'item-a',
        lojaId: 'loja_a',
      );
      expect(r, isNull);
    });

    test('encontra por nome quando slug não informado (fallback permitido)', () {
      box.add(produto(nome: 'Bermuda Azul', slug: 'bermuda-azul', lojaId: 'loja_a'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        nome: 'Bermuda Azul',
        lojaId: 'loja_a',
      );
      expect(r, isNotNull);
      expect(r!.nome, 'Bermuda Azul');
    });

    test('busca por slug tem preferência sobre nome', () {
      box.add(produto(nome: 'X', slug: 'slug-x', lojaId: 'loja_a'));
      box.add(produto(nome: 'Outro', slug: 'outro', lojaId: 'loja_a'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        slug: 'slug-x',
        nome: 'Outro',
        lojaId: 'loja_a',
      );
      expect(r!.slug, 'slug-x');
    });

    test('resolve por productId quando productId existe', () {
      box.add(produto(
        nome: 'Produto A',
        slug: 'produto-a',
        lojaId: 'loja_a',
        idFirebase: 'firebase_id_123',
      ));
      box.add(produto(
        nome: 'Produto B',
        slug: 'produto-b',
        lojaId: 'loja_a',
        idFirebase: 'firebase_id_456',
      ));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        productId: 'firebase_id_123',
        nome: 'Produto B',
        lojaId: 'loja_a',
      );
      expect(r, isNotNull);
      expect(r!.nome, 'Produto A');
      expect(r.idFirebase, 'firebase_id_123');
    });

    test('productId tem preferência sobre slug e nome', () {
      box.add(produto(
        nome: 'Alvo',
        slug: 'alvo',
        lojaId: 'loja_a',
        idFirebase: 'id_alvo',
      ));
      box.add(produto(nome: 'Outro', slug: 'outro', lojaId: 'loja_a'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        productId: 'id_alvo',
        slug: 'outro',
        nome: 'Outro',
        lojaId: 'loja_a',
      );
      expect(r!.nome, 'Alvo');
    });

    test('dois produtos com mesmo nome: fluxo por nome retorna o primeiro (risco conhecido)', () {
      box.add(produto(nome: 'Homônimo', slug: 'h1', lojaId: 'loja_a', idFirebase: 'id1'));
      box.add(produto(nome: 'Homônimo', slug: 'h2', lojaId: 'loja_a', idFirebase: 'id2'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        nome: 'Homônimo',
        lojaId: 'loja_a',
      );
      expect(r, isNotNull);
      expect(r!.nome, 'Homônimo');
      expect(['id1', 'id2'], contains(r.idFirebase));
    });

    test('dois produtos com mesmo nome: fluxo por productId retorna o correto', () {
      box.add(produto(nome: 'Homônimo', slug: 'h1', lojaId: 'loja_a', idFirebase: 'id_correto'));
      box.add(produto(nome: 'Homônimo', slug: 'h2', lojaId: 'loja_a', idFirebase: 'id_outro'));

      final r = VendasService.encontrarProdutoNoEstoque(
        produtosBox: box,
        productId: 'id_correto',
        lojaId: 'loja_a',
      );
      expect(r, isNotNull);
      expect(r!.idFirebase, 'id_correto');
    });

    group('modo estrito', () {
      setUp(() {
        setStrictResolutionTestOverride(true);
      });

      tearDown(() {
        setStrictResolutionTestOverride(false);
      });

      test('fallback por nome lança exceção em modo estrito', () {
        box.add(produto(nome: 'Teste', slug: 'teste', lojaId: 'loja_a'));

        expect(
          () => VendasService.encontrarProdutoNoEstoque(
            produtosBox: box,
            nome: 'Teste',
            lojaId: 'loja_a',
          ),
          throwsA(
            predicate<Exception>((e) =>
                e.toString().contains('modo estrito') &&
                e.toString().contains('ID-first') &&
                e.toString().contains('productId')),
          ),
        );
      });

      test('productId continua funcionando em modo estrito', () {
        box.add(produto(
          nome: 'Produto',
          slug: 'produto',
          lojaId: 'loja_a',
          idFirebase: 'id_123',
        ));

        final r = VendasService.encontrarProdutoNoEstoque(
          produtosBox: box,
          productId: 'id_123',
          lojaId: 'loja_a',
        );
        expect(r, isNotNull);
        expect(r!.nome, 'Produto');
      });

      test('slug continua funcionando em modo estrito', () {
        box.add(produto(nome: 'Produto', slug: 'meu-slug', lojaId: 'loja_a'));

        final r = VendasService.encontrarProdutoNoEstoque(
          produtosBox: box,
          slug: 'meu-slug',
          lojaId: 'loja_a',
        );
        expect(r, isNotNull);
        expect(r!.slug, 'meu-slug');
      });
    });
  });
}
