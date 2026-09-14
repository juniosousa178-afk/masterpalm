import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_publish_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/catalogo_web_apos_estoque_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('removerDoCatalogoSeEstoqueZerado', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = db;
    });

    tearDown(() {
      EstoqueTransactionService.debugClearOverrides();
    });

    Future<void> writeLive(String loja, String id, Map<String, dynamic> data) {
      return db.collection('lojas').doc(loja).collection('produtos').doc(id).set(data);
    }

    Future<void> writeDraft(String loja, String id, Map<String, dynamic> data) {
      return db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.draftProdutosCol)
          .doc(id)
          .set(data);
    }

    Future<bool> liveExists(String loja, String id) async {
      return (await db.collection('lojas').doc(loja).collection('produtos').doc(id).get())
          .exists;
    }

    test('slug ausente ainda remove o documento canônico', () async {
      const loja = 'diagnostico';
      await writeLive(loja, 'id-canonico', {
        'id': 'id-canonico',
        'quantidade': 0,
        'ativo': true,
      });
      await writeDraft(loja, 'id-canonico', {
        'id': 'id-canonico',
        'quantidade': 0,
      });

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
        EstoqueTransactionResult(
          produtoId: 'id-canonico',
          produtoNome: 'Peca com variacao',
          produtoSlug: 'slug-antigo-ausente',
          quantidadeDebitada: 1,
          quantidadeTotalAtualizada: 0,
          variacoesAtualizadas: const {},
        ),
      ]);

      expect(await liveExists(loja, 'id-canonico'), isFalse);
      expect(
        (await db
                .collection('lojas')
                .doc(loja)
                .collection(FSPaths.draftProdutosCol)
                .doc('id-canonico')
                .get())
            .exists,
        isFalse,
      );
    });

    test('legado e canônico coexistindo: remove os dois do mesmo produto', () async {
      const loja = 'diagnostico';
      await writeLive(loja, 'id-canonico', {
        'id': 'id-canonico',
        'slug': 'slug-legado',
        'nome': 'Peca',
      });
      await writeLive(loja, 'slug-legado', {
        'id': 'id-canonico',
        'slug': 'slug-legado',
        'nome': 'Peca',
      });
      await writeDraft(loja, 'id-canonico', {'id': 'id-canonico'});
      await writeDraft(loja, 'slug-legado', {
        'id': 'id-canonico',
        'slug': 'slug-legado',
        'nome': 'Peca',
      });

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
        EstoqueTransactionResult(
          produtoId: 'id-canonico',
          produtoNome: 'Peca',
          produtoSlug: 'slug-legado',
          quantidadeDebitada: 1,
          quantidadeTotalAtualizada: 0,
        ),
      ]);

      expect(await liveExists(loja, 'id-canonico'), isFalse);
      expect(await liveExists(loja, 'slug-legado'), isFalse);
    });

    test('não remove documento de outro produto com o mesmo slug textual', () async {
      const loja = 'diagnostico';
      await writeLive(loja, 'id-canonico', {'id': 'id-canonico', 'nome': 'Peca A'});
      await writeLive(loja, 'slug-colisao', {
        'id': 'outro-produto',
        'slug': 'slug-colisao',
        'nome': 'Peca B',
      });

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
        EstoqueTransactionResult(
          produtoId: 'id-canonico',
          produtoNome: 'Peca A',
          produtoSlug: 'slug-colisao',
          quantidadeDebitada: 1,
          quantidadeTotalAtualizada: 0,
        ),
      ]);

      expect(await liveExists(loja, 'id-canonico'), isFalse);
      expect(await liveExists(loja, 'slug-colisao'), isTrue);
    });

    test('última unidade da última variação: remove do catálogo público', () async {
      const loja = 'diagnostico';
      await writeLive(loja, 'prod-var', {'id': 'prod-var', 'nome': 'Anel'});

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
        EstoqueTransactionResult(
          produtoId: 'prod-var',
          produtoNome: 'Anel',
          produtoSlug: 'anel',
          quantidadeDebitada: 1,
          quantidadeTotalAtualizada: 0,
          variacoesAtualizadas: {
            'P': {'Azul': 0},
          },
        ),
      ]);

      expect(await liveExists(loja, 'prod-var'), isFalse);
    });

    test('uma variação zerada e outra disponível: mantém no catálogo', () async {
      const loja = 'diagnostico';
      await writeLive(loja, 'prod-var', {'id': 'prod-var', 'nome': 'Anel'});

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
        EstoqueTransactionResult(
          produtoId: 'prod-var',
          produtoNome: 'Anel',
          produtoSlug: 'anel',
          quantidadeDebitada: 1,
          quantidadeTotalAtualizada: 3,
          variacoesAtualizadas: {
            'P': {'Azul': 0, 'Verde': 3},
          },
        ),
      ]);

      expect(await liveExists(loja, 'prod-var'), isTrue);
    });

    test('não remove o mesmo id de outra loja nem o cadastro de estoque', () async {
      const lojaA = 'loja-a';
      const lojaB = 'loja-b';
      const pid = 'id-compartilhado';
      await writeLive(lojaA, pid, {'id': pid, 'nome': 'Peca'});
      await writeLive(lojaB, pid, {'id': pid, 'nome': 'Peca'});
      await db
          .collection('lojas')
          .doc(lojaA)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'quantidade': 0, 'nome': 'Peca'});

      await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(lojaA, [
        EstoqueTransactionResult(
          produtoId: pid,
          produtoNome: 'Peca',
          produtoSlug: 'peca',
          quantidadeDebitada: 1,
          quantidadeTotalAtualizada: 0,
        ),
      ]);

      expect(await liveExists(lojaA, pid), isFalse);
      expect(await liveExists(lojaB, pid), isTrue);
      expect(
        (await db
                .collection('lojas')
                .doc(lojaA)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(pid)
                .get())
            .data()?['quantidade'],
        0,
      );
    });
  });

  group('processStockFromFirestoreMap / variação esgotada', () {
    test('grade zerada com agregado antigo não entra no catálogo', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'variacoes': {
          'P': {'Azul': 0},
        },
        'estoquePorTamanho': {'P': 0},
        'estoque_atual': 1,
        'quantidade': 0,
      }, isCombo: false);
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
    });

    test('produto simples sem grade usa quantidade', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'quantidade': 7,
        'estoque_atual': 7,
      }, isCombo: false);
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 7);
    });

    test('produto simples zerado sem grade some do catálogo público', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'quantidade': 0,
        'estoque_atual': 0,
      }, isCombo: false);
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
    });

    test('uma variação zerada com outra disponível: mantém e bloqueia a esgotada', () {
      final map = {
        'variacoes': {
          'P': {'Azul': 0, 'Verde': 2},
        },
        'estoquePorTamanho': {'P': 2},
        'estoque_atual': 9,
        'quantidade': 2,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 2);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul'),
        0,
      );
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Verde'),
        2,
      );
    });

    test('somente tamanho: grade zerada ignora agregado', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'estoquePorTamanho': {'M': 0, 'G': 0},
        'estoque_atual': 4,
        'quantidade': 0,
      }, isCombo: false);
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
    });

    test('somente cor: grade positiva entra no catálogo', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'variacoes': {
          'sem-tamanho': {'Rosa': 3},
        },
        'estoque_atual': 99,
      }, isCombo: false);
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 3);
    });

    test('tamanho + cor + extra: soma só células positivas', () {
      final map = {
        'variacoes': {
          'P': {
            'Azul': {'G': 0, 'GG': 1},
          },
        },
        'estoque_atual': 8,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 1);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul', 'G'),
        0,
      );
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul', 'GG'),
        1,
      );
    });

    test('combo com grade zerada não usa agregado antigo', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'tipoProduto': 'combo',
        'itensCombo': [
          {'productId': 'a', 'quantidade': 1},
        ],
        'variacoes': {
          'kit': {'unico': 0},
        },
        'estoque_atual': 5,
        'quantidade': 0,
      }, isCombo: true);
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
    });

    test('variacoes vazia {} é grade esvaziada e ignora agregado', () {
      final map = {
        // Atributo persistido distingue grade esvaziada de produto sem variação.
        'tamanhos': ['P'],
        'variacoes': <String, dynamic>{},
        'estoquePorTamanho': <String, int>{},
        'estoque_atual': 5,
        'quantidade': 5,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul'),
        0,
      );
    });

    test('estoquePorTamanho vazio {} em produto simples usa quantidade', () {
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap({
        'estoquePorTamanho': <String, int>{},
        'quantidade': 7,
        'estoque_atual': 7,
      }, isCombo: false);
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 7);
    });

    test('grade canônica zerada não herda estoquePorTamanho agregado', () {
      final map = {
        'variacoes': {
          'P': {'Azul': 0},
        },
        'estoquePorTamanho': {'P': 1},
        'quantidade': 0,
        'estoque_atual': 1,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul'),
        0,
      );
    });

    test('grade canônica zerada não herda estoquePorCor agregado', () {
      final map = {
        'variacoes': {
          'sem-tamanho': {'Rosa': 0},
        },
        'estoquePorCor': {'Rosa': 2},
        'quantidade': 0,
        'estoque_atual': 2,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, '', 'Rosa'),
        0,
      );
    });

    test('variacoes vazia não herda agregados de tamanho/cor', () {
      final map = {
        'variacoes': <String, dynamic>{},
        'estoquePorTamanho': {'P': 1},
        'estoquePorCor': {'Rosa': 2},
        'quantidade': 0,
        'estoque_atual': 3,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isFalse);
      expect(result.quantidadeTotal, 0);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul'),
        0,
      );
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, '', 'Rosa'),
        0,
      );
    });

    test('somente tamanho sem variacoes usa estoquePorTamanho legítimo', () {
      final map = {
        'estoquePorTamanho': {'M': 2, 'G': 1},
        'quantidade': 3,
        'estoque_atual': 3,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 3);
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'M', ''), 2);
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'G', ''), 1);
    });

    test('somente cor sem variacoes usa estoquePorCor legítimo', () {
      final map = {
        'estoquePorCor': {'Rosa': 4},
        'quantidade': 4,
        'estoque_atual': 4,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 4);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, '', 'Rosa'),
        4,
      );
    });

    test('cor extra fora da grade canônica permanece disponível', () {
      final map = {
        'variacoes': {
          'P': {'Azul': 0},
        },
        'estoquePorCor': {'Rosa': 2},
        'quantidade': 0,
        'estoque_atual': 2,
      };
      final result = CatalogEstoqueHelper.processStockFromFirestoreMap(
        map,
        isCombo: false,
      );
      expect(result.incluirNoCatalogo, isTrue);
      expect(result.quantidadeTotal, 2);
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, 'P', 'Azul'),
        0,
      );
      expect(
        CatalogEstoqueHelper.estoqueDisponivelVariacao(map, '', 'Rosa'),
        2,
      );
    });
  });

  group('recuperação pós-falha do sync de catálogo', () {
    late Directory hiveDir;
    late Box<Produto> produtosBox;
    late FakeFirebaseFirestore db;

    setUpAll(() async {
      hiveDir = await Directory.systemTemp.createTemp('hive_cat_zero_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = db;
      CatalogoSyncService.debugFirestoreOverride = db;
      CatalogPublishService.debugFirestoreOverride = db;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      ProdutoExclusaoTombstoneService.debugFirestoreOverride = db;
      produtosBox = await Hive.openBox<Produto>(
        HiveBoxNames.produtos('loja-rec-${DateTime.now().microsecondsSinceEpoch}'),
      );
      CatalogoWebAposEstoqueService.debugClearOverrides();
    });

    tearDown(() async {
      CatalogoWebAposEstoqueService.debugClearOverrides();
      EstoqueTransactionService.debugClearOverrides();
      CatalogoSyncService.debugFirestoreOverride = null;
      CatalogoSyncService.debugFailLegacySlugDelete = null;
      CatalogPublishService.debugFirestoreOverride = null;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      if (produtosBox.isOpen) {
        await produtosBox.clear();
        await produtosBox.close();
      }
      if (Hive.isBoxOpen(HiveBoxNames.config())) {
        await Hive.box(HiveBoxNames.config()).clear();
      }
    });

    test('falha no sync marca catálogo para atualizar e não baixa estoque de novo', () async {
      const loja = 'loja-rec';
      const pid = 'prod-rec';
      await db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({
        'nome': 'Peca',
        'quantidade': 0,
        'variacoes': {
          'P': {'Azul': 0},
        },
      });

      await produtosBox.add(
        Produto(
          nome: 'Peca',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 10,
          precoFinal: 10,
          quantidade: 0,
          precoUnitario: 10,
          categoria: '',
          dataEntrada: DateTime(2026, 1, 1),
          idFirebase: pid,
          lojaId: loja,
          publicadoNoCatalogo: true,
          slug: 'peca',
        ),
      );

      var syncAttempts = 0;
      CatalogoWebAposEstoqueService.debugBeforeProductSync = (id) async {
        syncAttempts++;
        throw StateError('sync catalogo indisponivel');
      };

      await CatalogoWebAposEstoqueService.sincronizarAposResultadosTransacao(
        lojaId: loja,
        produtosBox: produtosBox,
        resultadosPrincipais: [
          EstoqueTransactionResult(
            produtoId: pid,
            produtoNome: 'Peca',
            produtoSlug: 'peca',
            quantidadeDebitada: 1,
            quantidadeTotalAtualizada: 0,
          ),
        ],
      );

      expect(syncAttempts, 1);
      expect(await CatalogPublishService.catalogoPrecisaAtualizar, isTrue);
      final pendentes = await CatalogPublishService.lerPendenciasSyncAposEstoque();
      expect(pendentes[loja], contains(pid));

      final estoqueSnap = await db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect(estoqueSnap.data()?['quantidade'], 0);
      expect(estoqueSnap.data()?['variacoes'], {
        'P': {'Azul': 0},
      });
    });

    test('pendência de IDs sobrevive a reabrir a box config', () async {
      const loja = 'loja-rec';
      await CatalogPublishService.registrarPendenciaSyncAposEstoque(
        lojaId: loja,
        productIds: const ['prod-rec'],
      );
      if (Hive.isBoxOpen(HiveBoxNames.config())) {
        await Hive.box(HiveBoxNames.config()).close();
      }
      final relida = await CatalogPublishService.lerPendenciasSyncAposEstoque();
      expect(relida[loja], contains('prod-rec'));
      expect(await CatalogPublishService.catalogoPrecisaAtualizar, isTrue);
    });

    test('recuperação limpa pendência só após sucesso e não debita estoque', () async {
      const loja = 'loja-rec';
      const pid = 'prod-rec';
      await db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({
        'nome': 'Peca',
        'quantidade': 0,
        'variacoes': {
          'P': {'Azul': 0},
        },
      });
      await produtosBox.add(
        Produto(
          nome: 'Peca',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 10,
          precoFinal: 10,
          quantidade: 0,
          precoUnitario: 10,
          categoria: '',
          dataEntrada: DateTime(2026, 1, 1),
          idFirebase: pid,
          lojaId: loja,
          publicadoNoCatalogo: true,
          slug: 'peca',
        ),
      );

      await CatalogPublishService.registrarPendenciaSyncAposEstoque(
        lojaId: loja,
        productIds: const [pid],
      );

      var syncAttempts = 0;
      CatalogoWebAposEstoqueService.debugBeforeProductSync = (id) async {
        syncAttempts++;
      };

      await CatalogoWebAposEstoqueService.tentarRecuperarPendencias(
        lojaId: loja,
        produtosBox: produtosBox,
      );

      expect(syncAttempts, 1);
      final restantes = await CatalogPublishService.lerPendenciasSyncAposEstoque();
      expect(restantes[loja] ?? const <String>{}, isEmpty);
      expect(
        (await db
                .collection('lojas')
                .doc(loja)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(pid)
                .get())
            .data()?['quantidade'],
        0,
      );
    });

    test(
      'falha na exclusão do slug live: recuperação remove a cópia e só então limpa pendência',
      () async {
        const loja = 'loja-rec';
        const lojaB = 'loja-outra';
        const pid = 'id-canonico';
        const slug = 'slug-legado';
        const outro = 'outro-produto';

        Future<void> writeLiveAt(String li, String id, Map<String, dynamic> data) {
          return db.collection('lojas').doc(li).collection('produtos').doc(id).set(data);
        }

        await writeLiveAt(loja, pid, {
          'id': pid,
          'slug': slug,
          'nome': 'Peca',
        });
        await writeLiveAt(loja, slug, {
          'id': pid,
          'slug': slug,
          'nome': 'Peca',
        });
        await writeLiveAt(loja, outro, {
          'id': outro,
          'slug': 'peca-outra',
          'nome': 'Outra',
        });
        await writeLiveAt(lojaB, slug, {
          'id': pid,
          'slug': slug,
          'nome': 'Peca',
        });
        await db
            .collection('lojas')
            .doc(loja)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(pid)
            .set({
          'nome': 'Peca',
          'quantidade': 0,
          'slug': slug,
        });
        await produtosBox.add(
          Produto(
            nome: 'Peca',
            custoReal: 1,
            frete: 0,
            gastosFixos: 0,
            gastosVariaveis: 0,
            precoSugerido: 10,
            precoFinal: 10,
            quantidade: 0,
            precoUnitario: 10,
            categoria: '',
            dataEntrada: DateTime(2026, 1, 1),
            idFirebase: pid,
            lojaId: loja,
            publicadoNoCatalogo: true,
            slug: slug,
          ),
        );

        EstoqueTransactionService.debugFailCatalogDelete =
            (col, docId) => col == 'produtos' && docId == slug;

        await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
          EstoqueTransactionResult(
            produtoId: pid,
            produtoNome: 'Peca',
            produtoSlug: slug,
            quantidadeDebitada: 1,
            quantidadeTotalAtualizada: 0,
          ),
        ]);

        expect(
          (await db.collection('lojas').doc(loja).collection('produtos').doc(pid).get())
              .exists,
          isFalse,
        );
        expect(
          (await db.collection('lojas').doc(loja).collection('produtos').doc(slug).get())
              .exists,
          isTrue,
          reason: 'cópia pública legada sobreviveu à falha de exclusão',
        );
        expect(
          (await CatalogPublishService.lerPendenciasSyncAposEstoque())[loja],
          contains(pid),
        );
        expect(
          (await db
                  .collection('lojas')
                  .doc(loja)
                  .collection(FSPaths.estoqueProdutosCol)
                  .doc(pid)
                  .get())
              .data()?['quantidade'],
          0,
        );

        EstoqueTransactionService.debugFailCatalogDelete = null;

        await CatalogoWebAposEstoqueService.tentarRecuperarPendencias(
          lojaId: loja,
          produtosBox: produtosBox,
        );

        expect(
          (await db.collection('lojas').doc(loja).collection('produtos').doc(slug).get())
              .exists,
          isFalse,
          reason: 'recuperação deve apagar a cópia pública do slug do mesmo produto',
        );
        expect(
          (await db.collection('lojas').doc(loja).collection('produtos').doc(pid).get())
              .exists,
          isFalse,
        );
        expect(
          (await db.collection('lojas').doc(loja).collection('produtos').doc(outro).get())
              .exists,
          isTrue,
        );
        expect(
          (await db.collection('lojas').doc(lojaB).collection('produtos').doc(slug).get())
              .exists,
          isTrue,
        );
        expect(
          (await CatalogPublishService.lerPendenciasSyncAposEstoque())[loja] ??
              const <String>{},
          isEmpty,
        );
        expect(
          (await db
                  .collection('lojas')
                  .doc(loja)
                  .collection(FSPaths.estoqueProdutosCol)
                  .doc(pid)
                  .get())
              .data()?['quantidade'],
          0,
          reason: 'recuperação não debita estoque de novo',
        );
        expect(produtosBox.values.first.quantidade, 0);
      },
    );

    test('falha ao limpar slug na recuperação mantém pendência e não debita', () async {
      const loja = 'loja-rec';
      const pid = 'id-canonico';
      const slug = 'slug-legado';
      await db.collection('lojas').doc(loja).collection('produtos').doc(slug).set({
        'id': pid,
        'slug': slug,
        'nome': 'Peca',
      });
      await db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({'nome': 'Peca', 'quantidade': 0, 'slug': slug});
      await produtosBox.add(
        Produto(
          nome: 'Peca',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 10,
          precoFinal: 10,
          quantidade: 0,
          precoUnitario: 10,
          categoria: '',
          dataEntrada: DateTime(2026, 1, 1),
          idFirebase: pid,
          lojaId: loja,
          publicadoNoCatalogo: true,
          slug: slug,
        ),
      );
      await CatalogPublishService.registrarPendenciaSyncAposEstoque(
        lojaId: loja,
        productIds: const [pid],
      );
      CatalogoSyncService.debugFailLegacySlugDelete =
          (col, docId) => col == 'produtos' && docId == slug;

      await CatalogoWebAposEstoqueService.tentarRecuperarPendencias(
        lojaId: loja,
        produtosBox: produtosBox,
      );

      expect(
        (await db.collection('lojas').doc(loja).collection('produtos').doc(slug).get())
            .exists,
        isTrue,
      );
      expect(
        (await CatalogPublishService.lerPendenciasSyncAposEstoque())[loja],
        contains(pid),
      );
      expect(
        (await db
                .collection('lojas')
                .doc(loja)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(pid)
                .get())
            .data()?['quantidade'],
        0,
      );
    });

    test('falha ao ler pendências no Hive não propaga e mantém a pendência', () async {
      const loja = 'loja-rec';
      await CatalogPublishService.registrarPendenciaSyncAposEstoque(
        lojaId: loja,
        productIds: const ['prod-rec'],
      );
      CatalogoWebAposEstoqueService.debugBeforeLerPendencias = () async {
        throw StateError('hive config indisponivel');
      };

      await expectLater(
        CatalogoWebAposEstoqueService.tentarRecuperarPendencias(
          lojaId: loja,
          produtosBox: produtosBox,
        ),
        completes,
      );

      expect(
        (await CatalogPublishService.lerPendenciasSyncAposEstoque())[loja],
        contains('prod-rec'),
      );
    });
  });
}
