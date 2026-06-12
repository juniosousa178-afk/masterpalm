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
  const lojaId = 'loja-catalogo-venda-dup';

  group('Catálogo cancelamento — vendas duplicadas', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_cat_vdup_');
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

    Future<Venda> novaVenda({
      required String produtoId,
      required String idFirebase,
    }) async {
      final venda = Venda(
        clienteNome: 'Cliente Dup',
        produtosDescricao: 'Colar',
        quantidade: 1,
        preco: 50,
        total: 50,
        formasPagamento: 'PIX',
        data: DateTime(2026, 6, 9),
        vendedor: 'Catálogo',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: 'Colar',
            quantidade: 1,
            precoUnitario: 50,
            productId: produtoId,
            lojaId: lojaId,
          ),
        ],
      );
      venda.idFirebase = idFirebase;
      venda.origemVenda = 'catalogo_web';
      await vendasBox.add(venda);
      return venda;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      produtosBox = await Hive.openBox<Produto>(
        'prod_vdup_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_vdup_${DateTime.now().microsecondsSinceEpoch}',
      );

      const produtoId = 'colar-dup-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Colar', 'quantidade': 8});
      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Colar'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = 8
          ..precoFinal = 50,
      );
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      await produtosBox.close();
      await vendasBox.close();
    });

    test('só a venda com marcador de baixa estorna; duplicata sem marcador não soma 2',
        () async {
      const produtoId = 'colar-dup-1';

      final vendaComBaixa = await novaVenda(
        produtoId: produtoId,
        idFirebase: 'uuid-venda-principal',
      );
      final vendaDuplicada = await novaVenda(
        produtoId: produtoId,
        idFirebase: 'uuid-venda-tentativa-antiga',
      );

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(vendaComBaixa.key.toString())
          .set({
        'baixaAplicada': true,
        'posPagamentoProcessado': true,
        'lojaId': lojaId,
        'vendaId': vendaComBaixa.key.toString(),
      });

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: vendaComBaixa,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 9);

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: vendaDuplicada,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect(
        (snap.data()?['quantidade'] as num?)?.toInt(),
        9,
        reason:
            'venda duplicada sem marcador de baixa catálogo não deve estornar de novo',
      );
      expect(produtosBox.values.first.quantidade, 9);
    });
  });
}
