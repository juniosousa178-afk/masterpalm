// Venda fiada / conta a receber — validação, registro e rollback de estoque.

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
  const lojaId = 'loja-fiado-test-20260602';

  group('validarParametrosVendaFiada', () {
    test('sem cliente bloqueia com mensagem clara', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
          clienteNome: '   ',
          total: 100,
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('cliente'),
          ),
        ),
      );
    });

    test('sem vencimento bloqueia sem TypeError', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: null,
          clienteNome: 'Maria',
          total: 50,
        ),
        throwsA(
          predicate<ArgumentError>(
            (e) => e.message.toString().contains('vencimento'),
          ),
        ),
      );
    });

    test('valor zero bloqueia', () {
      expect(
        () => VendasService.validarParametrosVendaFiada(
          isFiado: true,
          dataVencimentoFiado: DateTime.now(),
          clienteNome: 'Maria',
          total: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('hiveKeyOrNull — chave Hive no web', () {
    test('aceita inteiros reais em int, num e string', () {
      expect(hiveKeyOrNull(0), 0);
      expect(hiveKeyOrNull(3), 3);
      expect(hiveKeyOrNull(7), 7);
      expect(hiveKeyOrNull(3.0), 3);
      expect(hiveKeyOrNull('3'), 3);
      expect(hiveKeyOrNull('3.0'), 3);
      expect(hiveKeyOrNull('12'), 12);
    });

    test('rejeita fracionários, negativos e tipos inválidos', () {
      expect(hiveKeyOrNull(3.5), isNull);
      expect(hiveKeyOrNull('3.5'), isNull);
      expect(hiveKeyOrNull(-1), isNull);
      expect(hiveKeyOrNull('-1'), isNull);
      expect(hiveKeyOrNull(double.nan), isNull);
      expect(hiveKeyOrNull(double.infinity), isNull);
      expect(hiveKeyOrNull(null), isNull);
      expect(hiveKeyOrNull('abc'), isNull);
      expect(hiveKeyOrNull({}), isNull);
      expect(hiveKeyOrNull([]), isNull);
    });
  });

  group('contrato vendaKey fiado', () {
    test('registrarVendaMulti usa retorno de vendasBox.add', () {
      final src = File('lib/services/vendas_service.dart').readAsStringSync();
      expect(src.contains('final addedKey = await vendasBox.add(venda)'), isTrue);
      expect(src.contains('hiveKeyOrNull(addedKey)'), isTrue);
      expect(
        src.contains('venda.key is int ? venda.key as int : 0'),
        isFalse,
        reason: 'não deve usar cast inseguro para vendaKey da conta',
      );
    });
  });

  group('registrarVendaMulti fiado', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_fiado_');
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
        'prod_fiado_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_fiado_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_fiado_${DateTime.now().microsecondsSinceEpoch}',
      );

      const productId = 'prod-fiado-1';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Produto Fiado', 'quantidade': 5});

      final p = Produto.vazio()
        ..nome = 'Produto Fiado'
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 5
        ..precoFinal = 40;
      await produtosBox.add(p);

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Fiado',
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
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    test('venda fiada válida baixa estoque, salva venda e cria conta a receber', () async {
      final cliente = clientesBox.values.first;
      final venc = DateTime.now().add(const Duration(days: 15));

      final venda = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Produto Fiado',
            quantidade: 2,
            precoUnitario: 40,
            productId: 'prod-fiado-1',
          ),
        ],
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: venc,
      );

      expect(vendasBox.length, 1);
      expect(venda.formasPagamento.toLowerCase(), contains('fiado'));
      expect(venda.pagamentoDinheiro, 0);
      expect(venda.pagamentoPix, 0);
      expect(venda.pagamentoCartao, 0);

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(lojaId),
      );
      expect(crBox.length, 1);
      final cr = crBox.values.first;
      expect(cr.clienteNome, cliente.nome);
      expect(cr.valor, closeTo(80, 0.01));
      expect(cr.vendaKey, hiveKeyOrNull(venda.key));
      await crBox.close();

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc('prod-fiado-1')
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 3);

      final hiveProd = produtosBox.values.first;
      expect(hiveProd.quantidade, 3);
    });

    test('isFiado false não exige vencimento', () async {
      final cliente = clientesBox.values.first;
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Produto Fiado',
            quantidade: 1,
            precoUnitario: 40,
            productId: 'prod-fiado-1',
          ),
        ],
        dinheiro: 40,
        lojaId: lojaId,
        isFiado: false,
        dataVencimentoFiado: null,
      );
      expect(vendasBox.length, 1);
    });
  });
}
