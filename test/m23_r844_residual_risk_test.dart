// M2.3-R8.4.4 — D1–D5 (DeleteField/no-overlap) e H1–H5 (save Hive).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_payload_sanitizer.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stock_revision_client_build_test_support.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('m23_r844_risk_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      await hiveDir.delete(recursive: true);
    }
  });

  tearDown(() {
    resetStockClientBuildForTest();
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutosFirestoreService.resetDebugHiveSaveOverrides();
  });

  setUp(() {
    initializeCompatibleStockClientBuildForTest(285);
  });

  group('D — DeleteField / no-overlap', () {
    test('D1 remoção explícita legítima remove variacoes e estoquePorTamanho',
        () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      const lojaId = 'loja-d1';
      const productId = 'prod-d1';

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'id': productId,
        'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
        'stockRevision': 2,
        'stockOperationId': 'op-remote-d1',
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        },
        'estoquePorTamanho': {'M': 2},
      });

      final p = Produto.vazio()
        ..nome = 'Sem grade'
        ..slug = productId
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 1
        ..precoFinal = 10
        ..precoUnitario = 10
        ..updatedAt = DateTime.now();

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      final data = snap.data()!;
      expect(data.containsKey('variacoes'), isFalse);
      expect(data.containsKey('estoquePorTamanho'), isFalse);
      expect(data['stockRevision'], greaterThan(2));
      expect(data['stockOperationId'], isNotEmpty);
    });

    test('D2 grades sem overlap com local stale bloqueia push', () async {
      final stale = Produto.vazio()
        ..nome = 'Stale'
        ..quantidade = 2
        ..stockRevision = 7
        ..variacoes = {
          'G': {
            'Vermelho': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        }
        ..estoquePorTamanho = const {'G': 2};

      final remote = {
        'stockRevision': 9,
        'stockOperationId': 'op-remote-d2',
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
          },
        },
        'estoquePorTamanho': {'M': 5},
      };

      expect(
        evaluatePushStockSkipByRevision(local: stale, existingData: remote),
        isTrue,
      );
      expect(
        ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
          local: stale,
          existingData: remote,
          bumpHiveTimestamp: false,
        ),
        isTrue,
      );
    });

    test('D2b mesmo revision sem overlap e grade local rica também bloqueia',
        () {
      final stale = Produto.vazio()
        ..quantidade = 2
        ..stockRevision = 7
        ..variacoes = {
          'G': {
            'Vermelho': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        }
        ..estoquePorTamanho = const {'G': 2};

      final remote = {
        'stockRevision': 7,
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
          },
        },
        'estoquePorTamanho': {'M': 5},
      };

      expect(
        evaluatePushStockSkipByRevision(local: stale, existingData: remote),
        isTrue,
      );
    });

    test('D3 metadata com forcePush preserva grade remota', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      const lojaId = 'loja-d3';
      const productId = 'prod-d3';

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'id': productId,
        'descricao': 'Remota',
        'quantidade': 5,
        'stockRevision': 4,
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
          },
        },
        'estoquePorTamanho': {'M': 5},
      });

      final p = Produto.vazio()
        ..nome = 'X'
        ..slug = productId
        ..idFirebase = productId
        ..lojaId = lojaId
        ..descricao = 'Local editada'
        ..quantidade = 5
        ..precoFinal = 10
        ..precoUnitario = 10
        ..stockRevision = 4
        ..variacoes = {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
          },
        }
        ..estoquePorTamanho = const {'M': 5};

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        forcePushFromCadastro: true,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      final data = snap.data()!;
      expect(data['descricao'], 'Local editada');
      expect(
        ProdutoVariacaoExtra.somarCelula(
          (data['variacoes'] as Map)['M']['Azul'],
        ),
        5,
      );
      expect(data['stockRevision'], 4);
    });

    test('D4 autosync stale não envia DeleteField sem intenção explícita',
        () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      const lojaId = 'loja-d4';
      const productId = 'prod-d4';

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .set({
        'id': productId,
        'stockRevision': 9,
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
          },
        },
        'estoquePorTamanho': {'M': 5},
      });

      final stale = Produto.vazio()
        ..nome = 'Stale'
        ..slug = productId
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 2
        ..stockRevision = 7
        ..variacoes = {
          'G': {
            'Vermelho': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        }
        ..estoquePorTamanho = const {'G': 2};

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        stale,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
      );
      expect(status, ProdutoSyncRemotoStatus.semMudancas);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      expect(snap.data()!.containsKey('variacoes'), isTrue);
      expect(
        ProdutoVariacaoExtra.somarCelula(
          (snap.data()!['variacoes'] as Map)['M']['Azul'],
        ),
        5,
      );
    });

    test('D5 remoção parcial preserva A e remove B via payload final', () {
      final existing = {
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 3},
          },
          'G': {
            'Preto': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        },
        'estoquePorTamanho': {'M': 3, 'G': 2},
      };
      final patch = <String, dynamic>{'nome': 'Parcial'};
      final removeKeys = <String>{};
      ProdutosFirestoreService.applyVariationFieldsToFirestorePayload(
        patch,
        variacoes: {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 3},
          },
        },
        variacoesExtraTipo: const {},
        estoquePorTamanho: const {'M': 3},
        variationKeysToRemove: removeKeys,
      );

      final finalPayload = ProdutosFirestoreService.buildFinalDocumentPayloadForSet(
        existingData: existing,
        patch: patch,
        forceRemoveKeys: removeKeys,
      );

      final vars = finalPayload['variacoes'] as Map<String, dynamic>;
      expect(vars.containsKey('M'), isTrue);
      expect(vars.containsKey('G'), isFalse);
      expect(finalPayload['estoquePorTamanho'], {'M': 3});
      expect(_payloadContainsDeleteSentinel(finalPayload), isFalse);
    });
  });

  group('H — _saveProdutoIfInBox', () {
    test('H1 DTO detached sincroniza Firestore sem HiveError', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final p = Produto.vazio()
        ..nome = 'Detached'
        ..slug = 'prod-h1'
        ..idFirebase = 'prod-h1'
        ..lojaId = 'loja-h1'
        ..quantidade = 1
        ..precoFinal = 10
        ..precoUnitario = 10;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: 'loja-h1',
        enqueueOnFailure: false,
        hiveSaveRequirement:
            ProdutoHiveSaveRequirement.optionalForDetachedDto,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);
      expect(ProdutosFirestoreService.debugLastHiveSaveSkipped, isTrue);
      expect(p.isInBox, isFalse);
    });

    test('H2 entidade persistida obrigatória detached falha controlada', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      const lojaId = 'loja-h2';
      const productId = 'prod-h2-req';

      final p = Produto.vazio()
        ..nome = 'Deveria persistir'
        ..slug = productId
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 4
        ..precoFinal = 10
        ..precoUnitario = 10;
      expect(p.isInBox, isFalse);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        bumpHiveTimestamp: true,
        enqueueOnFailure: false,
        hiveSaveRequirement:
            ProdutoHiveSaveRequirement.requiredForPersistedEntity,
      );
      expect(status, ProdutoSyncRemotoStatus.falhaRemota);
      expect(ProdutosFirestoreService.debugLastHiveSaveSkipped, isTrue);
      expect(
        ProdutosFirestoreService.ultimoErroSyncSanitizado,
        contains('persistencia_hive_obrigatoria_objeto_detached'),
      );

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(productId)
          .get();
      expect(snap.exists, isFalse);
    });

    test('H3 produto na box persiste após sync com bump', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final box = await Hive.openBox<Produto>('prod_h3');
      final p = Produto.vazio()
        ..nome = 'Na box'
        ..slug = 'prod-h3'
        ..idFirebase = 'prod-h3'
        ..lojaId = 'loja-h3'
        ..quantidade = 4
        ..precoFinal = 10
        ..precoUnitario = 10;
      final key = await box.add(p);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: 'loja-h3',
        bumpHiveTimestamp: true,
        enqueueOnFailure: false,
        hiveSaveRequirement:
            ProdutoHiveSaveRequirement.requiredForPersistedEntity,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);
      expect(ProdutosFirestoreService.debugLastHiveSaveSkipped, isFalse);

      final reloaded = box.get(key)!;
      expect(reloaded.updatedAt, isNotNull);
      await box.close();
    });

    test('H3b reabertura Hive contém campos após save na box', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final box = await Hive.openBox<Produto>('prod_h3b');
      final p = Produto.vazio()
        ..nome = 'Persist'
        ..slug = 'prod-h3b'
        ..idFirebase = 'prod-h3b'
        ..lojaId = 'loja-h3b'
        ..descricao = 'Antes'
        ..quantidade = 2
        ..precoFinal = 10
        ..precoUnitario = 10;
      final key = await box.add(p);
      p.descricao = 'Depois do sync';

      await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: 'loja-h3b',
        forcePushFromCadastro: true,
        bumpHiveTimestamp: true,
        enqueueOnFailure: false,
        hiveSaveRequirement:
            ProdutoHiveSaveRequirement.requiredForPersistedEntity,
      );

      final reloaded = box.get(key)!;
      expect(reloaded.descricao, 'Depois do sync');
      await box.close();
    });

    test('H4 sync público sem custoReal com objeto detached', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      const lojaId = 'loja-h4';
      const productId = 'prod-h4';

      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .doc(productId)
          .set({'nome': 'Legado', 'custoReal': 99});

      final p = Produto.vazio()
        ..nome = 'Publicado'
        ..slug = productId
        ..idFirebase = productId
        ..lojaId = lojaId
        ..quantidade = 1
        ..precoFinal = 10
        ..precoUnitario = 10
        ..publicadoNoCatalogo = true;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
        hiveSaveRequirement:
            ProdutoHiveSaveRequirement.optionalForDetachedDto,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);
      expect(ProdutosFirestoreService.debugLastHiveSaveSkipped, isTrue);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .doc(productId)
          .get();
      expect(snap.data()!.containsKey('custoReal'), isFalse);
    });

    test('H5 falha obrigatória no save Hive propaga erro', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final box = await Hive.openBox<Produto>('prod_h5');
      final p = Produto.vazio()
        ..nome = 'Falha save'
        ..slug = 'prod-h5'
        ..idFirebase = 'prod-h5'
        ..lojaId = 'loja-h5'
        ..quantidade = 1
        ..precoFinal = 10
        ..precoUnitario = 10;
      await box.add(p);

      ProdutosFirestoreService.debugProdutoSaveOverride = (_) async {
        throw StateError('hive-save-simulated-failure');
      };

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: 'loja-h5',
        bumpHiveTimestamp: true,
        enqueueOnFailure: false,
        hiveSaveRequirement:
            ProdutoHiveSaveRequirement.requiredForPersistedEntity,
      );
      expect(status, ProdutoSyncRemotoStatus.falhaRemota);
      await box.close();
    });
  });
}

bool _payloadContainsDeleteSentinel(dynamic value) {
  if (FirestorePayloadSanitizer.isDeleteFieldValue(value)) return true;
  if (value is Map) {
    for (final e in value.values) {
      if (_payloadContainsDeleteSentinel(e)) return true;
    }
  }
  return false;
}
