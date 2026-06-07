import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-catalogo-cadastro';
const _productId = 'prod-cat-cad-1';

Produto _produtoHive({
  String descricao = 'Cadastro privado correto',
  DateTime? updatedAt,
}) {
  return Produto(
    nome: 'Anel Teste',
    custoReal: 8,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 30,
    quantidade: 2,
    precoUnitario: 30,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 6, 5),
    descricao: descricao,
    lojaId: _lojaId,
    idFirebase: _productId,
    slug: _productId,
    updatedAt: updatedAt ?? DateTime(2026, 6, 5, 9, 0),
    publicadoNoCatalogo: true,
    ativoNoRascunho: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catálogo não sobrescreve cadastro privado stale', () {
    test('auto-sync stale não regrava estoque_produtos nem produtos', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      try {
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .set({
          'id': _productId,
          'descricao': 'Remoto autoritativo',
          'preco': 45.0,
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
        });
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('produtos')
            .doc(_productId)
            .set({
          'id': _productId,
          'descricao': 'Remoto autoritativo',
          'preco': 45.0,
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
        });

        final stale = _produtoHive(descricao: 'Hive antigo');

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          stale,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          writeOrigin: 'produto_auto_sync.estoque',
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.semMudancas);

        // Simula auto-sync que NÃO deve rodar catálogo após skip (guard no serviço).
        // Aqui validamos que estoque e catálogo permanecem intactos sem novo write.
        final estoque = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        final catalogo = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('produtos')
            .doc(_productId)
            .get();

        expect(estoque.data()!['descricao'], 'Remoto autoritativo');
        expect(catalogo.data()!['descricao'], 'Remoto autoritativo');
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('draft_produtos não é copiado de volta para estoque_produtos', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      try {
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('draft_produtos')
            .doc(_productId)
            .set({
          'id': _productId,
          'descricao': 'Somente rascunho catálogo',
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 18, 0)),
        });
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .set({
          'id': _productId,
          'descricao': 'Cadastro privado',
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 17, 0)),
        });

        final hive = _produtoHive(
          descricao: 'Cadastro privado',
          updatedAt: DateTime(2026, 6, 5, 16, 0),
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          hive,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.semMudancas);

        final estoque = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        expect(estoque.data()!['descricao'], 'Cadastro privado');
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });
  });
}
