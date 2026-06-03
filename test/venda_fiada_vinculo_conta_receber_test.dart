// Vínculo venda fiada ↔ conta a receber (chave Hive instável no Web + idFirebase estável).

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
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-fiado-vinculo-20260603';
  const vendaUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  group('resolverVendaHiveKeyAposAdd', () {
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_fiado_vinc_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
    });

    setUp(() async {
      vendasBox = await Hive.openBox<Venda>(
        'vendas_vinc_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      await vendasBox.close();
    });

    test('retorno int de add resolve key', () {
      final v = Venda(
        clienteNome: 'A',
        produtosDescricao: 'x',
        quantidade: 1,
        preco: 10,
        total: 10,
        formasPagamento: 'Fiado',
        data: DateTime.now(),
        tamanho: '',
        vendedor: 'App',
        observacao: '',
        idFirebase: vendaUuid,
      );
      expect(
        VendasService.resolverVendaHiveKeyAposAdd(
          vendasBox: vendasBox,
          venda: v,
          addedKey: 3,
        ),
        3,
      );
    });

    test('double 3.0 no retorno de add resolve key', () {
      final v = Venda(
        clienteNome: 'A',
        produtosDescricao: 'x',
        quantidade: 1,
        preco: 10,
        total: 10,
        formasPagamento: 'Fiado',
        data: DateTime.now(),
        tamanho: '',
        vendedor: 'App',
        observacao: '',
        idFirebase: vendaUuid,
      );
      expect(
        VendasService.resolverVendaHiveKeyAposAdd(
          vendasBox: vendasBox,
          venda: v,
          addedKey: 3.0,
        ),
        3,
      );
    });

    test('retorno inválido encontra venda pelo idFirebase na box', () async {
      final v = Venda(
        clienteNome: 'Maria',
        produtosDescricao: '1 x Prod',
        quantidade: 1,
        preco: 50,
        total: 50,
        formasPagamento: 'Fiado',
        data: DateTime(2026, 6, 3),
        tamanho: '',
        vendedor: 'App',
        observacao: '',
        idFirebase: vendaUuid,
      );
      await vendasBox.add(v);
      final key = VendasService.resolverVendaHiveKeyAposAdd(
        vendasBox: vendasBox,
        venda: v,
        addedKey: Object(),
      );
      expect(key, isNotNull);
      expect(vendasBox.get(key!), isNotNull);
    });

    test('não usa vendaKey 0 como fallback silencioso quando id ausente', () {
      expect(
        VendasService.resolverVendaHiveKeyAposAdd(
          vendasBox: vendasBox,
          venda: Venda(
            clienteNome: 'X',
            produtosDescricao: '',
            quantidade: 0,
            preco: 0,
            total: 0,
            formasPagamento: '',
            data: DateTime.now(),
            tamanho: '',
            vendedor: 'App',
            observacao: '',
          ),
          addedKey: null,
        ),
        isNull,
      );
    });
  });

  group('registrarVendaMulti fiado — vínculo conta a receber', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_fiado_vinc_int_');
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
        'prod_vinc_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_vinc_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_vinc_int_${DateTime.now().microsecondsSinceEpoch}',
      );

      const productId = 'prod-vinc-fiado';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Prod Vinc', 'quantidade': 10});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Prod Vinc'
          ..idFirebase = productId
          ..lojaId = lojaId
          ..quantidade = 10
          ..precoFinal = 100,
      );

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Vinc',
          telefone: '11988887777',
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

    test('venda fiada grava idFirebase e vincula conta por key e id', () async {
      final cliente = clientesBox.values.first;
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod Vinc',
            quantidade: 1,
            precoUnitario: 100,
            productId: 'prod-vinc-fiado',
          ),
        ],
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );

      expect((venda.idFirebase ?? '').trim(), isNotEmpty);
      final vk = hiveKeyOrNull(venda.key);
      expect(vk, isNotNull);

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      final cr = crBox.values.first;
      expect(cr.vendaKey, vk);
      expect(cr.vendaIdFirebase, venda.idFirebase);
      expect(cr.valor, closeTo(100, 0.01));
      await crBox.close();
    });

    test('exclusão remove conta vinculada por vendaIdFirebase', () async {
      final cliente = clientesBox.values.first;
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod Vinc',
            quantidade: 1,
            precoUnitario: 80,
            productId: 'prod-vinc-fiado',
          ),
        ],
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 20)),
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      final idV = venda.idFirebase!;

      await VendasService.removerContasReceberVinculadasAVenda(
        lojaId: lojaId,
        vendaKey: null,
        vendaIdFirebase: idV,
      );
      expect(crBox.length, 0);
      await crBox.close();
    });

    test('pagamento misto vincula conta do saldo fiado', () async {
      final cliente = clientesBox.values.first;
      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Prod Vinc',
            quantidade: 1,
            precoUnitario: 200,
            productId: 'prod-vinc-fiado',
          ),
        ],
        pix: 50,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 45)),
      );

      expect(venda.pagamentoPix, closeTo(50, 0.01));
      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      final cr = crBox.values.first;
      expect(cr.valor, closeTo(150, 0.01));
      expect(cr.vendaIdFirebase, isNotEmpty);
      await crBox.close();
    });
  });

  group('hiveKeyOrNull — BigInt', () {
    test('aceita BigInt não negativo', () {
      expect(hiveKeyOrNull(BigInt.from(5)), 5);
      expect(hiveKeyOrNull(BigInt.from(0)), 0);
      expect(hiveKeyOrNull(BigInt.from(-1)), isNull);
    });
  });
}
