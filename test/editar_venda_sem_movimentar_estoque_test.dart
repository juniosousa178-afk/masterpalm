// Edição de venda — delta de estoque e dados administrativos sem movimentação desnecessária.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/safe_cast.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_edicao_estoque_diff.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-editar-venda-20260602';

  group('VendaEdicaoEstoqueDiff', () {
    test('itens equivalentes detecta combo json igual', () {
      expect(
        VendaEdicaoEstoqueDiff.itensVendaEquivalentes(
          antigos: [
            VendaItem(
              produtoNome: 'A',
              quantidade: 1,
              precoUnitario: 10,
              productId: 'p1',
            ),
          ],
          novos: [
            VendaItem(
              produtoNome: 'A',
              quantidade: 1,
              precoUnitario: 12,
              productId: 'p1',
            ),
          ],
          comboJsonAntigo: '{"0":[{"productId":"c1","nome":"C","quantidade":1}]}',
          comboJsonNovo: '{"0":[{"productId":"c1","nome":"C","quantidade":1}]}',
        ),
        isTrue,
      );
    });

    test('calcularDelta baixa só diferença positiva', () {
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: [
          {'productId': 'p1', 'nome': 'Prod', 'quantidade': 2, 'tamanho': '', 'cor': ''},
        ],
        linhasNovas: [
          {'productId': 'p1', 'nome': 'Prod', 'quantidade': 3, 'tamanho': '', 'cor': ''},
        ],
      );
      expect(delta.devolver, isEmpty);
      expect(delta.baixar.length, 1);
      expect(delta.baixar.first['quantidade'], 1);
    });

    test('calcularDelta devolve só diferença negativa', () {
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: [
          {'productId': 'p1', 'nome': 'Prod', 'quantidade': 3, 'tamanho': '', 'cor': ''},
        ],
        linhasNovas: [
          {'productId': 'p1', 'nome': 'Prod', 'quantidade': 1, 'tamanho': '', 'cor': ''},
        ],
      );
      expect(delta.baixar, isEmpty);
      expect(delta.devolver.length, 1);
      expect(delta.devolver.first['quantidade'], 2);
    });

    test('trocar produto devolve antigo e baixa novo', () {
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: [
          {'productId': 'p1', 'nome': 'A', 'quantidade': 1, 'tamanho': '', 'cor': ''},
        ],
        linhasNovas: [
          {'productId': 'p2', 'nome': 'B', 'quantidade': 1, 'tamanho': '', 'cor': ''},
        ],
      );
      expect(delta.devolver.first['productId'], 'p1');
      expect(delta.baixar.first['productId'], 'p2');
    });

    test('variação alterada devolve célula antiga e baixa nova', () {
      final delta = VendaEdicaoEstoqueDiff.calcularDelta(
        linhasAntigas: [
          {
            'productId': 'v1',
            'nome': 'Camiseta',
            'quantidade': 1,
            'tamanho': 'P',
            'cor': 'Azul',
          },
        ],
        linhasNovas: [
          {
            'productId': 'v1',
            'nome': 'Camiseta',
            'quantidade': 1,
            'tamanho': 'M',
            'cor': 'Azul',
          },
        ],
      );
      expect(delta.devolver.first['tamanho'], 'P');
      expect(delta.baixar.first['tamanho'], 'M');
    });
  });

  group('resolverValidacaoEstoquePreSalvamentoEdicao (UI)', () {
    late Box<Produto> produtosBox;
    const lojaUi = 'loja-ui-pre-salv-20260602';

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_ui_pre_salv_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
      if (!Hive.isAdapterRegistered(7)) {
        Hive.registerAdapter(VendaItemAdapter());
      }
    });

    setUp(() async {
      produtosBox = await Hive.openBox<Produto>(
        'prod_ui_pre_${DateTime.now().microsecondsSinceEpoch}',
      );
      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Camiseta'
          ..idFirebase = 'cam-1'
          ..lojaId = lojaUi
          ..quantidade = 0
          ..precoFinal = 20,
      );
      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Calça'
          ..idFirebase = 'cal-1'
          ..lojaId = lojaUi
          ..quantidade = 0
          ..precoFinal = 30,
      );
    });

    tearDown(() async {
      await produtosBox.close();
    });

    Venda vendaComItens(List<VendaItem> itens, {String? comboJson}) {
      return Venda(
        clienteNome: 'Cliente',
        produtosDescricao: '',
        quantidade: itens.length,
        preco: 10,
        total: 10,
        formasPagamento: 'Dinheiro',
        data: DateTime(2026, 1, 10),
        tamanho: '',
        vendedor: 'App',
        observacao: '',
        itens: itens,
        lojaId: lojaUi,
        itensComboSelecaoJson: comboJson,
      );
    }

    test('edição administrativa (mesmos itens) pula validação de estoque', () {
      final original = vendaComItens([
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 2,
          precoUnitario: 20,
          productId: 'cam-1',
        ),
      ]);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: original.itens!,
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.pularValidacaoEstoque, isTrue);
      expect(pre.linhasValidarBaixa, isEmpty);
    });

    test('só data/pagamento equivalente não exige linhas de baixa com estoque 0', () {
      final itens = [
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 1,
          precoUnitario: 25,
          productId: 'cam-1',
        ),
      ];
      final original = vendaComItens(itens);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: [
          VendaItem(
            produtoNome: 'Camiseta',
            quantidade: 1,
            precoUnitario: 99,
            productId: 'cam-1',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.pularValidacaoEstoque, isTrue);
    });

    test('aumentar quantidade com estoque 0 exige validar delta de baixa', () {
      final original = vendaComItens([
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 1,
          precoUnitario: 20,
          productId: 'cam-1',
        ),
      ]);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: [
          VendaItem(
            produtoNome: 'Camiseta',
            quantidade: 3,
            precoUnitario: 20,
            productId: 'cam-1',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.pularValidacaoEstoque, isFalse);
      expect(pre.linhasValidarBaixa.length, 1);
      expect(pre.linhasValidarBaixa.first['quantidade'], 2);
      expect(pre.linhasValidarBaixa.first['productId'], 'cam-1');
    });

    test('diminuir quantidade não exige validação de baixa', () {
      final original = vendaComItens([
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 3,
          precoUnitario: 20,
          productId: 'cam-1',
        ),
      ]);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: [
          VendaItem(
            produtoNome: 'Camiseta',
            quantidade: 1,
            precoUnitario: 20,
            productId: 'cam-1',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.pularValidacaoEstoque, isFalse);
      expect(pre.linhasValidarBaixa, isEmpty);
    });

    test('adicionar produto exige validar só o item novo', () {
      final original = vendaComItens([
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 1,
          precoUnitario: 20,
          productId: 'cam-1',
        ),
      ]);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: [
          ...original.itens!,
          VendaItem(
            produtoNome: 'Calça',
            quantidade: 1,
            precoUnitario: 30,
            productId: 'cal-1',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.linhasValidarBaixa.length, 1);
      expect(pre.linhasValidarBaixa.first['productId'], 'cal-1');
    });

    test('trocar produto valida baixa apenas do produto novo', () {
      final original = vendaComItens([
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 1,
          precoUnitario: 20,
          productId: 'cam-1',
        ),
      ]);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: [
          VendaItem(
            produtoNome: 'Calça',
            quantidade: 1,
            precoUnitario: 30,
            productId: 'cal-1',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.linhasValidarBaixa.length, 1);
      expect(pre.linhasValidarBaixa.first['productId'], 'cal-1');
    });

    test('variação alterada valida só célula nova no delta', () {
      final original = vendaComItens([
        VendaItem(
          produtoNome: 'Camiseta',
          quantidade: 1,
          precoUnitario: 20,
          productId: 'cam-1',
          tamanho: 'P',
          cor: 'Azul',
        ),
      ]);
      final pre = VendasService.resolverValidacaoEstoquePreSalvamentoEdicao(
        vendaOriginal: original,
        itensNovos: [
          VendaItem(
            produtoNome: 'Camiseta',
            quantidade: 1,
            precoUnitario: 20,
            productId: 'cam-1',
            tamanho: 'M',
            cor: 'Azul',
          ),
        ],
        produtosBox: produtosBox,
        lojaId: lojaUi,
      );
      expect(pre.linhasValidarBaixa.length, 1);
      expect(pre.linhasValidarBaixa.first['tamanho'], 'M');
      expect(pre.linhasValidarBaixa.first['quantidade'], 1);
    });
  });

  group('editarVendaMulti integração', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_edit_venda_');
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

    Future<void> seedProduto({
      required String id,
      required int qtd,
      String nome = '',
    }) async {
      final n = nome.isEmpty ? 'Prod $id' : nome;
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({'nome': n, 'quantidade': qtd});
      await produtosBox.add(
        Produto.vazio()
          ..nome = n
          ..idFirebase = id
          ..lojaId = lojaId
          ..quantidade = qtd
          ..precoFinal = 10,
      );
    }

    Future<int> qtdFirestore(String id) async {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

      produtosBox = await Hive.openBox<Produto>(
        'prod_edit_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_edit_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_edit_${DateTime.now().microsecondsSinceEpoch}',
      );

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Edição',
          telefone: '11999999999',
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
      try {
        await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(lojaId));
      } catch (_) {}
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Venda> vender({
      required String id,
      int qtd = 1,
      double dinheiro = 10,
      double pix = 0,
      bool isFiado = false,
      DateTime? venc,
    }) async {
      final cliente = clientesBox.values.first;
      const preco = 10.0;
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod $id',
            quantidade: qtd,
            precoUnitario: preco,
            productId: id,
          ),
        ],
        dinheiro: dinheiro,
        pix: pix,
        lojaId: lojaId,
        isFiado: isFiado,
        dataVencimentoFiado: venc,
      );
    }

    test('estoque 0: editar forma de pagamento sem movimentar estoque', () async {
      const id = 'adm-pag-1';
      await seedProduto(id: id, qtd: 1);
      final venda = await vender(id: id, dinheiro: 10);
      expect(await qtdFirestore(id), 0);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: venda.itens!,
        pix: 10,
        dinheiro: 0,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(id), 0);
      expect(venda.pagamentoPix, closeTo(10, 0.01));
      expect(venda.pagamentoDinheiro, 0);
    });

    test('estoque 0: editar observação sem movimentar estoque', () async {
      const id = 'adm-obs-1';
      await seedProduto(id: id, qtd: 1);
      final venda = await vender(id: id);
      expect(await qtdFirestore(id), 0);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: venda.itens!,
        dinheiro: 10,
        observacao: 'Entrega agendada',
        lojaId: lojaId,
      );

      expect(await qtdFirestore(id), 0);
      expect(venda.observacao, 'Entrega agendada');
    });

    test('estoque 0: editar data sem movimentar estoque', () async {
      const id = 'adm-data-1';
      await seedProduto(id: id, qtd: 1);
      final venda = await vender(id: id);
      expect(await qtdFirestore(id), 0);
      final dataOriginal = venda.data;
      final novaData = DateTime(2026, 3, 15, 14, 30);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: venda.itens!,
        dinheiro: 10,
        lojaId: lojaId,
        dataVenda: novaData,
      );

      expect(await qtdFirestore(id), 0);
      expect(venda.data, novaData);
      expect(venda.data, isNot(equals(dataOriginal)));
    });

    test('edição administrativa preserva key Hive e idFirebase', () async {
      const id = 'pres-id-1';
      await seedProduto(id: id, qtd: 1);
      final venda = await vender(id: id);
      final hiveKeyAntes = hiveKeyOrNull(venda.key);
      expect(hiveKeyAntes, isNotNull);
      venda.idFirebase = 'venda-firestore-preservar-20260602';
      await venda.save();
      expect(vendasBox.length, 1);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: 'Cliente Atualizado',
        itens: venda.itens!,
        pix: 10,
        lojaId: lojaId,
      );

      expect(hiveKeyOrNull(venda.key), hiveKeyAntes);
      expect(venda.idFirebase, 'venda-firestore-preservar-20260602');
      expect(vendasBox.length, 1);
      expect(vendasBox.get(hiveKeyAntes), same(venda));
    });

    test('edição administrativa fiada preserva contas a receber vinculadas', () async {
      const id = 'pres-cr-1';
      await seedProduto(id: id, qtd: 2);
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
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime(2026, 7, 1),
      );
      final vk = hiveKeyOrNull(venda.key);
      expect(vk, isNotNull);

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      final crAntes = crBox.values.first;
      final crKeyAntes = crAntes.key;
      final crValorAntes = crAntes.valor;
      expect(crAntes.vendaKey, vk);
      await crBox.close();

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: venda.itens!,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime(2026, 8, 1),
        observacao: 'Vencimento ajustado',
      );

      final crBoxDepois = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBoxDepois.length, 1);
      final crDepois = crBoxDepois.get(crKeyAntes);
      expect(crDepois, isNotNull);
      expect(crDepois!.vendaKey, vk);
      expect(crDepois.valor, closeTo(crValorAntes, 0.01));
      expect(crDepois.observacao, isNot(contains('Parcela')));
      await crBoxDepois.close();
    });

    test('edição sem mudança de produtos mantém estoque', () async {
      const id = 'sem-mud-1';
      await seedProduto(id: id, qtd: 5);
      final venda = await vender(id: id, qtd: 2);
      expect(await qtdFirestore(id), 3);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: 'Outro Nome',
        itens: venda.itens!,
        dinheiro: 20,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(id), 3);
      expect(venda.clienteNome, 'Outro Nome');
    });

    test('aumentar quantidade baixa somente delta', () async {
      const id = 'delta-mais-1';
      await seedProduto(id: id, qtd: 10);
      final venda = await vender(id: id, qtd: 2, dinheiro: 20);
      expect(await qtdFirestore(id), 8);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: [
          VendaItem(
            produtoNome: 'Prod $id',
            quantidade: 3,
            precoUnitario: 10,
            productId: id,
          ),
        ],
        dinheiro: 30,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(id), 7);
    });

    test('diminuir quantidade devolve somente delta', () async {
      const id = 'delta-menos-1';
      await seedProduto(id: id, qtd: 10);
      final venda = await vender(id: id, qtd: 3, dinheiro: 30);
      expect(await qtdFirestore(id), 7);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
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

      expect(await qtdFirestore(id), 9);
    });

    test('adicionar produto baixa somente item novo', () async {
      const idA = 'add-a';
      const idB = 'add-b';
      await seedProduto(id: idA, qtd: 10);
      await seedProduto(id: idB, qtd: 5);
      final venda = await vender(id: idA, qtd: 2, dinheiro: 20);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: [
          VendaItem(
            produtoNome: 'Prod $idA',
            quantidade: 2,
            precoUnitario: 10,
            productId: idA,
          ),
          VendaItem(
            produtoNome: 'Prod $idB',
            quantidade: 1,
            precoUnitario: 10,
            productId: idB,
          ),
        ],
        dinheiro: 30,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(idA), 8);
      expect(await qtdFirestore(idB), 4);
    });

    test('remover produto devolve item removido', () async {
      const idA = 'rem-a';
      const idB = 'rem-b';
      await seedProduto(id: idA, qtd: 10);
      await seedProduto(id: idB, qtd: 10);
      final cliente = clientesBox.values.first;
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod $idA',
            quantidade: 1,
            precoUnitario: 10,
            productId: idA,
          ),
          VendaItem(
            produtoNome: 'Prod $idB',
            quantidade: 2,
            precoUnitario: 10,
            productId: idB,
          ),
        ],
        dinheiro: 30,
        lojaId: lojaId,
      );
      expect(await qtdFirestore(idA), 9);
      expect(await qtdFirestore(idB), 8);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: [
          VendaItem(
            produtoNome: 'Prod $idA',
            quantidade: 1,
            precoUnitario: 10,
            productId: idA,
          ),
        ],
        dinheiro: 10,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(idA), 9);
      expect(await qtdFirestore(idB), 10);
    });

    test('trocar produto devolve antigo e baixa novo', () async {
      const idA = 'troca-a';
      const idB = 'troca-b';
      await seedProduto(id: idA, qtd: 5);
      await seedProduto(id: idB, qtd: 3);
      final venda = await vender(id: idA, qtd: 1, dinheiro: 10);
      expect(await qtdFirestore(idA), 4);
      expect(await qtdFirestore(idB), 3);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: [
          VendaItem(
            produtoNome: 'Prod $idB',
            quantidade: 1,
            precoUnitario: 10,
            productId: idB,
          ),
        ],
        dinheiro: 10,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(idA), 5);
      expect(await qtdFirestore(idB), 2);
    });

    test('variação alterada devolve célula antiga e baixa nova', () async {
      const id = 'var-edit-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({
        'nome': 'Camiseta',
        'quantidade': 0,
        'variacoes': {
          'P': {'Azul': 2},
          'M': {'Azul': 3},
        },
      });
      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Camiseta'
          ..idFirebase = id
          ..lojaId = lojaId
          ..variacoes = {
            'P': {'Azul': 2},
            'M': {'Azul': 3},
          }
          ..precoFinal = 30,
      );

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

      var snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      var vars = snap.data()?['variacoes'] as Map?;
      expect((vars?['P'] as Map?)?['Azul'], 1);
      expect((vars?['M'] as Map?)?['Azul'], 3);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: [
          VendaItem(
            produtoNome: 'Camiseta',
            quantidade: 1,
            precoUnitario: 30,
            productId: id,
            tamanho: 'M',
            cor: 'Azul',
          ),
        ],
        dinheiro: 30,
        lojaId: lojaId,
      );

      snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      vars = snap.data()?['variacoes'] as Map?;
      expect((vars?['P'] as Map?)?['Azul'], 2);
      expect((vars?['M'] as Map?)?['Azul'], 2);
    });

    test('combo usa expansão canônica e aplica delta', () async {
      const idFilho = 'comp-edit-1';
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
        ..nome = 'Kit Edit'
        ..idFirebase = 'combo-edit-1'
        ..lojaId = lojaId
        ..tipoProduto = 'combo'
        ..quantidade = 3
        ..itensCombo = [
          {'productId': idFilho, 'nome': 'Componente', 'quantidade': 2},
        ];
      await produtosBox.addAll([comp, combo]);

      final selecao = {
        0: [
          {'productId': idFilho, 'nome': 'Componente', 'quantidade': 2},
        ],
      };
      final cliente = clientesBox.values.first;
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Kit Edit',
            quantidade: 1,
            precoUnitario: 50,
            productId: combo.idFirebase,
          ),
        ],
        dinheiro: 50,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: selecao,
      );
      expect(await qtdFirestore(idFilho), 8);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: [
          VendaItem(
            produtoNome: 'Kit Edit',
            quantidade: 2,
            precoUnitario: 50,
            productId: combo.idFirebase,
          ),
        ],
        dinheiro: 100,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: selecao,
      );

      expect(await qtdFirestore(idFilho), 6);
    });

    test('venda fiada editada sem alterar itens não mexe no estoque', () async {
      const id = 'fiado-adm-1';
      await seedProduto(id: id, qtd: 2);
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
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );
      expect(await qtdFirestore(id), 0);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: venda.itens!,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 45)),
        observacao: 'Prazo estendido',
      );

      expect(await qtdFirestore(id), 0);
      expect(venda.observacao, 'Prazo estendido');
    });

    test('pagamento misto editado sem alterar itens não mexe no estoque', () async {
      const id = 'misto-adm-1';
      await seedProduto(id: id, qtd: 5);
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
            quantidade: 3,
            precoUnitario: 100,
            productId: id,
          ),
        ],
        pix: 120,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );
      expect(await qtdFirestore(id), 2);

      await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: venda.clienteNome,
        itens: venda.itens!,
        pix: 150,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );

      expect(await qtdFirestore(id), 2);
      expect(venda.pagamentoPix, closeTo(150, 0.01));
    });

    test('conta parcialmente paga não permite reduzir total abaixo do recebido', () async {
      const id = 'parcial-bloq-1';
      await seedProduto(id: id, qtd: 5);
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
            quantidade: 3,
            precoUnitario: 100,
            productId: id,
          ),
        ],
        pix: 120,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      final cr = crBox.values.first;
      ContaReceberService.aplicarBaixaNaConta(
        conta: cr,
        valorRecebido: 120,
        formaPagamento: 'Pix',
        dataRecebimento: DateTime(2026, 6, 2),
      );
      await cr.save();
      await crBox.close();

      expect(
        () => VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: venda.clienteNome,
          itens: [
            VendaItem(
              produtoNome: 'Prod $id',
              quantidade: 2,
              precoUnitario: 100,
              productId: id,
            ),
          ],
          pix: 120,
          lojaId: lojaId,
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('valor já recebido'),
          ),
        ),
      );
    });

    test('exclusão com retorno de estoque continua funcionando', () async {
      const id = 'exc-reg-1';
      await seedProduto(id: id, qtd: 5);
      final venda = await vender(id: id, qtd: 2);
      expect(await qtdFirestore(id), 3);

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: lojaId,
      );

      expect(await qtdFirestore(id), 5);
    });
  });
}
