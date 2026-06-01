// Produto recém-criado / tombstone no slug: mensagem clara antes da baixa Firestore.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_estoque_doc_id_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'nathy-pratas-e-folheados';
  const slugTeste = 'nathy-pratas-e-folheados-teste';
  const slugTesteSeguro = 'nathy-pratas-e-folheados-teste-2';

  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_venda_prep_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
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
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_$s');
    clientesBox = await Hive.openBox<Cliente>('c_$s');
    vendasBox = await Hive.openBox<Venda>('v_$s');
  });

  tearDown(() async {
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    EstoqueTransactionService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await produtosBox.close();
    await clientesBox.close();
    await vendasBox.close();
  });

  Future<void> tombstoneProduto(String docId) async {
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.exclusaoProdutoCol)
        .doc(docId)
        .set({'p': true});
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
  }

  Produto produtoTesteLocal({String idFirebase = ''}) {
    return Produto.vazio()
      ..nome = 'Teste'
      ..slug = slugTeste
      ..idFirebase = idFirebase
      ..lojaId = lojaId
      ..quantidade = 1
      ..precoFinal = 29.9
      ..updatedAt = DateTime.now();
  }

  Future<Cliente> cliente() async {
    final c = Cliente(
      nome: 'Cliente',
      telefone: '11',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<void> venderTeste(Produto p) async {
    final c = await cliente();
    await VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: c.nome,
      clienteExistente: c,
      itens: [
        VendaItem(
          produtoNome: p.nome,
          quantidade: 1,
          precoUnitario: 29.9,
          productId: p.idFirebase.isNotEmpty
              ? p.idFirebase
              : (p.slug.isNotEmpty ? p.slug : null),
        ),
      ],
      dinheiro: 29.9,
      lojaId: lojaId,
    );
  }

  group('ProdutoEstoqueDocIdService — cadastro', () {
    test('sem tombstone: slug canônico base', () async {
      final id = await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
        lojaId: lojaId,
        nome: 'Teste',
      );
      expect(id, slugTeste);
    });

    test('tombstone no slug base: gera sufixo -2', () async {
      await tombstoneProduto(slugTeste);

      final id = await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
        lojaId: lojaId,
        nome: 'Teste',
      );

      expect(id, slugTesteSeguro);
      expect(id, isNot(slugTeste));
      expect(
        await ProdutoEstoqueDocIdService.docIdIndisponivelParaNovoProduto(
          lojaId: lojaId,
          docId: slugTeste,
        ),
        isTrue,
      );
      expect(
        await ProdutoEstoqueDocIdService.docIdIndisponivelParaNovoProduto(
          lojaId: lojaId,
          docId: id,
        ),
        isFalse,
      );
    });

    test(
      'fluxo cadastro+venda: novo Teste não usa id tombstonado e finaliza venda',
      () async {
        await tombstoneProduto(slugTeste);

        final novoId =
            await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
          lojaId: lojaId,
          nome: 'Teste',
        );
        expect(novoId, slugTesteSeguro);

        final p = Produto.vazio()
          ..nome = 'Teste'
          ..slug = novoId
          ..idFirebase = novoId
          ..lojaId = lojaId
          ..quantidade = 1
          ..precoFinal = 29.9
          ..precoUnitario = 29.9
          ..updatedAt = DateTime.now();
        await produtosBox.add(p);

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          p,
          lojaId: lojaId,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        await venderTeste(p);

        expect(vendasBox.length, 1);
        expect(
          (await firestore
                  .collection('lojas')
                  .doc(lojaId)
                  .collection(FSPaths.estoqueProdutosCol)
                  .doc(slugTeste)
                  .get())
              .exists,
          isFalse,
        );
        final snapNovo = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(novoId)
            .get();
        expect(snapNovo.exists, isTrue);
        expect((snapNovo.data()?['quantidade'] as num?)?.toInt(), 0);
      },
    );

    test('id tombstonado antigo continua bloqueado na venda', () async {
      await tombstoneProduto(slugTeste);
      final p = produtoTesteLocal(idFirebase: slugTeste);
      await produtosBox.add(p);

      expect(
        () => venderTeste(p),
        throwsA(
          predicate(
            (Object e) =>
                formatDartErrorForUser(e).contains('identificador') ||
                formatDartErrorForUser(e).contains('removido do estoque'),
          ),
        ),
      );
      expect(vendasBox.length, 0);
    });
  });

  group('VendaEstoqueRemotoPrepService', () {
    test('produto só Hive sem tombstone: prep sincroniza e doc passa a existir', () async {
      final p = produtoTesteLocal();
      await produtosBox.add(p);

      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaId,
        produtos: [p],
      );

      expect(
        await VendaEstoqueRemotoPrepService.estoqueDocExisteRemoto(
          lojaId: lojaId,
          produto: p,
        ),
        isTrue,
      );
      expect(p.idFirebase.trim(), slugTeste);
    });

    test('slug tombstonado sem doc remoto: mensagem de identificador excluído', () async {
      await tombstoneProduto(slugTeste);
      final p = produtoTesteLocal();
      await produtosBox.add(p);

      expect(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        throwsA(
          predicate(
            (Object e) {
              final msg = formatDartErrorForUser(e);
              return msg.contains('identificador') &&
                  !msg.contains('removido do estoque');
            },
          ),
        ),
      );
    });

    test('doc remoto + tombstone: prep bloqueia com removido antes do sync', () async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(slugTeste)
          .set({
        'nome': 'Teste antigo',
        'slug': slugTeste,
        'quantidade': 0,
      });
      await tombstoneProduto(slugTeste);

      final p = produtoTesteLocal(idFirebase: slugTeste);
      await produtosBox.add(p);

      expect(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        throwsA(
          predicate(
            (Object e) =>
                formatDartErrorForUser(e).contains('removido do estoque'),
          ),
        ),
      );
    });
  });

  group('registrarVendaMulti — produto recém-criado / pendente', () {
    test(
      'produto local com slug tombstonado (sem cadastro seguro): prep bloqueia venda',
      () async {
        final p = produtoTesteLocal();
        await produtosBox.add(p);

        await tombstoneProduto(slugTeste);

        expect(
          () => venderTeste(p),
          throwsA(
            predicate(
              (Object e) =>
                  !formatDartErrorForUser(e).contains('removido do estoque'),
            ),
          ),
        );

        expect(vendasBox.length, 0);
        final snap = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(slugTeste)
            .get();
        expect(snap.exists, isFalse);
      },
    );

    test('sem tombstone: prep sincroniza e venda conclui', () async {
      final p = produtoTesteLocal();
      await produtosBox.add(p);

      await venderTeste(p);

      expect(vendasBox.length, 1);
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(slugTeste)
          .get();
      expect(snap.exists, isTrue);
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 0);
    });

    test('baixa direta sem prep com tombstone ainda usa mensagem removido (legado)', () async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(slugTeste)
          .set({'nome': 'Teste', 'slug': slugTeste, 'quantidade': 1});
      await tombstoneProduto(slugTeste);

      expect(
        EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: lojaId,
          itens: [
            {
              'productId': slugTeste,
              'slug': slugTeste,
              'nome': 'Teste',
              'quantidade': 1,
            },
          ],
        ),
        throwsA(
          predicate(
            (Object e) =>
                formatDartErrorForUser(e).contains('removido do estoque'),
          ),
        ),
      );
    });
  });
}
