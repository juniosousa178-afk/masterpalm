import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-catalogo-sem-baixa';

  group('Catálogo cancelamento — sem baixa aplicada', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_cat_sem_baixa_');
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

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      produtosBox = await Hive.openBox<Produto>(
        'prod_sem_baixa_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_sem_baixa_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      await produtosBox.close();
      await vendasBox.close();
    });

    test('marcador existe mas baixaAplicada=false não devolve estoque', () async {
      const produtoId = 'prod-sem-baixa-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Pulseira', 'quantidade': 10});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Pulseira'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = 10
          ..precoFinal = 30,
      );

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: 'Pulseira',
        quantidade: 1,
        preco: 30,
        total: 30,
        formasPagamento: 'PIX',
        data: DateTime(2026, 6, 9),
        vendedor: 'Catálogo',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: 'Pulseira',
            quantidade: 1,
            precoUnitario: 30,
            productId: produtoId,
            lojaId: lojaId,
          ),
        ],
      );
      venda.idFirebase = 'uuid-pendente-sem-baixa';
      venda.origemVenda = 'catalogo_web';
      await vendasBox.add(venda);

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(venda.key.toString())
          .set({
        'baixaAplicada': false,
        'lojaId': lojaId,
        'vendaId': venda.key.toString(),
      });

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 10);
      expect(produtosBox.values.first.quantidade, 10);
    });

    test('venda PDV sem marcador catálogo continua devolvendo estoque', () async {
      const produtoId = 'prod-pdv-normal';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Brinco PDV', 'quantidade': 8});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Brinco PDV'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = 8
          ..precoFinal = 20,
      );

      final venda = Venda(
        clienteNome: 'Cliente PDV',
        produtosDescricao: 'Brinco PDV',
        quantidade: 2,
        preco: 10,
        total: 20,
        formasPagamento: 'Dinheiro',
        data: DateTime(2026, 6, 9),
        vendedor: 'PDV',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: 'Brinco PDV',
            quantidade: 2,
            precoUnitario: 10,
            productId: produtoId,
            lojaId: lojaId,
          ),
        ],
      );
      await vendasBox.add(venda);

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 10);
      expect(produtosBox.values.first.quantidade, 10);
    });
  });
}
