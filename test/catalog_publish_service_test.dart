import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_publish_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CatalogPublishService', () {
    late FakeFirebaseFirestore firestore;

    const lojaId = 'nathy-pratas-e-folheados';
    const productZero = 'nathy-pratas-e-folheados-brinco-3-cora-o';
    const productTwo = 'nathy-pratas-e-folheados-colar-cora-o-cravejado';
    const fallbackOnlyDraft = 'produto-sem-estoque-canonico';

    Future<void> writeDraft(
      String productId, {
      required String nome,
      required int quantidade,
      Map<String, dynamic>? extra,
    }) async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('draft_produtos')
          .doc(productId)
          .set({
        'id': productId,
        'nome': nome,
        'slug': productId,
        'descricao': 'Produto de teste',
        'publicar': true,
        'publicadoNoCatalogo': true,
        'ativo': true,
        'preco': 10.0,
        'preco_venda': 10.0,
        'precoFinal': 10.0,
        'quantidade': quantidade,
        'estoque': quantidade,
        'estoque_atual': quantidade,
        'qtdEstoque': quantidade,
        ...?extra,
      });
    }

    Future<void> writeEstoque(
      String productId, {
      required String nome,
      required int quantidade,
      Map<String, dynamic>? extra,
    }) async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(productId)
          .set({
        'id': productId,
        'nome': nome,
        'slug': productId,
        'quantidade': quantidade,
        ...?extra,
      });
    }

    Future<Map<String, dynamic>?> readLive(String productId) async {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .doc(productId)
          .get();
      return snap.data();
    }

    Future<Map<String, dynamic>?> readEstoque(String productId) async {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(productId)
          .get();
      return snap.data();
    }

    Future<void> seedPublishEverythingPrereqs() async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('draft_config')
          .doc('config')
          .set({
        'nome': 'Nathy Pratas e Folheados',
        'publishedFrom': 'draft',
      });
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('draft_config')
          .doc('payments')
          .set({
        'defaultGateway': 'pix',
        'pix': {'enabled': true},
      });
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      CatalogPublishService.debugFirestoreOverride = firestore;
      CatalogPublishService.debugSyncPaymentsPublicOverride =
          (_) async {};
    });

    tearDown(() {
      CatalogPublishService.debugFirestoreOverride = null;
      CatalogPublishService.debugSyncPaymentsPublicOverride = null;
    });

    test(
      'promoteAll usa estoque canônico e não ressuscita item zerado do draft',
      () async {
        await writeDraft(
          productZero,
          nome: 'Brinco 3 Coração',
          quantidade: 1,
          extra: {
            'variacoes': {
              'sem-tamanho': {'prata': 1},
            },
          },
        );
        await writeDraft(
          productTwo,
          nome: 'Colar Coração Cravejado',
          quantidade: 5,
        );

        await writeEstoque(
          productZero,
          nome: 'Brinco 3 Coração',
          quantidade: 0,
          extra: {
            'variacoes': <String, dynamic>{},
            'estoquePorTamanho': <String, dynamic>{},
          },
        );
        await writeEstoque(
          productTwo,
          nome: 'Colar Coração Cravejado',
          quantidade: 2,
        );

        // Garante que um live antigo é removido quando o estoque canônico zerou.
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('produtos')
            .doc(productZero)
            .set({
          'quantidade': 99,
          'estoque': 99,
          'estoque_atual': 99,
          'qtdEstoque': 99,
          'ativo': true,
        });

        await CatalogPublishService.promoteAll(lojaIdOverride: lojaId);

        final liveZero = await readLive(productZero);
        final liveTwo = await readLive(productTwo);
        final estoqueZero = await readEstoque(productZero);
        final estoqueTwo = await readEstoque(productTwo);

        expect(
          liveZero,
          isNull,
          reason: 'produto zerado no estoque canônico não deve reaparecer no live',
        );

        expect(liveTwo, isNotNull);
        expect(liveTwo!['quantidade'], 2);
        expect(liveTwo['estoque'], 2);
        expect(liveTwo['estoque_atual'], 2);
        expect(liveTwo['qtdEstoque'], 2);

        expect(estoqueZero, isNotNull);
        expect(estoqueZero!['quantidade'], 0);
        expect(estoqueTwo, isNotNull);
        expect(estoqueTwo!['quantidade'], 2);
      },
    );

    test(
      'promoteOne preserva o comportamento atual quando estoque canônico não existe',
      () async {
        await writeDraft(
          fallbackOnlyDraft,
          nome: 'Produto Só no Draft',
          quantidade: 5,
        );

        await CatalogPublishService.promoteOne(
          fallbackOnlyDraft,
          lojaIdOverride: lojaId,
        );

        final live = await readLive(fallbackOnlyDraft);
        final estoque = await readEstoque(fallbackOnlyDraft);

        expect(live, isNotNull);
        expect(live!['quantidade'], 5);
        expect(live['estoque'], 5);
        expect(live['estoque_atual'], 5);
        expect(live['qtdEstoque'], 5);
        expect(estoque, isNull);
      },
    );

    test(
      'publishEverything usa estoque canônico e não republica estoque antigo do draft',
      () async {
        await seedPublishEverythingPrereqs();

        await writeDraft(
          productZero,
          nome: 'Brinco 3 Coração',
          quantidade: 1,
          extra: {
            'variacoes': {
              'sem-tamanho': {'prata': 1},
            },
          },
        );
        await writeDraft(
          productTwo,
          nome: 'Colar Coração Cravejado',
          quantidade: 5,
        );

        await writeEstoque(
          productZero,
          nome: 'Brinco 3 Coração',
          quantidade: 0,
          extra: {
            'variacoes': <String, dynamic>{},
            'estoquePorTamanho': <String, dynamic>{},
          },
        );
        await writeEstoque(
          productTwo,
          nome: 'Colar Coração Cravejado',
          quantidade: 2,
        );

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('produtos')
            .doc(productZero)
            .set({
          'quantidade': 1,
          'estoque': 1,
          'estoque_atual': 1,
          'qtdEstoque': 1,
          'ativo': true,
        });

        final result = await CatalogPublishService.publishEverything(
          lojaIdOverride: lojaId,
        );

        final liveZero = await readLive(productZero);
        final liveTwo = await readLive(productTwo);
        final estoqueZero = await readEstoque(productZero);
        final estoqueTwo = await readEstoque(productTwo);

        expect(result['success'], isTrue);
        expect(result['config'], isTrue);
        expect(result['payments'], isTrue);
        expect(result['products'], 1);

        expect(
          liveZero == null ||
              (liveZero['quantidade'] == 0 &&
                  liveZero['estoque'] == 0 &&
                  liveZero['estoque_atual'] == 0 &&
                  liveZero['qtdEstoque'] == 0),
          isTrue,
          reason:
              'produto zerado no estoque canônico não pode voltar ao catálogo com quantidade 1',
        );

        expect(liveTwo, isNotNull);
        expect(liveTwo!['quantidade'], 2);
        expect(liveTwo['estoque'], 2);
        expect(liveTwo['estoque_atual'], 2);
        expect(liveTwo['qtdEstoque'], 2);

        expect(estoqueZero, isNotNull);
        expect(estoqueZero!['quantidade'], 0);
        expect(estoqueTwo, isNotNull);
        expect(estoqueTwo!['quantidade'], 2);
      },
    );

    test(
      'publishEverything preserva fallback quando estoque canônico não existe',
      () async {
        await seedPublishEverythingPrereqs();
        await writeDraft(
          fallbackOnlyDraft,
          nome: 'Produto Só no Draft',
          quantidade: 5,
        );

        final result = await CatalogPublishService.publishEverything(
          lojaIdOverride: lojaId,
        );

        final live = await readLive(fallbackOnlyDraft);
        final estoque = await readEstoque(fallbackOnlyDraft);

        expect(result['success'], isTrue);
        expect(result['products'], 1);
        expect(live, isNotNull);
        expect(live!['quantidade'], 5);
        expect(live['estoque'], 5);
        expect(live['estoque_atual'], 5);
        expect(live['qtdEstoque'], 5);
        expect(estoque, isNull);
      },
    );
  });
}
