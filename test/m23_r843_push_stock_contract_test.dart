// M2.3-R8.4.3 — contratos mínimos de push de estoque (cadastro, metadata, limpeza, gate).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/core/stock_revision_client_build_resolver.dart';
import 'package:master_palm/core/stock_revision_operation_gate.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('m23_r843_contract_');
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

  tearDown(StockRevisionOperationGate.resetDebugOverrides);

  group('R8.4.3 — contratos de push', () {
    setUp(() {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
    });

    test('cadastro explícito (forcePush) envia metadata sem stale skip', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      const lojaId = 'loja-r843-cadastro';
      const productId = 'prod-r843-cadastro';

      try {
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .set({'id': productId, 'nome': 'Legado'});

        final p = Produto(
          nome: 'Produto',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 44,
          quantidade: 3,
          precoUnitario: 44,
          categoria: 'Geral',
          dataEntrada: DateTime(2026, 7, 1),
          descricao: 'Desc R843',
          lojaId: lojaId,
          idFirebase: productId,
          slug: productId,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          p,
          lojaId: lojaId,
          forcePushFromCadastro: true,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .get();
        expect(snap.data()?['descricao'], 'Desc R843');
        expect(snap.data()?['preco'], 44);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('limpeza de grade legada não é bloqueada pelo stale guard', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      const lojaId = 'loja-r843-clear';
      const productId = 'prod-r843-clear';

      try {
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .set({
          'id': productId,
          'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
          'variacoes': {
            'M': {
              'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 2},
            },
          },
          'estoquePorTamanho': {'M': 2},
        });

        final p = Produto.vazio()
          ..nome = 'Simples'
          ..slug = productId
          ..idFirebase = productId
          ..lojaId = lojaId
          ..quantidade = 1
          ..precoFinal = 10
          ..precoUnitario = 10
          ..updatedAt = DateTime.now();

        expect(
          ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
            local: p,
            existingData: {
              'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
              'variacoes': {
                'M': {
                  'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 2},
                },
              },
              'estoquePorTamanho': {'M': 2},
            },
            bumpHiveTimestamp: false,
          ),
          isFalse,
        );

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
            .collection('estoque_produtos')
            .doc(productId)
            .get();
        expect(snap.data()?.containsKey('variacoes'), isFalse);
        expect(snap.data()?.containsKey('estoquePorTamanho'), isFalse);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('conversão estrutural simples↔grade bypassa localDominates', () {
      final local = Produto.vazio()..quantidade = 1;
      final remote = {
        'variacoes': {
          'M': {
            'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 2},
          },
        },
        'estoquePorTamanho': {'M': 2},
      };
      expect(
        evaluatePushStockSkipByRevision(local: local, existingData: remote),
        isFalse,
      );
    });

    test('gate de revisão só quando grade muda no payload', () {
      StockRevisionClientBuildResolver.instance.setTestOverride(285);
      final localGrade = ProdutoEstoqueGradeSnapshot.fromProduto(
        Produto.vazio()..quantidade = 5,
      );
      final remoteGrade = ProdutoEstoqueGradeSnapshot.fromRemote({
        'quantidade': 5,
      });
      expect(localGrade.gradeDiffersFrom(remoteGrade), isFalse);

      expect(
        () => StockRevisionOperationGate.assertAllowed(
          StockRevisionOperationKind.importacaoProduto,
        ),
        returnsNormally,
      );
    });
  });
}
