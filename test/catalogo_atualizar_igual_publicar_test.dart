import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_publish_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Atualizar catálogo = Publicar catálogo (fluxo canônico)', () {
    late FakeFirebaseFirestore firestore;

    const lojaId = 'nathy-pratas-e-folheados';
    const anelId = 'nathy-pratas-e-folheados-anel-cora-o-meigo-rose';
    const simplesId = 'produto-simples-catalogo';

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
        'publicar': true,
        'publicadoNoCatalogo': true,
        'ativo': true,
        'precoFinal': 89.9,
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
        'custoReal': 20,
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

    Future<void> seedPublishPrereqs() async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('draft_config')
          .doc('config')
          .set({'nome': 'Nathy'});
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('draft_config')
          .doc('payments')
          .set({'pix': {'enabled': true}});
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      CatalogPublishService.debugFirestoreOverride = firestore;
      CatalogPublishService.debugSyncPaymentsPublicOverride = (_) async {};
    });

    tearDown(() {
      CatalogPublishService.debugFirestoreOverride = null;
      CatalogPublishService.debugSyncPaymentsPublicOverride = null;
    });

    test('publicarCatalogoCanonicamente delega para publishEverything', () async {
      await seedPublishPrereqs();
      await writeDraft(simplesId, nome: 'Pulseira', quantidade: 3);
      await writeEstoque(simplesId, nome: 'Pulseira', quantidade: 3);

      final viaAlias = await CatalogPublishService.publicarCatalogoCanonicamente(
        lojaIdOverride: lojaId,
      );
      final viaDirect = await CatalogPublishService.publishEverything(
        lojaIdOverride: lojaId,
      );

      expect(viaAlias['success'], isTrue);
      expect(viaDirect['success'], isTrue);
      expect(viaAlias['products'], viaDirect['products']);
    });

    test('merge canônico usa grade do estoque quando draft está vazio', () {
      final merged = CatalogPublishService.mergeDraftComEstoqueCanonicoForTest(
        lojaId: lojaId,
        productId: anelId,
        draftData: {
          'nome': 'Anel Coração Meigo Rose',
          'quantidade': 4,
          'variacoes': <String, dynamic>{},
          'estoquePorTamanho': <String, dynamic>{},
        },
        estoqueData: {
          'quantidade': 2,
          'variacoes': {
            '20': {'rosa': 1},
            '22': {'rosa': 1},
          },
          'estoquePorTamanho': {'20': 1, '22': 1},
          'variacoesExtraTipo': {
            '20': {
              'rosa': {'_sem_extra': 'Modelo'},
            },
          },
          'tamanhos': ['20', '22'],
          'precoPorTamanho': {'20': 95.0},
        },
      );

      expect(merged['variacoes'], {
        '20': {'rosa': 1},
        '22': {'rosa': 1},
      });
      expect(merged['estoquePorTamanho'], {'20': 1, '22': 1});
      expect(merged['variacoesExtraTipo'], isNotNull);
      expect(merged['tamanhos'], ['20', '22']);
      expect(merged['precoPorTamanho'], {'20': 95.0});
      expect(merged['quantidade'], 2);
    });

    test('promoteAll publica Anel com grade 20/rosa e 22/rosa no live', () async {
      await writeDraft(
        anelId,
        nome: 'Anel Coração Meigo Rose',
        quantidade: 4,
        extra: {
          'variacoes': <String, dynamic>{},
          'estoquePorTamanho': <String, dynamic>{},
        },
      );
      await writeEstoque(
        anelId,
        nome: 'Anel Coração Meigo Rose',
        quantidade: 2,
        extra: {
          'variacoes': {
            '20': {'rosa': 1},
            '22': {'rosa': 1},
          },
          'estoquePorTamanho': {'20': 1, '22': 1},
          'variacoesExtraTipo': {
            '20': {
              'rosa': {'_sem_extra': 'Modelo'},
            },
          },
          'tamanhos': ['20', '22'],
        },
      );

      await CatalogPublishService.promoteAll(lojaIdOverride: lojaId);

      final live = await readLive(anelId);
      expect(live, isNotNull);
      expect(live!['variacoes'], {
        '20': {'rosa': 1},
        '22': {'rosa': 1},
      });
      expect(live['estoquePorTamanho'], {'20': 1, '22': 1});
      expect(live['quantidade'], 2);
      expect(live.containsKey('custoReal'), isFalse);
    });

    test('estoque sem chave variacoes mantém grade do draft no merge', () {
      final merged = CatalogPublishService.mergeDraftComEstoqueCanonicoForTest(
        lojaId: lojaId,
        productId: anelId,
        draftData: {
          'quantidade': 2,
          'variacoes': {
            '20': {'rosa': 1},
          },
          'estoquePorTamanho': {'20': 1},
        },
        estoqueData: {
          'quantidade': 2,
        },
      );

      expect(merged['variacoes'], {
        '20': {'rosa': 1},
      });
      expect(merged['estoquePorTamanho'], {'20': 1});
    });

    test('estoque com variacoes {} explícito não ressuscita grade do draft', () async {
      await writeDraft(
        anelId,
        nome: 'Anel',
        quantidade: 1,
        extra: {
          'variacoes': {
            '20': {'rosa': 1},
          },
        },
      );
      await writeEstoque(
        anelId,
        nome: 'Anel',
        quantidade: 0,
        extra: {
          'variacoes': <String, dynamic>{},
          'estoquePorTamanho': <String, dynamic>{},
        },
      );

      await CatalogPublishService.promoteAll(lojaIdOverride: lojaId);

      final live = await readLive(anelId);
      expect(live, isNull);
    });

    test('produto simples sem grade continua simples no live', () async {
      await writeDraft(simplesId, nome: 'Pulseira', quantidade: 5);
      await writeEstoque(simplesId, nome: 'Pulseira', quantidade: 5);

      await CatalogPublishService.promoteAll(lojaIdOverride: lojaId);

      final live = await readLive(simplesId);
      expect(live, isNotNull);
      expect(live!['quantidade'], 5);
      final variacoes = live['variacoes'];
      if (variacoes is Map) {
        expect(variacoes.isEmpty, isTrue);
      }
    });

    test('publishEverything via fluxo canônico preserva custoReal fora do live', () async {
      await seedPublishPrereqs();
      await writeDraft(anelId, nome: 'Anel', quantidade: 2);
      await writeEstoque(
        anelId,
        nome: 'Anel',
        quantidade: 2,
        extra: {
          'custoReal': 25,
          'variacoes': {'20': {'rosa': 1}},
          'estoquePorTamanho': {'20': 1},
        },
      );

      await CatalogPublishService.publicarCatalogoCanonicamente(
        lojaIdOverride: lojaId,
      );

      final live = await readLive(anelId);
      final estoque = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(anelId)
          .get();

      expect(live, isNotNull);
      expect(live!.containsKey('custoReal'), isFalse);
      expect(estoque.data()!['custoReal'], 25);
    });
  });
}
