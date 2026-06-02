// Exclusão de venda — devolução de estoque (simples, variação, combo, idempotência, fiado).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-exclusao-estorno-20260602';

  group('devolverEstoqueParaVendaRemovida', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_exc_est_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
      if (!Hive.isAdapterRegistered(29)) {
        Hive.registerAdapter(ContaReceberAdapter());
      }
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    Future<void> seedProdutoSimples({
      required String id,
      required int qtd,
    }) async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({'nome': 'Prod $id', 'quantidade': qtd});
      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Prod $id'
          ..idFirebase = id
          ..lojaId = lojaId
          ..quantidade = qtd
          ..precoFinal = 10,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

      produtosBox = await Hive.openBox<Produto>(
        'prod_exc_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_exc_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_exc_${DateTime.now().microsecondsSinceEpoch}',
      );

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Exclusão',
          telefone: '11888888888',
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId,
        ),
      );
    });

    tearDown(() async {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    test('produto simples: vender 2 e excluir devolve 2', () async {
      const id = 'simples-exc-1';
      await seedProdutoSimples(id: id, qtd: 10);
      final cliente = clientesBox.values.first;

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod $id',
            quantidade: 2,
            precoUnitario: 10,
            productId: id,
          ),
        ],
        dinheiro: 20,
        lojaId: lojaId,
      );

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 8);

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 10);
      expect(produtosBox.values.first.quantidade, 10);
    });

    test('variação: baixa célula e exclusão devolve célula', () async {
      const id = 'var-exc-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({
        'nome': 'Camiseta',
        'quantidade': 0,
        'variacoes': {
          'P': {'Azul': 4},
        },
      });
      final p = Produto.vazio()
        ..nome = 'Camiseta'
        ..idFirebase = id
        ..lojaId = lojaId
        ..variacoes = {
          'P': {'Azul': 4},
        }
        ..precoFinal = 30;
      await produtosBox.add(p);

      final cliente = clientesBox.values.first;
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Camiseta',
            quantidade: 1,
            precoUnitario: 30,
            productId: id,
            tamanho: 'P',
            cor: 'Azul',
          ),
        ],
        dinheiro: 30,
        lojaId: lojaId,
      );

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      final vars = snap.data()?['variacoes'] as Map?;
      final pMap = vars?['P'] as Map?;
      expect((pMap?['Azul'] as num?)?.toInt(), 4);
    });

    test('devolução duplicada é idempotente (não soma estoque 2x)', () async {
      const id = 'idemp-exc-1';
      await seedProdutoSimples(id: id, qtd: 5);
      final cliente = clientesBox.values.first;

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod $id',
            quantidade: 1,
            precoUnitario: 10,
            productId: id,
          ),
        ],
        dinheiro: 10,
        lojaId: lojaId,
      );

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );
      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 5);
    });

    test('combo: exclusão devolve componentes', () async {
      const idFilho = 'comp-exc-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idFilho)
          .set({'nome': 'Componente', 'quantidade': 10});

      final comp = Produto.vazio()
        ..nome = 'Componente'
        ..idFirebase = idFilho
        ..lojaId = lojaId
        ..quantidade = 10;
      final combo = Produto.vazio()
        ..nome = 'Kit Exc'
        ..idFirebase = 'combo-exc-1'
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..quantidade = 3
        ..itensCombo = [
          {'productId': idFilho, 'nome': 'Componente', 'quantidade': 2},
        ];
      await produtosBox.addAll([comp, combo]);

      final cliente = clientesBox.values.first;
      final selecao = {
        0: [
          {'productId': idFilho, 'nome': 'Componente', 'quantidade': 2},
        ],
      };

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Kit Exc',
            quantidade: 1,
            precoUnitario: 50,
            productId: combo.idFirebase,
          ),
        ],
        dinheiro: 50,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: selecao,
      );

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idFilho)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 8);

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idFilho)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 10);
    });

    test('venda fiada excluída remove contas a receber vinculadas', () async {
      const id = 'fiado-exc-prod';
      await seedProdutoSimples(id: id, qtd: 5);
      final cliente = clientesBox.values.first;

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod $id',
            quantidade: 1,
            precoUnitario: 10,
            productId: id,
          ),
        ],
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);

      final vk = venda.key as int;
      await VendasService.removerContasReceberVinculadasAVenda(
        lojaId: lojaId,
        vendaKey: vk,
      );
      expect(crBox.length, 0);
      await crBox.close();
    });
  });

  group('resolver itens devolução — contrato', () {
    test('vendas_service expõe fallback expansao após agrupado vazio', () {
      final src = File('lib/services/vendas_service.dart').readAsStringSync();
      expect(src.contains('_montarItensDevolucaoViaExpansaoVenda'), isTrue);
      expect(src.contains('_resolverItensDevolucaoParaVenda'), isTrue);
      expect(src.contains('itens_estruturados_sem_maps'), isTrue);
    });

    test('montarTxItems compatível com devolução batch', () {
      final maps = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: [
          VendaItem(
            produtoNome: 'X',
            quantidade: 1,
            precoUnitario: 1,
            productId: 'pid-x',
          ),
        ],
        produtosEncontrados: [
          Produto.vazio()
            ..nome = 'X'
            ..idFirebase = 'pid-x',
        ],
      );
      expect(maps.first['productId'], 'pid-x');
      expect(maps.first['quantidade'], 1);
    });
  });
}
