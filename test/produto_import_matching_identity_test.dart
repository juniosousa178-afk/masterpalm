// Contrato de matching na importação: SKU/código têm prioridade sobre nome.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_estoque_doc_id_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produto_upsert_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-matching-teste';
  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_matching_');
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
    produtosBox = await Hive.openBox<Produto>('p_match_$s');
    vendasBox = await Hive.openBox<Venda>('v_match_$s');
  });

  tearDown(() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
    await produtosBox.close();
    await vendasBox.close();
  });

  Produto base({
    required String nome,
    String categoria = 'Joias',
    int qtd = 1,
  }) {
    return Produto(
      nome: nome,
      custoReal: 0,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 10,
      quantidade: qtd,
      precoUnitario: 10,
      categoria: categoria,
      dataEntrada: DateTime.now(),
      lojaId: lojaId,
    );
  }

  Future<Produto> inserirExistente({
    required String nome,
    String categoria = 'Joias',
    String sku = '',
    String codigoBarras = '',
    String? docId,
  }) async {
    final p = base(nome: nome, categoria: categoria);
    if (sku.isNotEmpty) p.sku = sku;
    if (codigoBarras.isNotEmpty) p.codigoBarras = codigoBarras;
    final id = docId ??
        await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
          lojaId: lojaId,
          nome: nome,
        );
    p.slug = id;
    p.idFirebase = id;
    await produtosBox.add(p);
    await p.save();
    return p;
  }

  group('matching — prioridade e anti-merge indevido', () {
    test('A. Mesmo nome+categoria + SKU diferente → não atualiza existente', () async {
      final existente = await inserirExistente(
        nome: 'Pulseira Dupla',
        sku: 'SKU-AAA',
      );
      final skuAntes = existente.sku;
      final qtdAntes = existente.quantidade;

      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        base(nome: 'Pulseira Dupla', qtd: 99),
        vendasBox,
        sku: 'SKU-BBB',
      );

      expect(res, UpsertImportResult.skippedConflict);
      expect(out, isNull);
      expect(produtosBox.length, 1);
      expect(existente.sku, skuAntes);
      expect(existente.quantidade, qtdAntes);
    });

    test('B. Mesmo nome+categoria + código diferente → não atualiza existente', () async {
      final existente = await inserirExistente(
        nome: 'Colar Perola',
        codigoBarras: '111111',
      );
      final barrasAntes = existente.codigoBarras;

      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        base(nome: 'Colar Perola', qtd: 50),
        vendasBox,
        codigoBarras: '222222',
      );

      expect(res, UpsertImportResult.skippedConflict);
      expect(out, isNull);
      expect(produtosBox.length, 1);
      expect(existente.codigoBarras, barrasAntes);
    });

    test('C. Mesmo SKU → atualiza produto correto', () async {
      final existente = await inserirExistente(
        nome: 'Brinco Lua',
        sku: 'SKU-LUA-1',
      );

      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        base(nome: 'Brinco Lua Renomeado Ignorado', qtd: 5),
        vendasBox,
        sku: 'SKU-LUA-1',
      );

      expect(res, UpsertImportResult.updated);
      expect(out, same(existente));
      expect(existente.quantidade, 5);
      expect(produtosBox.length, 1);
    });

    test('D. Mesmo código de barras → atualiza produto correto', () async {
      final existente = await inserirExistente(
        nome: 'Anel Sol',
        codigoBarras: '789000111',
      );

      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        base(nome: 'Outro Nome', qtd: 8),
        vendasBox,
        codigoBarras: '789000111',
      );

      expect(res, UpsertImportResult.updated);
      expect(out, same(existente));
      expect(existente.quantidade, 8);
    });

    test('E. SKU e código vazios → fallback nome+categoria atualiza', () async {
      final existente = await inserirExistente(
        nome: 'Pingente Estrela',
        categoria: 'Colares',
      );

      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        base(nome: 'Pingente Estrela', categoria: 'Colares', qtd: 3),
        vendasBox,
      );

      expect(res, UpsertImportResult.updated);
      expect(out, same(existente));
      expect(existente.quantidade, 3);
      expect(produtosBox.length, 1);
    });

    test('F. Produto existente com venda atualiza localmente no import', () async {
      final docId =
          await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
        lojaId: lojaId,
        nome: 'Com Venda Ref',
      );
      final existente = await inserirExistente(
        nome: 'Com Venda Ref',
        docId: docId,
      );

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(docId)
          .set({'p': true});
      await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);

      await vendasBox.add(
        Venda(
          clienteNome: 'Cliente',
          produtosDescricao: existente.nome,
          quantidade: 1,
          preco: 10,
          total: 10,
          formasPagamento: 'pix',
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
        ),
      );

      final slugAntes = existente.slug;
      final (res, out) = await upsertProdutoParaImportacao(
        produtosBox,
        lojaId,
        base(nome: existente.nome, qtd: 2),
        vendasBox,
        sku: 'SKU-NOVO',
      );

      expect(res, UpsertImportResult.updated);
      expect(out, same(existente));
      expect(existente.slug, slugAntes);
    });
  });
}
