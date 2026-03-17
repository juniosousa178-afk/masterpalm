// test/venda_item_test.dart
// Testes para VendaItem e Venda.fromForm: productId, serialização, compatibilidade.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';

void main() {
  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_test_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  group('VendaItem', () {
    test('cria com productId opcional', () {
      final item = VendaItem(
        produtoNome: 'Produto A',
        quantidade: 2,
        precoUnitario: 25.0,
        productId: 'firebase_id_123',
      );
      expect(item.produtoNome, 'Produto A');
      expect(item.productId, 'firebase_id_123');
    });

    test('cria sem productId (compatibilidade com venda antiga)', () {
      final item = VendaItem(
        produtoNome: 'Produto B',
        quantidade: 1,
        precoUnitario: 10.0,
      );
      expect(item.productId, isNull);
    });
  });

  group('Venda.fromForm', () {
    test('nova venda salva VendaItem com productId quando disponível', () {
      final venda = Venda.fromForm(
        clienteNome: 'Cliente',
        produtos: [
          {
            'produto': 'Produto X',
            'quantidade': 1,
            'preco': 50.0,
            'productId': 'id_produto_x',
          },
        ],
        desconto: 0,
        frete: 0,
        formasPagamento: {'pix': 50.0},
        vendedor: 'App',
      );
      expect(venda.itens, isNotNull);
      expect(venda.itens!.length, 1);
      expect(venda.itens!.first.productId, 'id_produto_x');
    });

    test('VendaItem sem productId continua compatível', () {
      final venda = Venda.fromForm(
        clienteNome: 'Cliente',
        produtos: [
          {
            'produto': 'Produto Y',
            'quantidade': 2,
            'preco': 30.0,
          },
        ],
        desconto: 0,
        frete: 0,
        formasPagamento: {'pix': 60.0},
        vendedor: 'App',
      );
      expect(venda.itens!.first.productId, isNull);
    });
  });

  group('VendaItem serialização Hive', () {
    test('item com productId serializa e desserializa corretamente', () async {
      final boxName = 'test_items_${DateTime.now().millisecondsSinceEpoch}';
      final box = await Hive.openBox<VendaItem>(boxName);

      final original = VendaItem(
        produtoNome: 'Produto',
        quantidade: 3,
        precoUnitario: 15.0,
        productId: 'id_firebase_xyz',
      );
      final key = await box.add(original);

      await box.close();
      final box2 = await Hive.openBox<VendaItem>(boxName);
      final loaded = box2.get(key);
      expect(loaded, isNotNull);
      expect(loaded!.produtoNome, 'Produto');
      expect(loaded.productId, 'id_firebase_xyz');
      expect(loaded.quantidade, 3);

      await box2.close();
    });

    test('venda antiga sem productId desserializa (campo null ou vazio)', () async {
      final boxName = 'test_items_old_${DateTime.now().millisecondsSinceEpoch}';
      final box = await Hive.openBox<VendaItem>(boxName);

      final oldStyle = VendaItem(
        produtoNome: 'Produto Antigo',
        quantidade: 1,
        precoUnitario: 20.0,
      );
      final key = await box.add(oldStyle);

      await box.close();

      final box2 = await Hive.openBox<VendaItem>(boxName);
      final loaded = box2.get(key);
      expect(loaded, isNotNull);
      expect(loaded!.produtoNome, 'Produto Antigo');
      expect(
        loaded.productId == null || loaded.productId!.trim().isEmpty,
        isTrue,
        reason: 'productId deve ser null ou vazio (adapter grava null como "")',
      );

      await box2.close();
    });
  });
}
