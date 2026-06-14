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
  const lojaId = 'loja-exc-hive-fs';

  group('Exclusão catálogo — Hive e Firestore alinhados', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_exc_hf_');
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
        'prod_hf_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      await produtosBox.close();
    });

    test('venda lixeira com key diferente usa hiveKeyOriginal no marcador', () async {
      const produtoId = 'pulseira-hf';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Pulseira', 'quantidade': 2});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Pulseira'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = 2
          ..precoFinal = 30,
      );

      const hiveKeyOriginal = 266;
      final vendaOriginal = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: 'Pulseira',
        quantidade: 1,
        preco: 30,
        total: 30,
        formasPagamento: 'PIX',
        data: DateTime(2026, 6, 11),
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
      vendaOriginal.idFirebase = 'uuid-pulseira';

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc('$hiveKeyOriginal')
          .set({
        'baixaAplicada': true,
        'estornoAplicado': true,
        'lojaId': lojaId,
        'vendaId': '$hiveKeyOriginal',
      });

      final vendaLixeira = Venda(
        clienteNome: vendaOriginal.clienteNome,
        produtosDescricao: vendaOriginal.produtosDescricao,
        quantidade: vendaOriginal.quantidade,
        preco: vendaOriginal.preco,
        total: vendaOriginal.total,
        formasPagamento: vendaOriginal.formasPagamento,
        data: vendaOriginal.data,
        vendedor: vendaOriginal.vendedor,
        observacao: vendaOriginal.observacao,
        lojaId: lojaId,
        itens: vendaOriginal.itens,
      );
      vendaLixeira.idFirebase = vendaOriginal.idFirebase;
      final trashBox = await Hive.openBox<Venda>(
        'trash_vendas_hf_${DateTime.now().microsecondsSinceEpoch}',
      );
      await trashBox.add(vendaLixeira);

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: vendaLixeira,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaHiveKeyMarcador: hiveKeyOriginal,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect(
        (snap.data()?['quantidade'] as num?)?.toInt(),
        2,
        reason: 'estornoAplicado no marcador original bloqueia nova devolução',
      );
      expect(produtosBox.values.first.quantidade, 2);
      await trashBox.close();
    });

    test('sem origemVenda mas com hiveKeyOriginal e estorno já aplicado: não duplica',
        () async {
      const produtoId = 'brinco-sem-origem';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Brinco', 'quantidade': 3});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Brinco'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = 3
          ..precoFinal = 20,
      );

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: 'Brinco',
        quantidade: 1,
        preco: 20,
        total: 20,
        formasPagamento: 'PIX',
        data: DateTime(2026, 6, 11),
        vendedor: 'Catálogo',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: 'Brinco',
            quantidade: 1,
            precoUnitario: 20,
            productId: produtoId,
            lojaId: lojaId,
          ),
        ],
      );
      venda.idFirebase = 'uuid-brinco';
      final hiveKey = 99;

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc('$hiveKey')
          .set({
        'baixaAplicada': true,
        'lojaId': lojaId,
        'vendaId': '$hiveKey',
      });

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaHiveKeyMarcador: hiveKey,
      );

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 4);
      expect(produtosBox.values.first.quantidade, 4);

      await VendasService.executarExclusaoPermanente(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaHiveKeyOriginal: hiveKey,
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 4);
      expect(produtosBox.values.first.quantidade, 4);
    });
  });
}
