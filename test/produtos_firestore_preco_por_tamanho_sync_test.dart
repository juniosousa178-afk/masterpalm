import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Produto _produtoBase({
  required String lojaId,
  required String productId,
  Map<String, double>? precoPorTamanho,
}) {
  return Produto(
    nome: 'Correntes Veneziana V 15',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 73.9,
    quantidade: 3,
    precoUnitario: 73.9,
    categoria: 'Correntes',
    dataEntrada: DateTime(2026, 5, 26),
    lojaId: lojaId,
    idFirebase: productId,
    slug: productId,
    estoquePorTamanho: const {
      '45cm': 1,
      '60cm': 2,
    },
    precoPorTamanho: precoPorTamanho,
    publicadoNoCatalogo: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProdutosFirestoreService precoPorTamanho sync', () {
    late FakeFirebaseFirestore firestore;

    const lojaId = 'nathy-pratas-e-folheados';
    const productId = 'nathy-pratas-e-folheados-correntes-veneziana-v-15';

    Future<Map<String, dynamic>?> readEstoque() async {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(productId)
          .get();
      return snap.data();
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
    });

    tearDown(() {
      ProdutosFirestoreService.debugFirestoreOverride = null;
    });

    test('preserva precoPorTamanho remoto quando produto local vem sem mapa',
        () async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(productId)
          .set({
        'id': productId,
        'slug': productId,
        'nome': 'Correntes Veneziana V 15',
        'precoPorTamanho': {
          '45 cm': 49.9,
          '60 cm': 59.9,
        },
      });

      final produto = _produtoBase(
        lojaId: lojaId,
        productId: productId,
        precoPorTamanho: null,
      );

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        produto,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );

      expect(status, ProdutoSyncRemotoStatus.confirmado);
      final remoto = await readEstoque();
      expect(remoto?['precoPorTamanho'], {
        '45 cm': 49.9,
        '60 cm': 59.9,
      });
    });

    test('substitui precoPorTamanho remoto quando produto local traz mapa',
        () async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(productId)
          .set({
        'id': productId,
        'slug': productId,
        'nome': 'Correntes Veneziana V 15',
        'precoPorTamanho': {
          '45 cm': 49.9,
          '70 cm': 99.9,
        },
      });

      final produto = _produtoBase(
        lojaId: lojaId,
        productId: productId,
        precoPorTamanho: const {
          '45 cm': 49.9,
          '60 cm': 59.9,
        },
      );

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        produto,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );

      expect(status, ProdutoSyncRemotoStatus.confirmado);
      final remoto = await readEstoque();
      expect(remoto?['precoPorTamanho'], {
        '45 cm': 49.9,
        '60 cm': 59.9,
      });
    });

    test('nao cria precoPorTamanho null para produto sem mapa', () async {
      final produto = _produtoBase(
        lojaId: lojaId,
        productId: productId,
        precoPorTamanho: null,
      );

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        produto,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );

      expect(status, ProdutoSyncRemotoStatus.confirmado);
      final remoto = await readEstoque();
      expect(remoto?.containsKey('precoPorTamanho'), isFalse);
    });

    test('helper so limpa precoPorTamanho quando houver mapa preenchido', () {
      expect(
        ProdutosFirestoreService.shouldClearPrecoPorTamanhoBeforeMerge(null),
        isFalse,
      );
      expect(
        ProdutosFirestoreService.shouldClearPrecoPorTamanhoBeforeMerge({}),
        isFalse,
      );
      expect(
        ProdutosFirestoreService.shouldClearPrecoPorTamanhoBeforeMerge(
          const {'45 cm': 49.9},
        ),
        isTrue,
      );
    });
  });
}
