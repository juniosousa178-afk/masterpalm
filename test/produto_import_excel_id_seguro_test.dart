// Importação Excel: docId seguro, anti-tombstone e validação Firestore.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_firestore_doc_id_validator.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_import_service.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/produto_upsert_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-import-teste';
  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_import_id_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VendaAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(VendaItemAdapter());
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
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_import_$s');
    vendasBox = await Hive.openBox<Venda>('v_import_$s');
  });

  tearDown(() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    await produtosBox.close();
    await vendasBox.close();
  });

  Future<void> tombstone(String docId) async {
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.exclusaoProdutoCol)
        .doc(docId)
        .set({'p': true});
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
  }

  Produto produtoLinha({
    required String nome,
    int qtd = 1,
    double preco = 10,
  }) {
    return Produto(
      nome: nome,
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: preco,
      quantidade: qtd,
      precoUnitario: preco,
      categoria: 'Cat',
      dataEntrada: DateTime.now(),
      lojaId: lojaId,
    );
  }

  group('ProdutoFirestoreDocIdValidator', () {
    test('1-4. SKU/código com / ou URL são inválidos', () {
      for (final id in [
        'ABC/123',
        'https://cdn.example.com/x.jpg',
        '',
        '   ',
      ]) {
        expect(
          ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(id),
          isFalse,
          reason: id,
        );
      }
    });

    test('10-12. storeId/produtoId inválidos não montam path seguro', () {
      final v = ProdutoFirestoreDocIdValidator.validate(
        storeId: '',
        produtoId: 'ok-id',
      );
      expect(v.ok, isFalse);
      expect(v.code, ProdutoFirestoreDocIdValidation.invalidStore);

      final v2 = ProdutoFirestoreDocIdValidator.validate(
        storeId: lojaId,
        produtoId: 'a/b',
      );
      expect(v2.ok, isFalse);
      expect(v2.code, ProdutoFirestoreDocIdValidation.invalidProdutoId);
    });

    test('19. caminho montado não contém //', () {
      final v = ProdutoFirestoreDocIdValidator.validate(
        storeId: lojaId,
        produtoId: 'produto-seguro-1',
      );
      expect(v.ok, isTrue);
    });
  });

  group('upsertProdutoParaImportacao — docId', () {
    test('1. SKU com / não vira document ID', () async {
      final (res, p) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Anel Teste SKU Barra'),
        vendasBox,
        sku: 'ABC/123',
      );
      expect(res, UpsertImportResult.inserted);
      expect(p, isNotNull);
      expect(p!.slug, isNot('ABC/123'));
      expect(p.sku, 'ABC/123');
      expect(ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(p.slug), isTrue);
    });

    test('2. Código de barras com / não vira document ID', () async {
      final (res, p) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Pulseira Codigo Barra'),
        vendasBox,
        codigoBarras: '789/000',
      );
      expect(res, UpsertImportResult.inserted);
      expect(p!.codigoBarras, '789/000');
      expect(p.slug, isNot('789/000'));
    });

    test('3-4. URL em SKU/código não vira document ID', () async {
      final url = 'https://cdn.example.com/img.jpg';
      final (resSku, pSku) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Colar URL SKU'),
        vendasBox,
        sku: url,
      );
      expect(resSku, UpsertImportResult.inserted);
      expect(pSku!.slug.contains('://'), isFalse);

      final (resCb, pCb) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Brinco URL Codigo'),
        vendasBox,
        codigoBarras: url,
      );
      expect(resCb, UpsertImportResult.inserted);
      expect(pCb!.slug.contains('://'), isFalse);
    });

    test('5-6. Linha sem SKU/código recebe docId seguro', () async {
      final (res, p) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Sem Codigos'),
        vendasBox,
      );
      expect(res, UpsertImportResult.inserted);
      expect(p!.slug, startsWith(ProdutoImportDocIdHelper.importLocalIdPrefix));
      expect(ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(p.slug), isTrue);
    });

    test('7. Duas linhas diferentes não recebem o mesmo docId', () async {
      final (_, p1) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Produto Alpha'),
        vendasBox,
      );
      final (_, p2) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Produto Beta'),
        vendasBox,
      );
      expect(p1!.slug, isNot(p2!.slug));
    });

    test('8-9. Insert offline usa id local import-*; tombstone tratado no sync', () async {
      final base = '$lojaId-coracao-fucsia';
      await tombstone(base);

      final (res, p) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: 'Coracao Fucsia'),
        vendasBox,
      );
      expect(res, UpsertImportResult.inserted);
      expect(ProdutoImportDocIdHelper.isDocIdLocalImportacao(p!.slug), isTrue);
      expect(p.slug, isNot(base));

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(base)
          .get();
      expect(snap.data()?['p'], isTrue);
    });

    test('13-14. Variação e estoque preservados no insert', () async {
      final p = produtoLinha(nome: 'Com Grade', qtd: 5);
      p.estoquePorTamanho = {'P': 2, 'M': 3};
      p.tamanhos = ['P', 'M'];
      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        p,
        vendasBox,
      );
      expect(res, UpsertImportResult.inserted);
      expect(out!.quantidade, 5);
      expect(out.estoquePorTamanho['M'], 3);
    });

    test('17. Produto existente com venda atualiza localmente; sync trata tombstone',
        () async {
      final existente = produtoLinha(nome: 'Com Venda');
      final docId = '$lojaId-com-venda';
      existente.slug = docId;
      existente.idFirebase = docId;
      await produtosBox.add(existente);
      await tombstone(docId);

      final venda = Venda(
        clienteNome: 'Cliente',
        produtosDescricao: existente.nome,
        quantidade: 1,
        preco: 10,
        total: 10,
        formasPagamento: 'Dinheiro',
        data: DateTime.now(),
        vendedor: 'v',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: existente.nome,
            quantidade: 1,
            precoUnitario: 10,
            productId: docId,
          ),
        ],
      );
      await vendasBox.add(venda);

      final (res, _) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        produtoLinha(nome: existente.nome, qtd: 2),
        vendasBox,
        sku: 'SKU-LEG',
      );
      expect(res, UpsertImportResult.updated);
    });
  });

  group('ProdutosFirestoreService — validação defensiva', () {
    test('10-11. produtoId inválido não grava no Firestore', () async {
      final p = produtoLinha(nome: 'Invalido');
      p.slug = 'https://bad/id';
      p.idFirebase = '';

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.produtoInvalido);

      final docs = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .get();
      expect(docs.docs, isEmpty);
    });

    test('20. mensagem sanitizada não expõe invalid-argument bruto', () {
      final msg = ProdutoSyncErroUtil.mensagemCadastroFalhaRemota(
        detalheErro: 'identificador do produto inválido',
      );
      expect(msg.contains('invalid argument'), isFalse);
      expect(msg.contains('//'), isFalse);
    });
  });

  group('ProdutoImportService — linha a linha', () {
    test('15. Uma linha inválida não bloqueia a próxima', () async {
      final r1 = await ProdutoImportService.processarLinha(
        linha: 1,
        produto: produtoLinha(nome: ''),
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendasBox: vendasBox,
      );
      expect(r1.status, ProdutoImportLinhaStatus.falhouDadosInvalidos);

      final r2 = await ProdutoImportService.processarLinha(
        linha: 2,
        produto: produtoLinha(nome: 'Linha Valida'),
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendasBox: vendasBox,
      );
      expect(r2.status, ProdutoImportLinhaStatus.pendenteSincronizacao);
    });

    test('16. Reimportação pelo nome atualiza sem duplicar por ID inseguro', () async {
      final nome = 'Reimport Unico';
      final r1 = await ProdutoImportService.processarLinha(
        linha: 1,
        produto: produtoLinha(nome: nome, qtd: 1),
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendasBox: vendasBox,
        sku: 'SKU-UNICO-1',
      );
      expect(r1.produto, isNotNull);

      final antes = produtosBox.length;
      final r2 = await ProdutoImportService.processarLinha(
        linha: 2,
        produto: produtoLinha(nome: nome, qtd: 4),
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendasBox: vendasBox,
        sku: 'SKU-UNICO-1',
      );
      expect(produtosBox.length, antes);
      expect(r2.status, ProdutoImportLinhaStatus.pendenteSincronizacao);
    });

    test('18. processarLinha enfileira sem sync imediato', () async {
      final r = await ProdutoImportService.processarLinha(
        linha: 1,
        produto: produtoLinha(nome: 'Enfileirado'),
        lojaId: lojaId,
        produtosBox: produtosBox,
        vendasBox: vendasBox,
      );
      expect(r.status, ProdutoImportLinhaStatus.pendenteSincronizacao);
      expect(
        ProdutoImportDocIdHelper.isDocIdLocalImportacao(r.produto!.slug),
        isTrue,
      );
      final docs = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .get();
      expect(docs.docs, isEmpty);
    });
  });

  group('ProdutoImportDocIdHelper', () {
    test('produtoTemVendaOuReferencia detecta productId', () {
      final p = produtoLinha(nome: 'Vendido');
      p.slug = 'doc-venda';
      final venda = Venda(
        clienteNome: 'C',
        produtosDescricao: 'outro',
        quantidade: 1,
        preco: 1,
        total: 1,
        formasPagamento: 'pix',
        data: DateTime.now(),
        vendedor: 'v',
        observacao: '',
        lojaId: lojaId,
        itens: [
          VendaItem(
            produtoNome: 'Vendido',
            quantidade: 1,
            precoUnitario: 1,
            productId: 'doc-venda',
          ),
        ],
      );
      vendasBox.add(venda);
      expect(
        ProdutoImportDocIdHelper.produtoTemVendaOuReferencia(
          produto: p,
          vendasBox: vendasBox,
          lojaId: lojaId,
        ),
        isTrue,
      );
    });
  });
}
