import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-write-origin';
const _productId = 'prod-write-origin-1';

Produto _produtoBase() {
  return Produto(
    nome: 'Origem Write',
    custoReal: 5,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 20,
    quantidade: 1,
    precoUnitario: 20,
    categoria: 'Geral',
    dataEntrada: DateTime(2026, 6, 5),
    descricao: 'Teste origem',
    lojaId: _lojaId,
    idFirebase: _productId,
    slug: _productId,
    updatedAt: DateTime(2026, 6, 5, 15, 0),
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('metadados de origem de write', () {
    test('push grava lastWriteOrigin e lastWriteBumpHiveTimestamp', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_write_origin_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      try {
        final box = await Hive.openBox<Produto>('produto_write_origin');
        final p = _produtoBase();
        await box.add(p);
        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          p,
          lojaId: _lojaId,
          bumpHiveTimestamp: true,
          forcePushFromCadastro: true,
          writeOrigin: 'produto_form.save',
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        final data = snap.data()!;
        expect(data['lastWriteOrigin'], 'produto_form.save');
        expect(data['lastWriteReason'], 'produto_form.save');
        expect(data['lastWriteBumpHiveTimestamp'], isTrue);
        expect(data['lastWritePath'],
            'lojas/$_lojaId/estoque_produtos/$_productId');
        expect(data['lastWriteAtClient'], isA<Timestamp>());
        await box.close();
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        Hive.close();
        if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
      }
    });

    test('estoque_service fallback usa bump=false e origem auditável', () async {
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
          'descricao': 'Remoto',
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
        });

        final stale = _produtoBase()
          ..descricao = 'Stale'
          ..updatedAt = DateTime(2026, 6, 5, 10, 0);

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          stale,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          writeOrigin: 'estoque_service.fallback_sync',
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.semMudancas);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        expect(snap.data()!['descricao'], 'Remoto');
        expect(snap.data()!.containsKey('lastWriteOrigin'), isFalse);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });
  });
}
