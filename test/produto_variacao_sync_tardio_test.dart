import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-sync-tardio';
const _productId = 'produto-sync-tardio-grade';

Map<String, dynamic> _gradeRemotaFirestore() {
  return {
    'id': _productId,
    'nome': 'Conjunto Remoto',
    'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 5, 10, 0)),
    'variacoes': {
      'P': {
        'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 2},
      },
      'M': {
        'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 4},
      },
    },
    'estoquePorTamanho': {'P': 2, 'M': 4},
    'tamanhos': ['P', 'M'],
    'quantidade': 6,
  };
}

Produto _produtoLocalStaleSemGrade({
  DateTime? updatedAt,
}) {
  return Produto(
    nome: 'Conjunto Remoto',
    custoReal: 30,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 89.9,
    quantidade: 6,
    precoUnitario: 89.9,
    categoria: 'Joias',
    dataEntrada: DateTime(2026, 6, 5),
    lojaId: _lojaId,
    idFirebase: _productId,
    slug: _productId,
    custoEditadoNoCadastro: true,
    updatedAt: updatedAt ?? DateTime(2026, 6, 5, 10, 0),
    variacoes: null,
    variacoesExtraTipo: null,
    estoquePorTamanho: const {},
    tamanhos: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('variação — sync tardio / push stale', () {
    test('shouldPreserveRemoteGradeOnEmptyLocalPush com remoto rico e local stale',
        () {
      final local = _produtoLocalStaleSemGrade();
      final remote = _gradeRemotaFirestore();

      expect(
        ProdutosFirestoreService.remoteTemGradeRica(remote),
        isTrue,
      );
      expect(
        ProdutosFirestoreService.shouldPreserveRemoteGradeOnEmptyLocalPush(
          local: local,
          existingData: remote,
          variacoesPush: {},
          variacoesExtraPush: {},
          estoquePorTamPush: {},
        ),
        isTrue,
      );
      expect(
        ProdutosFirestoreService.isExplicitGradeRemovalOnPush(
          local: local,
          existingData: remote,
          variacoesPush: {},
          variacoesExtraPush: {},
          estoquePorTamPush: {},
        ),
        isFalse,
      );
    });

    test('remoção explícita com updatedAt local posterior ao remoto', () {
      final remote = _gradeRemotaFirestore();
      final local = _produtoLocalStaleSemGrade(
        updatedAt: DateTime(2026, 6, 5, 12, 0),
      );

      expect(
        ProdutosFirestoreService.isExplicitGradeRemovalOnPush(
          local: local,
          existingData: remote,
          variacoesPush: {},
          variacoesExtraPush: {},
          estoquePorTamPush: {},
        ),
        isTrue,
      );
      expect(
        ProdutosFirestoreService.shouldPreserveRemoteGradeOnEmptyLocalPush(
          local: local,
          existingData: remote,
          variacoesPush: {},
          variacoesExtraPush: {},
          estoquePorTamPush: {},
        ),
        isFalse,
      );
    });

    test('buildFinalDocumentPayloadForSet não remove grade quando push preserva remoto',
        () {
      final remote = _gradeRemotaFirestore();
      final resolved = ProdutosFirestoreService.resolveVariationFieldsForFirestorePush(
        local: _produtoLocalStaleSemGrade(),
        existingData: remote,
        variacoesPush: {},
        variacoesExtraPush: {},
        estoquePorTamPush: {},
      );

      final patch = <String, dynamic>{'nome': 'Conjunto Remoto'};
      final removeKeys = <String>{};
      ProdutosFirestoreService.applyVariationFieldsToFirestorePayload(
        patch,
        variacoes: resolved.variacoes,
        variacoesExtraTipo: resolved.variacoesExtraTipo,
        estoquePorTamanho: resolved.estoquePorTamanho,
        variationKeysToRemove: removeKeys,
        treatEmptyAsOmitOnly: resolved.rehydrateLocalFromRemote,
      );

      expect(removeKeys, isEmpty);
      final finalPayload =
          ProdutosFirestoreService.buildFinalDocumentPayloadForSet(
        existingData: remote,
        patch: patch,
        forceRemoveKeys: removeKeys,
      );
      expect(finalPayload['variacoes'], isNotNull);
      expect(finalPayload['estoquePorTamanho'], {'P': 2, 'M': 4});
      expect(finalPayload['tamanhos'], ['P', 'M']);
    });

    test('auto-sync tardio com Hive stale não apaga grade remota', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      final hiveDir =
          Directory.systemTemp.createTempSync('produto_sync_tardio_hive_');
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
            .set(_gradeRemotaFirestore());

        final box = await Hive.openBox<Produto>('produtos_sync_tardio');
        final stale = _produtoLocalStaleSemGrade();
        final hiveKey = await box.add(stale);

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          stale,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
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
        expect(data['variacoes'], isNotNull);
        expect(data['estoquePorTamanho'], {'P': 2, 'M': 4});
        expect(data['tamanhos'], ['P', 'M']);

        final reloaded = box.get(hiveKey);
        expect(reloaded, isNotNull);
        expect(reloaded!.variacoes, isNotNull);
        expect(reloaded.estoquePorTamanho, {'P': 2, 'M': 4});
        expect(reloaded.tamanhos, ['P', 'M']);

        await box.close();
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
        Hive.close();
        if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
      }
    });

    test('remoção explícita apaga grade remota quando updatedAt local é mais novo',
        () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      const productId = 'produto-remocao-explicita';
      try {
        await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .set({
          ..._gradeRemotaFirestore(),
          'id': productId,
          'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
        });

        final p = _produtoLocalStaleSemGrade(
          updatedAt: DateTime(2026, 6, 5, 15, 0),
        )
          ..idFirebase = productId
          ..slug = productId;

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          p,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .get();
        final data = snap.data()!;
        expect(data.containsKey('variacoes'), isFalse);
        expect(data.containsKey('estoquePorTamanho'), isFalse);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('produto simples sem grade continua sincronizando sem variacoes', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      const productId = 'produto-simples-sync-tardio';
      try {
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
          idFirebase: productId,
          slug: productId,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          simples,
          lojaId: _lojaId,
          bumpHiveTimestamp: false,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .get();
        expect(snap.exists, isTrue);
        expect(snap.data()?.containsKey('variacoes'), isFalse);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });
  });
}
