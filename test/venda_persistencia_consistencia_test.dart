// Consistência parcial: baixa remota vs persistência Hive — sem produção.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
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

Future<Map<String, dynamic>?> _estoqueRemoto(
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
  return snap.data();
}

int _qtdTotalRemota(Map<String, dynamic>? data) =>
    (data?['quantidade'] as num?)?.toInt() ?? -1;

Map<String, dynamic>? _varRemota(Map<String, dynamic>? data, String tam) {
  final vars = data?['variacoes'];
  if (vars is! Map) return null;
  final cell = vars[tam];
  return cell is Map ? Map<String, dynamic>.from(cell) : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-consistencia-venda-test';

  group('ordem e rollback documentados no código', () {
    test('registrarVendaMulti: baixa antes de vendasBox.add', () {
      final src = _vendasServiceSource();
      final iBaixa = src.indexOf('baixarEstoqueTransactionBatchIdempotente');
      final iAdd = src.indexOf('vendasBox.add(venda)');
      expect(iBaixa, greaterThan(-1));
      expect(iAdd, greaterThan(iBaixa));
    });

    test('fiado pós-add faz rollback de estoque em falha de conta a receber', () {
      final src = _vendasServiceSource();
      final iAdd = src.indexOf('vendasBox.add(venda)');
      final iDevolver = src.indexOf('devolverEstoqueParaVendaRemovida', iAdd);
      expect(iDevolver, greaterThan(iAdd));
    });

    test('syncVenda usa merge + docId estável (idempotência de retry remoto)', () {
      final src = _vendasFirestoreServiceSource();
      expect(src.contains('resolveFirestoreVendaDocId(venda)'), isTrue);
      expect(src.contains('SetOptions(merge: true)'), isTrue);
      expect(src.contains('enqueueOnFailure'), isTrue);
    });
  });

  group('registrarVendaMulti — comportamento com fakes', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_venda_consist_');
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
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => lojaId;
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_cons_$s');
      clientesBox = await Hive.openBox<Cliente>('c_cons_$s');
      vendasBox = await Hive.openBox<Venda>('v_cons_$s');
    });

    tearDown(() async {
      VendasService.debugVendasBoxAddOverride = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      VendasService.debugPersistirContasReceberNaBoxOverride = null;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      LojaAtivaResolver.debugResolveOverride = null;
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Cliente> cliente() async {
      final c = Cliente(
        nome: 'Cliente Teste',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: lojaId,
      );
      await clientesBox.add(c);
      return c;
    }

    test('falha antes da baixa: sem venda local e estoque remoto intacto', () async {
      const pid = 'prod-sem-estoque';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'nome': 'Item', 'quantidade': 1});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Item'
          ..idFirebase = pid
          ..lojaId = lojaId
          ..quantidade = 1
          ..precoFinal = 10,
      );

      final c = await cliente();
      expect(
        VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: c.nome,
          clienteExistente: c,
          itens: [
            VendaItem(
              produtoNome: 'Item',
              quantidade: 5,
              precoUnitario: 10,
              productId: pid,
            ),
          ],
          dinheiro: 50,
          lojaId: lojaId,
        ),
        throwsA(isA<Exception>()),
      );
      expect(vendasBox.length, 0);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 1);
    });

    test('sucesso: venda local criada e estoque remoto debitado uma vez', () async {
      const pid = 'prod-ok';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'nome': 'Item OK', 'quantidade': 3});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Item OK'
          ..idFirebase = pid
          ..lojaId = lojaId
          ..quantidade = 3
          ..precoFinal = 10,
      );

      final c = await cliente();
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: [
          VendaItem(
            produtoNome: 'Item OK',
            quantidade: 1,
            precoUnitario: 10,
            productId: pid,
          ),
        ],
        dinheiro: 10,
        lojaId: lojaId,
      );

      expect(vendasBox.length, 1);
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 2);
    });

    test(
        'baixa concluída e falha em vendasBox.add estorna estoque remoto (sem venda Hive)',
        () async {
      const pid = 'prod-rollback-hive';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'nome': 'Item Rollback', 'quantidade': 5});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Item Rollback'
          ..idFirebase = pid
          ..lojaId = lojaId
          ..quantidade = 5
          ..precoFinal = 10,
      );

      var addCalls = 0;
      VendasService.debugVendasBoxAddOverride = (box, venda) async {
        addCalls++;
        throw HiveError('falha simulada vendasBox.add');
      };

      final c = await cliente();
      await expectLater(
        VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: c.nome,
          clienteExistente: c,
          itens: [
            VendaItem(
              produtoNome: 'Item Rollback',
              quantidade: 1,
              precoUnitario: 10,
              productId: pid,
            ),
          ],
          dinheiro: 10,
          lojaId: lojaId,
        ),
        throwsA(isA<HiveError>()),
      );

      expect(addCalls, 1);
      expect(vendasBox.length, 0);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 5);
    });

    test('estorno pós-falha Hive é idempotente para o mesmo vendaId', () async {
      const pid = 'prod-idempotencia-estorno';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'nome': 'Item Idem', 'quantidade': 4});

      await produtosBox.add(
        Produto.vazio()
          ..nome = 'Item Idem'
          ..idFirebase = pid
          ..lojaId = lojaId
          ..quantidade = 4
          ..precoFinal = 10,
      );

      const vendaId = 'venda-estorno-idem-test';
      final txItems = [
        {'productId': pid, 'nome': 'Item Idem', 'quantidade': 1},
      ];

      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: lojaId,
        itens: txItems,
      );

      await VendasService.estornarBaixaPosFalhaAntesDePersistirVendaHive(
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendaIdEstorno: vendaId,
        txItems: txItems,
        txResultsComboCap: const [],
      );

      await VendasService.estornarBaixaPosFalhaAntesDePersistirVendaHive(
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendaIdEstorno: vendaId,
        txItems: txItems,
        txResultsComboCap: const [],
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 4);
    });

    test(
      'variação: falha em vendasBox.add restaura grade remota e total inicial',
      () async {
        const pid = 'anel-var-rollback';
        const tam = 'P';
        const corVendida = 'Azul';
        const corOutra = 'Rosa';
        const qtdInicialTotal = 6;
        const qtdAzulInicial = 2;
        const qtdRosaInicial = 1;
        const qtdMInicial = 3;

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(pid)
            .set({
          'nome': 'Anel Grade',
          'quantidade': qtdInicialTotal,
          'variacoes': {
            tam: {corVendida: qtdAzulInicial, corOutra: qtdRosaInicial},
            'M': {'Azul': qtdMInicial},
          },
          'estoquePorTamanho': {tam: 3, 'M': 3},
        });

        await produtosBox.add(
          Produto(
            nome: 'Anel Grade',
            custoReal: 1,
            frete: 0,
            gastosFixos: 0,
            gastosVariaveis: 0,
            precoSugerido: 0,
            precoFinal: 50,
            quantidade: qtdInicialTotal,
            precoUnitario: 50,
            categoria: '',
            dataEntrada: DateTime(2026, 6, 1),
            lojaId: lojaId,
            idFirebase: pid,
            variacoes: {
              tam: {corVendida: qtdAzulInicial, corOutra: qtdRosaInicial},
              'M': {'Azul': qtdMInicial},
            },
          ),
        );

        VendasService.debugVendasBoxAddOverride =
            (box, venda) async => throw HiveError('falha hive add variação');

        final c = await cliente();
        await expectLater(
          VendasService.registrarVendaMulti(
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: c.nome,
            clienteExistente: c,
            itens: [
              VendaItem(
                produtoNome: 'Anel Grade',
                quantidade: 1,
                precoUnitario: 50,
                productId: pid,
                tamanho: tam,
                cor: corVendida,
              ),
            ],
            dinheiro: 50,
            lojaId: lojaId,
          ),
          throwsA(isA<HiveError>()),
        );

        expect(vendasBox.length, 0);

        final remoto = await _estoqueRemoto(firestore, lojaId, pid);
        expect(_qtdTotalRemota(remoto), qtdInicialTotal);
        final pVars = _varRemota(remoto, tam)!;
        expect((pVars[corVendida] as num?)?.toInt(), qtdAzulInicial);
        expect((pVars[corOutra] as num?)?.toInt(), qtdRosaInicial);
        final mVars = _varRemota(remoto, 'M')!;
        expect((mVars['Azul'] as num?)?.toInt(), qtdMInicial);
      },
    );

    test(
      'combo/cap: falha em vendasBox.add estorna baixa principal e teto combo',
      () async {
        const idPingente = 'comp-combo-cap-rb';
        const idCombo = 'combo-cap-rb';
        const qtdInicialComp = 10;
        const qtdInicialCombo = 10;
        const qtdVendaComp = 4;

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idPingente)
            .set({'nome': 'Pingente Cap', 'quantidade': qtdInicialComp});
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(idCombo)
            .set({'nome': 'Colar Combo Cap', 'quantidade': qtdInicialCombo});

        await produtosBox.addAll([
          Produto.vazio()
            ..nome = 'Pingente Cap'
            ..idFirebase = idPingente
            ..lojaId = lojaId
            ..quantidade = qtdInicialComp
            ..precoFinal = 10,
          Produto.vazio()
            ..nome = 'Colar Combo Cap'
            ..idFirebase = idCombo
            ..lojaId = lojaId
            ..tipoProduto = 'combo'
            ..quantidade = qtdInicialCombo
            ..precoFinal = 100
            ..itensCombo = [
              {'productId': idPingente, 'nome': 'Pingente Cap', 'quantidade': 1},
            ],
        ]);

        final c = await cliente();
        VendasService.debugVendasBoxAddOverride =
            (box, venda) async => throw HiveError('falha hive add combo cap');

        await expectLater(
          VendasService.registrarVendaMulti(
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: c.nome,
            clienteExistente: c,
            itens: [
              VendaItem(
                produtoNome: 'Pingente Cap',
                quantidade: qtdVendaComp,
                precoUnitario: 10,
                productId: idPingente,
              ),
            ],
            dinheiro: qtdVendaComp * 10.0,
            lojaId: lojaId,
          ),
          throwsA(isA<HiveError>()),
        );

        expect(vendasBox.length, 0);

        final snapComp = await _estoqueRemoto(firestore, lojaId, idPingente);
        final snapCombo = await _estoqueRemoto(firestore, lojaId, idCombo);
        expect(_qtdTotalRemota(snapComp), qtdInicialComp);
        expect(_qtdTotalRemota(snapCombo), qtdInicialCombo);
      },
    );

    test(
      'fiado pós-add: falha ContaReceber remove venda Hive e restaura estoque',
      () async {
        const pid = 'prod-fiado-pos-add-rb';
        const qtdInicial = 5;
        ContaReceberFirestoreService.debugFirestoreOverride = firestore;

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(pid)
            .set({'nome': 'Item Fiado RB', 'quantidade': qtdInicial});

        await produtosBox.add(
          Produto.vazio()
            ..nome = 'Item Fiado RB'
            ..idFirebase = pid
            ..lojaId = lojaId
            ..quantidade = qtdInicial
            ..precoFinal = 40,
        );

        VendasService.debugPersistirContasReceberNaBoxOverride =
            ({required crBox, required contas, required lojaId, required vendaIdVinculo, required vendaHiveKey}) async {
          throw StateError('falha simulada persistência ContaReceber');
        };

        final c = await cliente();
        await expectLater(
          VendasService.registrarVendaMulti(
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: c.nome,
            clienteExistente: c,
            itens: [
              VendaItem(
                produtoNome: 'Item Fiado RB',
                quantidade: 2,
                precoUnitario: 40,
                productId: pid,
              ),
            ],
            lojaId: lojaId,
            isFiado: true,
            dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(vendasBox.length, 0);
        expect(
          _qtdTotalRemota(await _estoqueRemoto(firestore, lojaId, pid)),
          qtdInicial,
        );

        final crBox =
            await Hive.openBox<ContaReceber>(HiveBoxNames.contasReceber(lojaId));
        expect(crBox.length, 0);
        await crBox.close();
      },
    );

    test(
      'falha Hive add + falha estorno pré-Hive lança inconsistência crítica explícita',
      () async {
        const pid = 'prod-rollback-falho';
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(pid)
            .set({'nome': 'Item Rollback Falho', 'quantidade': 3});

        await produtosBox.add(
          Produto.vazio()
            ..nome = 'Item Rollback Falho'
            ..idFirebase = pid
            ..lojaId = lojaId
            ..quantidade = 3
            ..precoFinal = 10,
        );

        VendasService.debugVendasBoxAddOverride =
            (box, venda) async => throw HiveError('falha hive add crítico');
        VendasService.debugForcarFalhaEstornoPreHiveRollback = () async {
          throw StateError('falha simulada estorno pré-Hive');
        };

        final c = await cliente();
        await expectLater(
          VendasService.registrarVendaMulti(
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: c.nome,
            clienteExistente: c,
            itens: [
              VendaItem(
                produtoNome: 'Item Rollback Falho',
                quantidade: 1,
                precoUnitario: 10,
                productId: pid,
              ),
            ],
            dinheiro: 10,
            lojaId: lojaId,
          ),
          throwsA(
            predicate(
              (e) =>
                  e is VendaPersistenciaInconsistenciaCritica &&
                  e.erroPersistencia is HiveError &&
                  e.erroEstorno is StateError &&
                  e.toString().contains('persistir venda local') &&
                  e.toString().contains('restaurar estoque remoto'),
            ),
          ),
        );

        expect(vendasBox.length, 0);
      },
    );
  });
}

String _vendasServiceSource() =>
    File('lib/services/vendas_service.dart').readAsStringSync();

String _vendasFirestoreServiceSource() =>
    File('lib/services/vendas_firestore_service.dart').readAsStringSync();

