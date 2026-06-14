import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/soft_delete_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reproduz exclusão pela tela Vendas: scheduleVendaDelete + exclusão definitiva.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-vendas-excluir-estorno';

  group('Tela Vendas — excluir venda catálogo estorna 1 vez', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Venda> vendasBox;
    late Box<Cliente> clientesBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_vendas_exc_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
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
        HiveBoxNames.produtos(lojaId),
      );
      vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
      clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
      await produtosBox.clear();
      await vendasBox.clear();
      await clientesBox.clear();
      await clientesBox.add(
        Cliente(
          nome: 'Cliente Catálogo',
          telefone: '11999999999',
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId,
        ),
      );
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      if (produtosBox.isOpen) await produtosBox.close();
      if (vendasBox.isOpen) await vendasBox.close();
      if (clientesBox.isOpen) await clientesBox.close();
    });

    test('schedule + exclusão definitiva: 3→2 baixa, excluir volta 3 não 4', () async {
      const produtoId = 'anel-vendas-exc';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set({'nome': 'Anel Vendas', 'quantidade': 2});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Anel Vendas'
          ..idFirebase = produtoId
          ..lojaId = lojaId
          ..quantidade = 2
          ..precoFinal = 50,
      );

      final venda = Venda(
        clienteNome: 'Cliente Catálogo',
        produtosDescricao: 'Anel Vendas',
        quantidade: 1,
        preco: 50,
        total: 50,
        formasPagamento: 'PIX',
        data: DateTime(2026, 6, 11),
        vendedor: 'Catálogo',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: 'Anel Vendas',
            quantidade: 1,
            precoUnitario: 50,
            productId: produtoId,
            lojaId: lojaId,
          ),
        ],
      );
      venda.idFirebase = 'uuid-venda-catalogo-exc';
      await vendasBox.add(venda);
      final hiveKeyOriginal = venda.key as int;

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(hiveKeyOriginal.toString())
          .set({
        'baixaAplicada': true,
        'posPagamentoProcessado': true,
        'lojaId': lojaId,
        'vendaId': hiveKeyOriginal.toString(),
      });

      await SoftDeleteService.scheduleVendaDelete(
        venda: venda,
        vendasBox: vendasBox,
        clientesBox: clientesBox,
        lojaId: lojaId,
      );

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 3);
      expect(produtosBox.values.first.quantidade, 3);

      final marcadorPosSchedule = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_baixa_pagamento')
          .doc(hiveKeyOriginal.toString())
          .get();
      expect(marcadorPosSchedule.data()?['estornoAplicado'], isTrue);

      final trashBox = await Hive.openBox<Venda>('trash_vendas');
      final vendaLixeira = trashBox.values.first;

      await VendasService.executarExclusaoPermanente(
        venda: vendaLixeira,
        produtosBox: produtosBox,
        lojaId: lojaId,
        vendaHiveKeyOriginal: hiveKeyOriginal,
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      expect(
        (snap.data()?['quantidade'] as num?)?.toInt(),
        3,
        reason: 'exclusão definitiva não deve estornar de novo',
      );
      expect(produtosBox.values.first.quantidade, 3);
      await trashBox.close();
    });
  });
}
