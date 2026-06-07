import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-persistencia-remota';
const _productId = 'prod-remoto-1';

Produto _produto({
  String descricao = 'Descricao A',
  DateTime? updatedAt,
  Map<String, dynamic>? variacoes,
}) {
  return Produto(
    nome: 'Produto Remoto',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 40,
    quantidade: 3,
    precoUnitario: 40,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 6, 5),
    descricao: descricao,
    lojaId: _lojaId,
    idFirebase: _productId,
    slug: _productId,
    updatedAt: updatedAt ?? DateTime(2026, 6, 5, 10, 0),
    variacoes: variacoes,
    publicadoNoCatalogo: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('persistência remota após auto-sync', () {
    test('edição salva permanece após push stale da fila', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      try {
        final remotoCorreto = {
          'id': _productId,
          'nome': 'Produto Remoto',
          'descricao': 'TESTE PERSISTENCIA 20260605 14:00',
          'preco': 55.0,
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 14, 0)),
        };
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .set(remotoCorreto);

        final stale = _produto(
          descricao: 'Antigo da fila',
          updatedAt: DateTime(2026, 6, 5, 9, 0),
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          stale,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          writeOrigin: 'sync_queue.upsert_produto',
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.semMudancas);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        expect(snap.data()!['descricao'], 'TESTE PERSISTENCIA 20260605 14:00');
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('variações permanecem quando Hive local envia grade vazia stale', () async {
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
          'nome': 'Produto Remoto',
          'variacoes': {
            'P|M': {'cor': 'Prata', 'qtd': 2},
          },
          'estoquePorTamanho': {'P': 2},
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 14, 0)),
        });

        final staleSemGrade = _produto(
          updatedAt: DateTime(2026, 6, 5, 9, 0),
          variacoes: null,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          staleSemGrade,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.semMudancas);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        final variacoes = snap.data()!['variacoes'] as Map;
        expect(variacoes.containsKey('P|M'), isTrue);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('save explícito com updatedAt fresco vence remoto antigo', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_persist_remota_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      try {
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .set({
          'id': _productId,
          'descricao': 'Remoto velho',
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 12, 0)),
        });

        final box = await Hive.openBox<Produto>('produto_persist_remota');
        final editado = _produto(
          descricao: 'TESTE PERSISTENCIA 20260605 15:30',
          updatedAt: DateTime(2026, 6, 5, 15, 30),
        );
        await box.add(editado);

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          editado,
          lojaId: _lojaId,
          bumpHiveTimestamp: true,
          forcePushFromCadastro: true,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        expect(snap.data()!['descricao'], 'TESTE PERSISTENCIA 20260605 15:30');
        await box.close();
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        Hive.close();
        if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
      }
    });
  });
}
