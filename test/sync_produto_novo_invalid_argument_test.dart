import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_payload_sanitizer.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_sync_fila_retry_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BadObject {
  const _BadObject();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'nathy-pratas-e-folheados';
  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_invalid_argument_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.ultimoErroSyncSanitizado = null;
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_invalid_$s');
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await SyncQueueService.clearQueue();
    await produtosBox.close();
  });

  Produto _novo({
    String nome = 'Teste77',
    String id = 'nathy-pratas-e-folheados-teste77',
  }) {
    return Produto.vazio()
      ..nome = nome
      ..slug = id
      ..idFirebase = id
      ..lojaId = lojaId
      ..categoria = 'Aneis'
      ..subcategoria = 'Prata'
      ..quantidade = 1
      ..precoFinal = 10
      ..precoUnitario = 10
      ..custoReal = 5
      ..precoSugerido = 10
      ..updatedAt = DateTime.now();
  }

  group('sanitização payload Firestore', () {
    test('produto novo simples gera payload Firestore-safe', () {
      final payload = <String, dynamic>{
        'nome': 'Teste77',
        'categoria': 'Aneis',
        'preco': 10.0,
        'quantidade': 1,
        'updatedAt': DateTime.now(),
      };
      final r = FirestorePayloadSanitizer.sanitizeMap(
        payload,
        rootPath: 'estoque_produtos/teste77',
      );
      expect(r.payload['nome'], 'Teste77');
      expect(r.payload['preco'], 10.0);
      expect(r.adjustedPaths, isEmpty);
    });

    test('double.nan é sanitizado para 0', () {
      final r = FirestorePayloadSanitizer.sanitizeMap(
        {'precoSugerido': double.nan},
        rootPath: 'estoque_produtos/x',
      );
      expect(r.payload['precoSugerido'], 0);
      expect(r.adjustedPaths.single, contains('precoSugerido'));
    });

    test('double.infinity é sanitizado para 0', () {
      final r = FirestorePayloadSanitizer.sanitizeMap(
        {'custoReal': double.infinity},
        rootPath: 'estoque_produtos/x',
      );
      expect(r.payload['custoReal'], 0);
      expect(r.adjustedPaths.single, contains('custoReal'));
    });

    test('objeto não serializável é bloqueado com caminho', () {
      expect(
        () => FirestorePayloadSanitizer.sanitizeMap(
          {
            'comboConfig': {'bad': const _BadObject()}
          },
          rootPath: 'estoque_produtos/x',
        ),
        throwsA(
          predicate(
            (Object e) => e is FormatException && e.message.contains('comboConfig.bad'),
          ),
        ),
      );
    });
  });

  group('sync imediato e fila', () {
    test('produto novo válido sincroniza em estoque_produtos', () async {
      final p = _novo();
      await produtosBox.add(p);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(p.idFirebase)
          .get();
      expect(snap.exists, isTrue);
    });

    test('fila e sync imediato usam mesma sanitização para NaN', () async {
      final p = _novo(id: 'nathy-pratas-e-folheados-teste77-na');
      p.precoSugerido = double.nan;
      await produtosBox.add(p);

      final status = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
        p,
        lojaId: lojaId,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(p.idFirebase)
          .get();
      expect(snap.exists, isTrue);
      expect((snap.data()?['precoSugerido'] as num?)?.toDouble(), 0.0);
    });

    test('erro invalid payload entra no lastError com campo suspeito', () async {
      final p = _novo(id: 'nathy-pratas-e-folheados-bad');
      await produtosBox.add(p);

      p.comboConfig = {
        'grupos': [
          {
            'id': 'g1',
            'nome': 'x',
            'opcoes': [const _BadObject()],
          }
        ],
      };

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: true,
      );
      expect(status, ProdutoSyncRemotoStatus.pendenteFila);

      final err = await SyncQueueService.lastProdutoSyncErrorForEntity(
        lojaId: lojaId,
        entityKey: p.key as int,
      );
      expect(err, isNotNull);
      expect(err!, contains('comboConfig.grupos[0].opcoes[0]'));
      expect(ProdutosFirestoreService.ultimoErroSyncSanitizado, contains('comboConfig.grupos[0].opcoes[0]'));
    });
  });
}
