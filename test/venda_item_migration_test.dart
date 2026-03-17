// test/venda_item_migration_test.dart
// Testes para VendaItemMigrationService: migração segura, contadores, regras conservadoras.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/venda_item_migration_service.dart';

void main() {
  late String hivePath;
  late String lojaId;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_mig_test_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    lojaId = 'test_mig_${DateTime.now().millisecondsSinceEpoch}';
  });

  tearDown(() async {
    try {
      await Hive.box<Venda>(HiveBoxNames.vendas(lojaId)).close();
      await Hive.box<Produto>(HiveBoxNames.produtos(lojaId)).close();
    } catch (_) {}
  });

  Future<void> setupProdutos(Box<Produto> produtosBox, List<({String nome, String idFirebase})> items) async {
    for (final item in items) {
      final p = Produto.vazio();
      p.nome = item.nome;
      p.slug = item.nome.toLowerCase().replaceAll(' ', '-');
      p.lojaId = lojaId;
      p.idFirebase = item.idFirebase;
      await produtosBox.add(p);
    }
  }

  group('VendaItemMigrationService.migrarLoja', () {
    test('item com nome único migra productId', () async {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

      await setupProdutos(produtosBox, [(nome: 'Produto Único', idFirebase: 'id_p1')]);

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: '1 x Produto Único',
        quantidade: 1,
        preco: 10,
        total: 10,
        formasPagamento: 'Pix',
        data: DateTime(2024, 1, 15),
        vendedor: 'App',
        observacao: '',
        itens: [
          VendaItem(
            produtoNome: 'Produto Único',
            quantidade: 1,
            precoUnitario: 10,
          ),
        ],
        lojaId: lojaId,
      );
      await vendasBox.add(venda);

      final result = await VendaItemMigrationService.migrarLoja(lojaId);

      expect(result.vendasAlteradas, 1);
      expect(result.itensMigrados, 1);
      expect(result.itensAmbiguos, 0);

      final vendaAtualizada = vendasBox.get(venda.key);
      expect(vendaAtualizada!.itens!.first.productId, 'id_p1');

      await vendasBox.close();
      await produtosBox.close();
    });

    test('item com nome duplicado NÃO migra', () async {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

      await setupProdutos(produtosBox, [
        (nome: 'Homônimo', idFirebase: 'id1'),
        (nome: 'Homônimo', idFirebase: 'id2'),
      ]);

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: '1 x Homônimo',
        quantidade: 1,
        preco: 5,
        total: 5,
        formasPagamento: 'Pix',
        data: DateTime(2024, 1, 1),
        vendedor: 'App',
        observacao: '',
        itens: [
          VendaItem(produtoNome: 'Homônimo', quantidade: 1, precoUnitario: 5),
        ],
        lojaId: lojaId,
      );
      await vendasBox.add(venda);

      final result = await VendaItemMigrationService.migrarLoja(lojaId);

      expect(result.itensMigrados, 0);
      expect(result.itensAmbiguos, 1);

      final vendaAtualizada = vendasBox.get(venda.key);
      expect(vendaAtualizada!.itens!.first.productId, isNull);

      await vendasBox.close();
      await produtosBox.close();
    });

    test('item sem match NÃO migra', () async {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

      await setupProdutos(produtosBox, [(nome: 'Outro Produto', idFirebase: 'id_outro')]);

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: '1 x Produto Inexistente',
        quantidade: 1,
        preco: 10,
        total: 10,
        formasPagamento: 'Pix',
        data: DateTime(2024, 1, 1),
        vendedor: 'App',
        observacao: '',
        itens: [
          VendaItem(produtoNome: 'Produto Inexistente', quantidade: 1, precoUnitario: 10),
        ],
        lojaId: lojaId,
      );
      await vendasBox.add(venda);

      final result = await VendaItemMigrationService.migrarLoja(lojaId);

      expect(result.itensMigrados, 0);
      expect(result.itensSemMatch, 1);

      await vendasBox.close();
      await produtosBox.close();
    });

    test('item já com productId é ignorado', () async {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

      await setupProdutos(produtosBox, [(nome: 'Produto', idFirebase: 'id_p')]);

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: '1 x Produto',
        quantidade: 1,
        preco: 10,
        total: 10,
        formasPagamento: 'Pix',
        data: DateTime(2024, 1, 1),
        vendedor: 'App',
        observacao: '',
        itens: [
          VendaItem(
            produtoNome: 'Produto',
            quantidade: 1,
            precoUnitario: 10,
            productId: 'id_p',
          ),
        ],
        lojaId: lojaId,
      );
      await vendasBox.add(venda);

      final result = await VendaItemMigrationService.migrarLoja(lojaId);

      expect(result.itensMigrados, 0);
      expect(result.itensJaComId, 1);

      await vendasBox.close();
      await produtosBox.close();
    });

    test('migração não altera valor, quantidade, data, cliente', () async {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

      await setupProdutos(produtosBox, [(nome: 'Item', idFirebase: 'id_item')]);

      final dataOriginal = DateTime(2024, 6, 15);
      final venda = Venda(
        clienteNome: 'Maria',
        produtosDescricao: '2 x Item',
        quantidade: 2,
        preco: 100,
        total: 100,
        formasPagamento: 'Pix',
        data: dataOriginal,
        vendedor: 'App',
        observacao: 'obs',
        itens: [
          VendaItem(produtoNome: 'Item', quantidade: 2, precoUnitario: 50),
        ],
        lojaId: lojaId,
      );
      await vendasBox.add(venda);

      await VendaItemMigrationService.migrarLoja(lojaId);

      final v = vendasBox.get(venda.key)!;
      expect(v.itens!.first.quantidade, 2);
      expect(v.itens!.first.precoUnitario, 50);
      expect(v.data, dataOriginal);
      expect(v.clienteNome, 'Maria');
      expect(v.itens!.first.productId, 'id_item');

      await vendasBox.close();
      await produtosBox.close();
    });

    test('retorna contadores corretos', () async {
      final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      final produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));

      await setupProdutos(produtosBox, [
        (nome: 'Migrar', idFirebase: 'id_m'),
        (nome: 'Já tem', idFirebase: 'id_j'),
      ]);

      await vendasBox.add(Venda(
        clienteNome: 'C',
        produtosDescricao: 'd',
        quantidade: 2,
        preco: 20,
        total: 20,
        formasPagamento: 'Pix',
        data: DateTime(2024, 1, 1),
        vendedor: 'App',
        observacao: '',
        itens: [
          VendaItem(produtoNome: 'Migrar', quantidade: 1, precoUnitario: 10),
          VendaItem(produtoNome: 'Já tem', quantidade: 1, precoUnitario: 10, productId: 'id_j'),
        ],
        lojaId: lojaId,
      ));

      final result = await VendaItemMigrationService.migrarLoja(lojaId);

      expect(result.vendasProcessadas, 1);
      expect(result.vendasAlteradas, 1);
      expect(result.itensMigrados, 1);
      expect(result.itensJaComId, 1);

      await vendasBox.close();
      await produtosBox.close();
    });
  });
}
