// Cenários mínimos: venda fiada → conta a receber (criação, misto, vínculo, rollback).

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
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-fiado-criacao-20260609';

  group('ContaReceberService.openBoxLoja', () {
    test('lojaId vazio retorna erro claro', () async {
      expect(
        () => ContaReceberService.openBoxLoja('  '),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('lojaId vazio'),
          ),
        ),
      );
    });
  });

  group('validarParametrosVendaFiada — pré-save', () {
    test('sem cliente bloqueia antes de salvar', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
          clienteNome: '',
          total: 132.70,
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().toLowerCase().contains('cliente'),
          ),
        ),
      );
    });

    test('saldo zero não exige vencimento', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: null,
          clienteNome: 'Maria',
          total: 100,
          totalPagoAgora: 100,
        ),
        returnsNormally,
      );
    });
  });

  group('registrarVendaMulti — conta a receber', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_fiado_criacao_');
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

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

      produtosBox = await Hive.openBox<Produto>(
        'prod_criacao_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_criacao_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_criacao_${DateTime.now().microsecondsSinceEpoch}',
      );

      const productId = 'prod-fiado-criacao';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Prod Fiado', 'quantidade': 20});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Prod Fiado'
          ..idFirebase = productId
          ..lojaId = lojaId
          ..quantidade = 20
          ..precoFinal = 132.70,
      );

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Teste Fiado',
          telefone: '11999990000',
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

    Future<Venda> vendaFiada({
      double preco = 132.70,
      int qtd = 1,
      double dinheiro = 0,
      double pix = 0,
      double cartao = 0,
      int parcelas = 1,
    }) {
      final cliente = clientesBox.values.first;
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod Fiado',
            quantidade: qtd,
            precoUnitario: preco,
            productId: 'prod-fiado-criacao',
          ),
        ],
        dinheiro: dinheiro,
        pix: pix,
        cartao: cartao,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
        quantidadeParcelasFiado: parcelas,
      );
    }

    test('1 — fiado puro com cliente válido cria conta a receber', () async {
      final venda = await vendaFiada();
      expect(vendasBox.length, 1);

      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.length, 1);
      final cr = crBox.values.first;
      expect(cr.clienteNome, 'Cliente Teste Fiado');
      expect(cr.valor, closeTo(132.70, 0.01));
      expect(cr.vendaIdFirebase, isNotEmpty);
      expect(cr.vendaIdFirebase, venda.idFirebase);
      await crBox.close();
    });

    test('2 — pagamento misto cria conta só do saldo', () async {
      await vendaFiada(preco: 200, pix: 67.30);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.length, 1);
      expect(crBox.values.first.valor, closeTo(132.70, 0.01));
      await crBox.close();
    });

    test('4 — valor restante zero não cria conta', () async {
      await vendaFiada(dinheiro: 132.70);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.length, 0);
      await crBox.close();
    });

    test('5 — vendaKey -1 com vendaIdFirebase estável vincula conta', () async {
      final venda = await vendaFiada();
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      final cr = crBox.values.first;
      cr.vendaKey = -1;
      await cr.save();
      expect(cr.vendaIdFirebase, venda.idFirebase);
      expect(cr.vendaIdFirebase, isNotEmpty);
      await crBox.close();
    });

    test('7 — conta vinculada por vendaIdFirebase', () async {
      final venda = await vendaFiada();
      final idV = venda.idFirebase!;
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.values.every((c) => c.vendaIdFirebase == idV), isTrue);
      await crBox.close();
    });

    test('8 — exclusão localiza conta por vendaIdFirebase', () async {
      final venda = await vendaFiada();
      final idV = venda.idFirebase!;
      await VendasService.removerContasReceberVinculadasAVenda(
        lojaId: lojaId,
        vendaKey: null,
        vendaIdFirebase: idV,
      );
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.length, 0);
      await crBox.close();
    });

    test('6 — falha ao abrir box com lojaId vazio bloqueia venda', () async {
      final cliente = clientesBox.values.first;
      expect(
        () => VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: [
            VendaItem(
              produtoNome: 'Prod Fiado',
              quantidade: 1,
              precoUnitario: 50,
              productId: 'prod-fiado-criacao',
            ),
          ],
          lojaId: '   ',
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(vendasBox.length, 0);
    });

    test('parcelamento cria N contas somando o saldo', () async {
      await vendaFiada(preco: 100, qtd: 3, parcelas: 3);
      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.length, 3);
      expect(
        crBox.values.fold<double>(0, (s, c) => s + c.valor),
        closeTo(300, 0.02),
      );
      await crBox.close();
    });
  });

  group('calcularSaldoFiado', () {
    test('132,70 total sem pagamento = saldo fiado integral', () {
      expect(
        VendasService.calcularSaldoFiado(total: 132.70, totalPagoAgora: 0),
        closeTo(132.70, 0.01),
      );
    });
  });
}
