import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-cadastro-persist';
const _productId = 'produto-cadastro-persist-1';

Produto _produtoBase({
  String descricao = 'Descricao original',
  double preco = 50,
  String categoria = 'Aneis',
  int quantidade = 5,
  DateTime? updatedAt,
}) {
  return Produto(
    nome: 'Produto Teste',
    custoReal: 20,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: preco,
    quantidade: quantidade,
    precoUnitario: preco,
    categoria: categoria,
    dataEntrada: DateTime(2026, 6, 5),
    descricao: descricao,
    lojaId: _lojaId,
    idFirebase: _productId,
    slug: _productId,
    updatedAt: updatedAt ?? DateTime(2026, 6, 5, 12, 0),
    custoEditadoNoCadastro: true,
  );
}

Future<void> _closeHiveBoxesByName(Iterable<String> names) async {
  for (final name in names) {
    if (Hive.isBoxOpen(name)) {
      await Hive.box(name).close();
    }
  }
  final vendasBoxName = HiveBoxNames.vendas(_lojaId);
  if (Hive.isBoxOpen(vendasBoxName)) {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VendaAdapter());
    }
    await Hive.box<Venda>(vendasBoxName).close();
  }
}

Future<void> _deleteHiveTempDirWithRetry(Directory hiveDir) async {
  if (!hiveDir.existsSync()) return;
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      await hiveDir.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}

Future<void> _cleanupProdutoCadastroHiveTemp(
  Directory hiveDir, {
  List<String> boxNames = const [],
}) async {
  await _closeHiveBoxesByName(boxNames);
  await Hive.close();
  await _deleteHiveTempDirWithRetry(hiveDir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cadastro produto — persistência local e sync', () {
    test('edição de descrição/preço/categoria/quantidade refletem no Hive', () async {
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_cadastro_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      try {
        final box = await Hive.openBox<Produto>('produtos_cadastro');
        final p = _produtoBase();
        final key = await box.add(p);

        final loaded = box.get(key)!;
        loaded
          ..descricao = 'TESTE PERSISTENCIA 20260605'
          ..precoFinal = 99.9
          ..precoUnitario = 99.9
          ..categoria = 'Colares'
          ..quantidade = 12
          ..updatedAt = DateTime(2026, 6, 5, 14, 0);
        await loaded.save();

        final reread = box.get(key)!;
        expect(reread.descricao, 'TESTE PERSISTENCIA 20260605');
        expect(reread.precoFinal, 99.9);
        expect(reread.categoria, 'Colares');
        expect(reread.quantidade, 12);
        await box.close();
      } finally {
        await _cleanupProdutoCadastroHiveTemp(
          hiveDir,
          boxNames: ['produtos_cadastro'],
        );
      }
    });

    test('payload Firestore contém campos alterados no push', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_cadastro_push_hive_');
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
            .set({'id': _productId, 'nome': 'Legado'});

        final box = await Hive.openBox<Produto>('produtos_cadastro_push');
        final p = _produtoBase(
          descricao: 'TESTE PERSISTENCIA 20260605',
          preco: 77.7,
          categoria: 'Pulseiras',
          quantidade: 8,
          updatedAt: DateTime(2026, 6, 5, 15, 0),
        );
        await box.add(p);

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          p,
          lojaId: _lojaId,
          bumpHiveTimestamp: true,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);
        await box.close();

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        final data = snap.data()!;
        expect(data['descricao'], 'TESTE PERSISTENCIA 20260605');
        expect(data['preco'], 77.7);
        expect(data['categoria'], 'Pulseiras');
        expect(data['quantidade'], 8);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        await _cleanupProdutoCadastroHiveTemp(
          hiveDir,
          boxNames: ['produtos_cadastro_push'],
        );
      }
    });

    test('pull preserva edição local quando updatedAt local é mais novo', () {
      final local = _produtoBase(
        descricao: 'Local mais novo',
        updatedAt: DateTime(2026, 6, 5, 16, 0),
      );

      expect(
        ProdutosFirestoreService.shouldPreserveLocalEditsOnFirestorePull(
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: DateTime(2026, 6, 5, 14, 0),
        ),
        isTrue,
      );
    });

    test('auto-sync stale não sobrescreve remoto mais novo', () async {
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
          'nome': 'Remoto correto',
          'descricao': 'Remoto correto',
          'preco': 60.0,
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
        });

        final staleLocal = _produtoBase(
          descricao: 'Hive stale antigo',
          preco: 10,
          updatedAt: DateTime(2026, 6, 5, 12, 0),
        );

        expect(
          ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
            local: staleLocal,
            existingData: {
              'descricao': 'Remoto correto',
              'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
            },
            bumpHiveTimestamp: false,
          ),
          isTrue,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          staleLocal,
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
        expect(snap.data()!['descricao'], 'Remoto correto');
        expect(snap.data()!['preco'], 60.0);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('bump sem cadastro explícito não sobrescreve remoto mais novo', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_cadastro_bump_stale_hive_');
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
          'descricao': 'Remoto correto',
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
        });

        final box = await Hive.openBox<Produto>('produto_cadastro_bump_stale');
        final staleLocal = _produtoBase(
          descricao: 'Hive stale com bump indevido',
          updatedAt: DateTime(2026, 6, 5, 12, 0),
        );
        await box.add(staleLocal);

        expect(
          ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
            local: staleLocal,
            existingData: {
              'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
            },
            bumpHiveTimestamp: true,
            updatedAtBeforeBump: staleLocal.updatedAt,
            forcePushFromCadastro: false,
          ),
          isTrue,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          staleLocal,
          lojaId: _lojaId,
          bumpHiveTimestamp: true,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.semMudancas);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        expect(snap.data()!['descricao'], 'Remoto correto');
        await box.close();
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        await _cleanupProdutoCadastroHiveTemp(
          hiveDir,
          boxNames: ['produto_cadastro_bump_stale'],
        );
      }
    });

    test('save explícito (forcePushFromCadastro) ainda envia mesmo com remoto mais novo', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_cadastro_bump_hive_');
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
          'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
        });

        final box = await Hive.openBox<Produto>('produtos_cadastro_bump');
        final editado = _produtoBase(
          descricao: 'Edição explícita do usuário',
          updatedAt: DateTime(2026, 6, 5, 12, 0),
        );
        await box.add(editado);

        editado.updatedAt = DateTime(2026, 6, 5, 17, 0);

        expect(
          ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
            local: editado,
            existingData: {
              'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 16, 0)),
            },
            bumpHiveTimestamp: true,
            updatedAtBeforeBump: editado.updatedAt,
            forcePushFromCadastro: true,
          ),
          isFalse,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          editado,
          lojaId: _lojaId,
          bumpHiveTimestamp: true,
          forcePushFromCadastro: true,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);
        await box.close();

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(_productId)
            .get();
        expect(snap.data()!['descricao'], 'Edição explícita do usuário');
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        await _cleanupProdutoCadastroHiveTemp(
          hiveDir,
          boxNames: ['produtos_cadastro_bump'],
        );
      }
    });

    test('produto simples sem variação continua sincronizando', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_cadastro_simples_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      const simpleId = 'produto-simples-cadastro';
      try {
        final box = await Hive.openBox<Produto>('produtos_cadastro_simples');
        final simples = Produto(
          nome: 'Simples',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 10,
          quantidade: 3,
          precoUnitario: 10,
          categoria: 'Geral',
          dataEntrada: DateTime(2026, 6, 5),
          lojaId: _lojaId,
          idFirebase: simpleId,
          slug: simpleId,
          updatedAt: DateTime(2026, 6, 5, 15, 0),
        );
        await box.add(simples);

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          simples,
          lojaId: _lojaId,
          bumpHiveTimestamp: true,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);
        await box.close();

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(simpleId)
            .get();
        expect(snap.exists, isTrue);
        expect(snap.data()?.containsKey('variacoes'), isFalse);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        await _cleanupProdutoCadastroHiveTemp(
          hiveDir,
          boxNames: ['produtos_cadastro_simples'],
        );
      }
    });
  });
}
