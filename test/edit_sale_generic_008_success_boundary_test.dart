// EDIT_SALE_GENERIC_008 — non-fiado success boundary (OPTION_3).
// Local/synthetic only. Sem Firebase de produção.

import 'dart:async';
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
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-edit-generic-008';
  const productId = 'prod-edit-generic-008';
  const totalReais = 255.0;

  group('EDIT_SALE_GENERIC_008 source contract', () {
    test('CR pré-save + sync remoto não bloqueia sucesso', () {
      final svc = File('lib/services/vendas_service.dart').readAsStringSync();
      expect(
        svc.contains('_validarRemocaoContasReceberAntesDeMutarVenda'),
        isTrue,
      );
      expect(svc.contains('_agendarSyncRemotoAposEdicaoLocal'), isTrue);
      expect(
        svc.contains('mensagemNaoPodeRemoverFiadoComRecebimentosParciais'),
        isTrue,
      );
      expect(
        svc.contains(
          'Não é possível remover o fiado: existem recebimentos parciais nesta venda.',
        ),
        isTrue,
      );

      final modal = File(
        'lib/screens/nova_venda_modal.dart',
      ).readAsStringSync();
      expect(modal.contains('sync remoto após fechar editor'), isTrue);
      expect(
        modal.contains('on VendaSalvaComPendenciaSyncException catch'),
        isTrue,
      );
      expect(modal.contains('Saldo fiado:'), isTrue);
    });
  });

  group('EDIT_SALE_GENERIC_008 E1–E8', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp(
        'hive_edit_generic_008_',
      );
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) {
        Hive.registerAdapter(VendaItemAdapter());
      }
      if (!Hive.isAdapterRegistered(29)) {
        Hive.registerAdapter(ContaReceberAdapter());
      }
    });

    tearDownAll(() async {
      LojaAtivaResolver.debugResolveOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
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
      VendasService.debugPersistirContasReceberNaBoxOverride = null;
      VendasService.debugEditarVendaSyncClienteOverride = null;
      VendasService.debugEditarVendaSyncVendaOverride = null;
      VendasService.debugForcarFalhaTransicaoCrLocalEdicao = null;
      VendasService.debugForcarFalhaEstoqueEdicaoAntesSave = null;

      produtosBox = await Hive.openBox<Produto>(
        'prod_eg008_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_eg008_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_eg008_${DateTime.now().microsecondsSinceEpoch}',
      );

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Produto 008', 'quantidade': 20});

      final p = Produto.vazio()
        ..nome = 'Produto 008'
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 20
        ..precoFinal = totalReais;
      await produtosBox.add(p);

      await clientesBox.add(
        Cliente(
          nome: 'Cliente 008',
          telefone: '11966665555',
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId,
        ),
      );
    });

    tearDown(() async {
      VendasService.debugPersistirContasReceberNaBoxOverride = null;
      VendasService.debugEditarVendaSyncClienteOverride = null;
      VendasService.debugEditarVendaSyncVendaOverride = null;
      VendasService.debugForcarFalhaTransicaoCrLocalEdicao = null;
      VendasService.debugForcarFalhaEstoqueEdicaoAntesSave = null;
      LojaAtivaResolver.debugResolveOverride = null;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
      try {
        await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(lojaId));
      } catch (_) {}
    });

    List<VendaItem> itemUnico({int qtd = 1, double preco = totalReais}) => [
      VendaItem(
        produtoNome: 'Produto 008',
        quantidade: qtd,
        precoUnitario: preco,
        productId: productId,
      ),
    ];

    Future<Venda> criarVendaPix255() {
      final cliente = clientesBox.values.first;
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: itemUnico(),
        pix: totalReais,
        lojaId: lojaId,
        isFiado: false,
      );
    }

    Future<Venda> criarVendaFiada255() {
      final cliente = clientesBox.values.first;
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: itemUnico(),
        dinheiro: 0,
        pix: 0,
        cartao: 0,
        lojaId: lojaId,
        isFiado: true,
        dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      );
    }

    Map<String, Object?> snapVenda(Venda v) => {
      'total': v.total,
      'pix': v.pagamentoPix,
      'dinheiro': v.pagamentoDinheiro,
      'cartao': v.pagamentoCartao,
      'formas': v.formasPagamento,
      'cliente': v.clienteNome,
    };

    test('E1 existing non-fiado Pix total no CR → edit succeeds', () async {
      final venda = await criarVendaPix255();
      final cliente = clientesBox.values.first;
      final crBefore = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBefore.length, 0);
      await crBefore.close();

      final edited = await VendasService.editarVendaMulti(
        vendaOriginal: venda,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: itemUnico(),
        pix: totalReais,
        lojaId: lojaId,
        isFiado: false,
        observacao: 'e1-ok',
      );

      expect(edited.pagamentoPix, closeTo(totalReais, 0.01));
      expect(edited.observacao, 'e1-ok');
      final crAfter = await ContaReceberService.openBoxLoja(lojaId);
      expect(crAfter.length, 0);
      await crAfter.close();
    });

    test(
      'E2 fiado CR saldo>0 valorPago=0 → non-fiado paid → CR removed + ok',
      () async {
        final venda = await criarVendaFiada255();
        final cliente = clientesBox.values.first;
        final crBox = await ContaReceberService.openBoxLoja(lojaId);
        expect(crBox.length, greaterThan(0));
        expect(crBox.values.every((c) => c.valorPago <= 0.01), isTrue);
        await crBox.close();

        final edited = await VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: itemUnico(),
          pix: totalReais,
          lojaId: lojaId,
          isFiado: false,
        );

        expect(edited.pagamentoPix, closeTo(totalReais, 0.01));
        expect(edited.formasPagamento.toLowerCase(), contains('pix'));
        expect(edited.formasPagamento.toLowerCase(), isNot(contains('fiado')));

        final crAfter = await ContaReceberService.openBoxLoja(lojaId);
        expect(crAfter.length, 0);
        await crAfter.close();
      },
    );

    test(
      'E3 CR valorPago>0 → validation before save; sale unchanged; no success',
      () async {
        final venda = await criarVendaFiada255();
        final cliente = clientesBox.values.first;

        final crBox = await ContaReceberService.openBoxLoja(lojaId);
        final cr = crBox.values.first;
        ContaReceberService.aplicarBaixaNaConta(
          conta: cr,
          valorRecebido: 50,
          formaPagamento: 'Pix',
          dataRecebimento: DateTime(2026, 8, 1),
        );
        await cr.save();
        final crValorPago = cr.valorPago;
        expect(crValorPago, greaterThan(0.01));
        final crLen = crBox.length;
        await crBox.close();

        final before = snapVenda(venda);

        await expectLater(
          () => VendasService.editarVendaMulti(
            vendaOriginal: venda,
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: cliente.nome,
            clienteExistente: cliente,
            itens: itemUnico(),
            pix: totalReais,
            lojaId: lojaId,
            isFiado: false,
          ),
          throwsA(
            predicate<ArgumentError>(
              (e) => e.message.toString().contains(
                'Não é possível remover o fiado: existem recebimentos parciais nesta venda.',
              ),
            ),
          ),
        );

        expect(snapVenda(venda), before);
        expect(venda.pagamentoPix, closeTo(0, 0.01));
        expect(venda.formasPagamento.toLowerCase(), contains('fiado'));

        final crAfter = await ContaReceberService.openBoxLoja(lojaId);
        expect(crAfter.length, crLen);
        expect(crAfter.values.first.valorPago, closeTo(crValorPago, 0.01));
        await crAfter.close();
      },
    );

    test(
      'E4 syncCliente throws after local success → edit still succeeds',
      () async {
        final venda = await criarVendaPix255();
        final cliente = clientesBox.values.first;
        var syncClienteCalled = false;
        VendasService.debugEditarVendaSyncClienteOverride =
            (c, {required lojaId}) async {
              syncClienteCalled = true;
              throw StateError('syncCliente synthetic fail');
            };
        VendasService.debugEditarVendaSyncVendaOverride =
            (v, {required lojaId}) async => true;

        final edited = await VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: itemUnico(),
          pix: totalReais,
          lojaId: lojaId,
          isFiado: false,
          observacao: 'e4',
        );

        expect(edited.observacao, 'e4');
        // Detached: allow microtask pump.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(syncClienteCalled, isTrue);
      },
    );

    test(
      'E5 syncVenda throws after local success → edit still succeeds',
      () async {
        final venda = await criarVendaPix255();
        final cliente = clientesBox.values.first;
        VendasService.debugEditarVendaSyncClienteOverride =
            (c, {required lojaId}) async {};
        VendasService.debugEditarVendaSyncVendaOverride =
            (v, {required lojaId}) async {
              throw StateError('syncVenda synthetic fail');
            };

        final edited = await VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: itemUnico(),
          pix: totalReais,
          lojaId: lojaId,
          isFiado: false,
          observacao: 'e5',
        );

        expect(edited.observacao, 'e5');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );

    test(
      'E6 remote delay: local success returns before remote completes',
      () async {
        final venda = await criarVendaPix255();
        final cliente = clientesBox.values.first;
        final gate = Completer<void>();
        var remoteStarted = false;

        VendasService.debugEditarVendaSyncClienteOverride =
            (c, {required lojaId}) async {
              remoteStarted = true;
              await gate.future;
            };
        VendasService.debugEditarVendaSyncVendaOverride =
            (v, {required lojaId}) async {
              await gate.future;
              return true;
            };

        final edited = await VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: itemUnico(),
          pix: totalReais,
          lojaId: lojaId,
          isFiado: false,
          observacao: 'e6',
        ).timeout(const Duration(seconds: 2));

        expect(edited.observacao, 'e6');
        expect(gate.isCompleted, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(remoteStarted, isTrue);
        gate.complete();
      },
    );

    test('E7 required CR local transition fails → no fake success', () async {
      final venda = await criarVendaFiada255();
      final cliente = clientesBox.values.first;
      VendasService.debugForcarFalhaTransicaoCrLocalEdicao = () async {
        throw StateError('CR local transition synthetic fail');
      };

      await expectLater(
        () => VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: itemUnico(),
          pix: totalReais,
          lojaId: lojaId,
          isFiado: false,
        ),
        throwsA(isA<StateError>()),
      );

      // Venda pode ter sido salva antes da falha de CR — não é sucesso de UI.
      // CR deve permanecer (delete não concluído).
      final crAfter = await ContaReceberService.openBoxLoja(lojaId);
      expect(crAfter.length, greaterThan(0));
      await crAfter.close();
    });

    test(
      'E8 stock required fails before local save → no fake success',
      () async {
        final venda = await criarVendaPix255();
        final cliente = clientesBox.values.first;
        final before = snapVenda(venda);

        VendasService.debugForcarFalhaEstoqueEdicaoAntesSave = () async {
          throw StateError('stock edit synthetic fail');
        };

        await expectLater(
          () => VendasService.editarVendaMulti(
            vendaOriginal: venda,
            produtosBox: produtosBox,
            clientesBox: clientesBox,
            vendasBox: vendasBox,
            clienteNome: cliente.nome,
            clienteExistente: cliente,
            // muda quantidade → delta de estoque obrigatório
            itens: itemUnico(qtd: 2, preco: totalReais / 2),
            pix: totalReais,
            lojaId: lojaId,
            isFiado: false,
          ),
          throwsA(isA<StateError>()),
        );

        expect(snapVenda(venda), before);
      },
    );
  });
}
