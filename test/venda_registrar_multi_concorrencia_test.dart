// Concorrência em registrarVendaMulti — coalescência service-level.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<int> _qtdRemota(
  FakeFirebaseFirestore firestore,
  String lojaId,
  String productId,
) async {
  final snap = await firestore
      .collection('lojas')
      .doc(lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(productId)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-concorrencia-venda-test';

  group('registrarVendaMulti — concorrência', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_venda_conc_');
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

    Future<Cliente> seedCliente({String nome = 'Cliente Conc'}) async {
      final c = Cliente(
        nome: nome,
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: lojaId,
      );
      await clientesBox.add(c);
      return c;
    }

    Future<void> seedProduto({
      required String pid,
      required String nome,
      required int qtd,
      double preco = 10,
    }) async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'nome': nome, 'quantidade': qtd});
      await produtosBox.add(
        Produto.vazio()
          ..nome = nome
          ..idFirebase = pid
          ..lojaId = lojaId
          ..quantidade = qtd
          ..precoFinal = preco,
      );
    }

    Future<Venda> registrar({
      required Cliente c,
      required List<VendaItem> itens,
      double dinheiro = 10,
      bool isFiado = false,
      DateTime? vencimento,
    }) {
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: itens,
        dinheiro: dinheiro,
        lojaId: lojaId,
        isFiado: isFiado,
        dataVencimentoFiado: vencimento,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => lojaId;
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      ContaReceberFirestoreService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_conc_$s');
      clientesBox = await Hive.openBox<Cliente>('c_conc_$s');
      vendasBox = await Hive.openBox<Venda>('v_conc_$s');
    });

    tearDown(() async {
      VendasService.debugVendasBoxAddOverride = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      VendasService.debugPersistirContasReceberNaBoxOverride = null;
      VendasService.debugAntesBaixaEstoqueBarrier = null;
      VendasService.debugOperacoesEmAndamentoClearForTests();
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      LojaAtivaResolver.debugResolveOverride = null;
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    test('CENÁRIO 1/2 — mesma operação concorrente é coalescida', () async {
      const pid = 'prod-dup';
      await seedProduto(pid: pid, nome: 'Dup', qtd: 10);
      final c = await seedCliente();
      final itens = [
        VendaItem(
          produtoNome: 'Dup',
          quantidade: 1,
          precoUnitario: 10,
          productId: pid,
        ),
      ];

      final v1 = registrar(c: c, itens: itens);
      final v2 = registrar(c: c, itens: itens);
      final results = await Future.wait([v1, v2]);

      expect(identical(results[0], results[1]), isTrue);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, lojaId, pid), 9);
    });

    test('CENÁRIO 2b — cópias idênticas sequenciais geram duas vendas', () async {
      const pid = 'prod-seq';
      await seedProduto(pid: pid, nome: 'Seq', qtd: 10);
      final c = await seedCliente();
      final itens = [
        VendaItem(
          produtoNome: 'Seq',
          quantidade: 1,
          precoUnitario: 10,
          productId: pid,
        ),
      ];

      await registrar(c: c, itens: itens);
      await registrar(c: c, itens: itens);

      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, lojaId, pid), 8);
    });

    test('CENÁRIO 3 — vendas diferentes na mesma loja concluem em paralelo', () async {
      await seedProduto(pid: 'prod-a', nome: 'A', qtd: 5);
      await seedProduto(pid: 'prod-b', nome: 'B', qtd: 5);
      final c = await seedCliente();

      await Future.wait([
        registrar(
          c: c,
          itens: [
            VendaItem(
              produtoNome: 'A',
              quantidade: 1,
              precoUnitario: 10,
              productId: 'prod-a',
            ),
          ],
        ),
        registrar(
          c: c,
          itens: [
            VendaItem(
              produtoNome: 'B',
              quantidade: 1,
              precoUnitario: 20,
              productId: 'prod-b',
            ),
          ],
          dinheiro: 20,
        ),
      ]);

      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, lojaId, 'prod-a'), 4);
      expect(await _qtdRemota(firestore, lojaId, 'prod-b'), 4);
    });

    test('CENÁRIO 4 — duplicata concorrente com estoque 1 não duplica venda', () async {
      const pid = 'prod-disputa';
      await seedProduto(pid: pid, nome: 'Único', qtd: 1);
      final c = await seedCliente();
      final itens = [
        VendaItem(
          produtoNome: 'Único',
          quantidade: 1,
          precoUnitario: 10,
          productId: pid,
        ),
      ];

      final results = await Future.wait([
        registrar(c: c, itens: itens),
        registrar(c: c, itens: itens),
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, lojaId, pid), 0);
    });

    test('CENÁRIO 4b — clientes distintos disputando último item (fake FS)', () async {
      const pid = 'prod-disputa-cli';
      await seedProduto(pid: pid, nome: 'Único B', qtd: 1);
      final c1 = await seedCliente(nome: 'Cliente A');
      final c2 = await seedCliente(nome: 'Cliente B');
      final itens = [
        VendaItem(
          produtoNome: 'Único B',
          quantidade: 1,
          precoUnitario: 10,
          productId: pid,
        ),
      ];

      final results = await Future.wait<Object?>([
        registrar(c: c1, itens: itens).then((v) => v),
        registrar(c: c2, itens: itens).catchError((e) => e),
      ]);

      final sucessos = results.whereType<Venda>().length;
      expect(sucessos, greaterThanOrEqualTo(1));
      expect(vendasBox.length, lessThanOrEqualTo(2));
      expect(await _qtdRemota(firestore, lojaId, pid), greaterThanOrEqualTo(0));
    });

    test('CENÁRIO 5 — falha libera coalescência para nova tentativa', () async {
      const pid = 'prod-fail-lock';
      await seedProduto(pid: pid, nome: 'Lock', qtd: 3);
      final c = await seedCliente();
      final itens = [
        VendaItem(
          produtoNome: 'Lock',
          quantidade: 1,
          precoUnitario: 10,
          productId: pid,
        ),
      ];

      VendasService.debugVendasBoxAddOverride = (_, __) async {
        throw StateError('falha hive simulada');
      };

      await expectLater(
        registrar(c: c, itens: itens),
        throwsA(isA<StateError>()),
      );
      expect(vendasBox.length, 0);

      VendasService.debugVendasBoxAddOverride = null;
      await registrar(c: c, itens: itens);
      expect(vendasBox.length, 1);
    });

    test('CENÁRIO 6 — fiado concorrente idêntico não duplica venda', () async {
      const pid = 'prod-fiado-conc';
      await seedProduto(pid: pid, nome: 'Fiado', qtd: 5);
      final c = await seedCliente();
      final venc = DateTime.now().add(const Duration(days: 30));
      final itens = [
        VendaItem(
          produtoNome: 'Fiado',
          quantidade: 1,
          precoUnitario: 50,
          productId: pid,
        ),
      ];

      final results = await Future.wait([
        registrar(
          c: c,
          itens: itens,
          dinheiro: 0,
          isFiado: true,
          vencimento: venc,
        ),
        registrar(
          c: c,
          itens: itens,
          dinheiro: 0,
          isFiado: true,
          vencimento: venc,
        ),
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(vendasBox.length, 1);
    });
  });
}
