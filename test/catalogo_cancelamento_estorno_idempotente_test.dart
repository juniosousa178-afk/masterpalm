import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  const lojaId = 'loja-catalogo-estorno-idem';

  group('Catálogo cancelamento — estorno idempotente', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_cat_est_');
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

    Future<Venda> seedVendaCatalogoComMarcador({
      required String produtoId,
      required int qtdRemota,
      required int qtdHive,
    }) async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Anel Teste', 'quantidade': qtdRemota});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Anel Teste'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = qtdHive
          ..precoFinal = 50,
      );

      final venda = Venda(
        clienteNome: 'Cliente Catálogo',
        produtosDescricao: 'Anel Teste',
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
            produtoNome: 'Anel Teste',
            quantidade: 1,
            precoUnitario: 50,
            productId: produtoId,
            lojaId: lojaId,
          ),
        ],
      );
      venda.idFirebase = 'uuid-sync-firestore-diferente-da-hive-key';
      venda.origemVenda = 'catalogo_web';
      await vendasBox.add(venda);

      final hiveKey = venda.key.toString();
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(hiveKey)
          .set({
        'baixaAplicada': true,
        'posPagamentoProcessado': true,
        'lojaId': lojaId,
        'vendaId': hiveKey,
        'origem': 'catalogo_whatsapp',
      });
      return venda;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      produtosBox = await Hive.openBox<Produto>(
        'prod_cat_est_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_cat_est_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      await produtosBox.close();
      await vendasBox.close();
    });

    test('baixa aplicada: cancelar estorna 1 vez mesmo com idFirebase diferente da hive key',
        () async {
      const produtoId = 'anel-estorno-1';
      final venda = await seedVendaCatalogoComMarcador(
        produtoId: produtoId,
        qtdRemota: 9,
        qtdHive: 9,
      );
      final hiveKey = venda.key.toString();

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        estornoOrigem: 'venda_delete',
      );

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 10);
      expect(produtosBox.values.first.quantidade, 10);

      final marcador = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(hiveKey)
          .get();
      expect(marcador.data()?['estornoAplicado'], isTrue);
      expect(marcador.data()?['estornoOrigem'], 'venda_delete');

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
        estornoOrigem: 'pre_pedido_cancelado',
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 10);
      expect(produtosBox.values.first.quantidade, 10);
    });

    test('estornoAplicado remoto bloqueia nova devolução', () async {
      const produtoId = 'anel-estorno-2';
      final venda = await seedVendaCatalogoComMarcador(
        produtoId: produtoId,
        qtdRemota: 9,
        qtdHive: 9,
      );
      final hiveKey = venda.key.toString();

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(hiveKey)
          .set({
        'estornoAplicado': true,
        'estornoOrigem': 'venda_delete',
        'lojaId': lojaId,
      }, SetOptions(merge: true));

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
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 9);
    });
  });
}
