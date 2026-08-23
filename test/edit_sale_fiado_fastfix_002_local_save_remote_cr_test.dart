// EDIT_SALE_FIADO_FASTFIX_002 — edit full-fiado: local OK + remote CR pendência.
// Sem integration_test / Firebase de produção.

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

  const lojaId = 'loja-fastfix-edit-fiado-002';
  const productId = 'prod-fastfix-edit-fiado-002';
  const totalReais = 255.0;

  group('EDIT_SALE_FIADO_FASTFIX_002 source contract', () {
    test('remoteBestEffort + timeout + Faltam/_pendenteFiado no código', () {
      final svc = File('lib/services/vendas_service.dart').readAsStringSync();
      expect(svc.contains('class VendaSalvaComPendenciaSyncException'), isTrue);
      expect(svc.contains('remoteBestEffort: true'), isTrue);
      expect(svc.contains('_remoteCrSyncTimeout'), isTrue);
      expect(svc.contains('Duration(seconds: 15)'), isTrue);

      final modal = File(
        'lib/screens/nova_venda_modal.dart',
      ).readAsStringSync();
      expect(
        modal.contains('on VendaSalvaComPendenciaSyncException catch'),
        isTrue,
      );
      expect(modal.contains('falta > 0 && _pendenteFiado'), isTrue);
      expect(modal.contains('Saldo fiado:'), isTrue);
    });

    test('isPendenciaMessage reconhece mensagem canónica', () {
      expect(
        VendaSalvaComPendenciaSyncException.isPendenciaMessage(
          VendaSalvaComPendenciaSyncException.defaultMessage,
        ),
        isTrue,
      );
      expect(
        VendaSalvaComPendenciaSyncException.isPendenciaMessage(
          'A venda não foi salva.',
        ),
        isFalse,
      );
    });
  });

  group('editarVendaMulti full-fiado local OK + CR remota pendente', () {
    late FakeFirebaseFirestore firestore;
    late String hivePath;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp(
        'hive_fastfix_edit_fiado_',
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

      produtosBox = await Hive.openBox<Produto>(
        'prod_ff002_${DateTime.now().microsecondsSinceEpoch}',
      );
      clientesBox = await Hive.openBox<Cliente>(
        'cli_ff002_${DateTime.now().microsecondsSinceEpoch}',
      );
      vendasBox = await Hive.openBox<Venda>(
        'vendas_ff002_${DateTime.now().microsecondsSinceEpoch}',
      );

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({'nome': 'Produto Fastfix', 'quantidade': 20});

      final p = Produto.vazio()
        ..nome = 'Produto Fastfix'
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 20
        ..precoFinal = totalReais;
      await produtosBox.add(p);

      await clientesBox.add(
        Cliente(
          nome: 'Cliente Fastfix Fiado',
          telefone: '11977776666',
          instagram: '',
          cep: '',
          cidade: '',
          lojaId: lojaId,
        ),
      );
    });

    tearDown(() async {
      VendasService.debugPersistirContasReceberNaBoxOverride = null;
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

    Future<Venda> criarVendaPaga255() {
      final cliente = clientesBox.values.first;
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: cliente.nome,
        clienteExistente: cliente,
        itens: [
          VendaItem(
            produtoNome: 'Produto Fastfix',
            quantidade: 1,
            precoUnitario: totalReais,
            productId: productId,
          ),
        ],
        pix: totalReais,
        lojaId: lojaId,
        isFiado: false,
      );
    }

    test(
        'remote CR falha após Hive → VendaSalvaComPendenciaSyncException; '
        'venda+CR locais intactos', () async {
      final venda = await criarVendaPaga255();
      final cliente = clientesBox.values.first;

      VendasService.debugPersistirContasReceberNaBoxOverride = ({
        required crBox,
        required contas,
        required lojaId,
        required vendaIdVinculo,
        required vendaHiveKey,
      }) async {
        for (final c in contas) {
          await crBox.add(c);
          try {
            await c.save();
          } catch (_) {}
        }
        throw const VendaSalvaComPendenciaSyncException();
      };

      await expectLater(
        () => VendasService.editarVendaMulti(
          vendaOriginal: venda,
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: cliente.nome,
          clienteExistente: cliente,
          itens: venda.itens!,
          dinheiro: 0,
          pix: 0,
          cartao: 0,
          lojaId: lojaId,
          isFiado: true,
          dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
        ),
        throwsA(isA<VendaSalvaComPendenciaSyncException>()),
      );

      expect(venda.pagamentoDinheiro, 0);
      expect(venda.pagamentoPix, 0);
      expect(venda.pagamentoCartao, 0);
      expect(venda.total, closeTo(totalReais, 0.01));
      expect(venda.formasPagamento.toLowerCase(), contains('fiado'));

      final crBox = await ContaReceberService.openBoxLoja(lojaId);
      expect(crBox.length, greaterThan(0));
      final aberto = crBox.values.fold<double>(0, (s, c) => s + c.valor);
      expect((aberto * 100).round(), 25500);
      await crBox.close();
    });
  });
}
