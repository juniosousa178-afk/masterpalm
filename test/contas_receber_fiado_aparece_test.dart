// Contas a receber fiado — criação, listagem e vínculo por vendaIdFirebase.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/safe_cast.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-cr-fiado-listagem-20260603';
  const vendaUuid = '11111111-2222-3333-4444-555555555555';

  group('ContaReceberService.listar', () {
    late Box<ContaReceber> crBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_cr_list_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(29)) {
        Hive.registerAdapter(ContaReceberAdapter());
      }
    });

    setUp(() async {
      crBox = await ContaReceberService.openBoxLoja(
        '${lojaId}_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      await crBox.close();
      await Hive.deleteBoxFromDisk(crBox.name);
    });

    test('conta com vendaKey -1 e vendaIdFirebase aparece em pendentes', () async {
      await crBox.add(
        ContaReceber(
          lojaId: lojaId,
          clienteNome: 'Ana Web',
          valor: 150,
          dataVencimento: DateTime.now().add(const Duration(days: 30)),
          dataVenda: DateTime.now(),
          vendaKey: -1,
          vendaIdFirebase: vendaUuid,
        ),
      );

      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 1);
      expect(list.first.vendaKey, -1);
      expect(list.first.vendaIdFirebase, vendaUuid);
    });

    test('conta paga não aparece em pendentes', () async {
      await crBox.add(
        ContaReceber(
          lojaId: lojaId,
          clienteNome: 'Pago',
          valor: 0,
          dataVencimento: DateTime.now(),
          dataVenda: DateTime.now(),
          pago: true,
          vendaKey: -1,
          vendaIdFirebase: vendaUuid,
        ),
      );
      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list, isEmpty);
    });

    test('legado sem lojaId na box da loja continua listável', () async {
      await crBox.add(
        ContaReceber(
          lojaId: '',
          clienteNome: 'Legado',
          valor: 40,
          dataVencimento: DateTime.now().add(const Duration(days: 10)),
          dataVenda: DateTime.now(),
        ),
      );
      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 1);
    });
  });

  group('registrarVendaMulti fiado — visível na listagem', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_cr_fiado_int_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
      if (!Hive.isAdapterRegistered(29)) {
        Hive.registerAdapter(ContaReceberAdapter());
      }
      if (!Hive.isAdapterRegistered(30)) {
        Hive.registerAdapter(LancamentoFinanceiroAdapter());
      }
    });

    tearDownAll(() async {
      LojaAtivaResolver.debugResolveOverride = null;
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => lojaId;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
      ContaReceberFirestoreService.debugFirestoreOverride = firestore;
      FinanceiroFirestoreService.debugFirestoreOverride = firestore;

      produtosBox = await Hive.openBox<Produto>(
        'prod_cr_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_cr_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_cr_${DateTime.now().microsecondsSinceEpoch}',
      );

      const productId = 'prod-cr-fiado';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Prod CR', 'quantidade': 20});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Prod CR'
          ..idFirebase = productId
          ..lojaId = lojaId
          ..quantidade = 20
          ..precoFinal = 50,
      );

      await clientesBox.add(
        Cliente(
          nome: 'Cliente CR',
          telefone: '11977776666',
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId,
        ),
      );
    });

    tearDown(() async {
      LojaAtivaResolver.debugResolveOverride = null;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
      FinanceiroFirestoreService.debugFirestoreOverride = null;
      try {
        await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(lojaId));
      } catch (_) {}
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<void> seedVendaFiada({
      double preco = 50,
      int qtd = 1,
      double pix = 0,
      int parcelas = 1,
    }) async {
      final cliente = clientesBox.values.first;
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod CR',
            quantidade: qtd,
            precoUnitario: preco,
            productId: 'prod-cr-fiado',
          ),
        ],
        pix: pix,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 25)),
        quantidadeParcelasFiado: parcelas,
        intervaloParcelasDias: 30,
      );
    }

    test('venda fiada integral aparece na listagem pendentes', () async {
      await seedVendaFiada();
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 1);
      expect(list.first.valor, closeTo(50, 0.01));
      expect(list.first.vendaIdFirebase, isNotEmpty);
      await crBox.close();
    });

    test('venda fiada com vendaKey -1 simulado continua listável', () async {
      await seedVendaFiada(preco: 90);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      final cr = crBox.values.first;
      cr.vendaKey = -1;
      await cr.save();

      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 1);
      expect(list.first.vendaKey, -1);
      expect(list.first.vendaIdFirebase, isNotEmpty);
      await crBox.close();
    });

    test('pagamento misto lista só saldo fiado', () async {
      await seedVendaFiada(preco: 200, pix: 80);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 1);
      expect(list.first.valor, closeTo(120, 0.01));
      await crBox.close();
    });

    test('parcelamento cria todas as parcelas listáveis', () async {
      await seedVendaFiada(preco: 100, qtd: 3, parcelas: 3);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 3);
      expect(list.fold<double>(0, (s, c) => s + c.valor), closeTo(300, 0.02));
      await crBox.close();
    });

    test('venda à vista não cria conta listável', () async {
      final cliente = clientesBox.values.first;
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod CR',
            quantidade: 1,
            precoUnitario: 50,
            productId: 'prod-cr-fiado',
          ),
        ],
        dinheiro: 50,
        lojaId: lojaId,
        isFiado: false,
      );
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(
        ContaReceberService.listar(
          contas: crBox.values,
          lojaId: lojaId,
          filtro: 'pendentes',
        ),
        isEmpty,
      );
      await crBox.close();
    });

    test('exclusão por vendaIdFirebase remove da listagem', () async {
      await seedVendaFiada();
      final venda = vendasBox.values.first;
      final idV = venda.idFirebase!;
      await VendasService.removerContasReceberVinculadasAVenda(
        lojaId: lojaId,
        vendaKey: null,
        vendaIdFirebase: idV,
      );
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(
        ContaReceberService.listar(
          contas: crBox.values,
          lojaId: lojaId,
          filtro: 'pendentes',
        ),
        isEmpty,
      );
      await crBox.close();
    });

    test('baixa parcial mantém conta vinculada por vendaIdFirebase', () async {
      await seedVendaFiada(preco: 100);
      await FinanceiroHiveStore.openLancamentosBox(lojaId);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      final cr = crBox.values.first;
      final idV = cr.vendaIdFirebase;
      cr.vendaKey = -1;
      await cr.save();
      final key = hiveKeyOrNull(cr.key);
      expect(key, isNotNull);

      final resultado = await ContaReceberService.registrarBaixa(
        conta: cr,
        valorRecebido: 40,
        formaPagamento: 'Pix',
        lojaId: lojaId,
        contaHiveKey: key!,
        dataRecebimento: DateTime.now(),
      );
      expect(resultado.sucesso, isTrue);
      expect(cr.saldoRestante, closeTo(60, 0.01));

      final list = ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(list.length, 1);
      expect(list.first.vendaIdFirebase, idV);
      await crBox.close();
    });
  });
}
