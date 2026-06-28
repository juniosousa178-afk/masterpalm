// Política canônica: formulário ignora inline e publica via draft+live.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_live_inline_policy.dart';
import 'package:master_palm/services/catalogo_sync_attempt_context.dart';
import 'package:master_palm/services/catalogo_sync_diagnostics_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produto_cadastro_pos_save_service.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _lojaId = 'loja-canonical-inline';
const _docId = 'prod-canonical-inline-test';

Produto _produtoPublicado() {
  return Produto(
    nome: 'Anel Canônico',
    custoReal: 20,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 90,
    quantidade: 2,
    precoUnitario: 90,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 6, 8),
    descricao: 'Teste canônico',
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    publicadoNoCatalogo: true,
    updatedAt: DateTime(2026, 6, 8, 12),
    custoEditadoNoCadastro: true,
  );
}

Future<Produto> _produtoEmBox() async {
  final box = await Hive.openBox<Produto>('produtos_$_lojaId');
  await box.clear();
  final p = _produtoPublicado();
  await box.add(p);
  return box.getAt(0)!;
}

Future<void> _seedEstoque(FakeFirebaseFirestore fake, Produto p) async {
  await fake
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_produtos')
      .doc(_docId)
      .set({
    'id': _docId,
    'nome': p.nome,
    'quantidade': 2,
    'publicadoNoCatalogo': true,
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hiveDir = Directory.systemTemp.createTempSync('canonical_inline_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  setUp(() {
    ProdutosFirestoreService.debugInlineUpsertCallCount = 0;
  });

  tearDown(() {
    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutosFirestoreService.limparFalhasUpsertCatalogo();
    CatalogoSyncDiagnosticsService.debugBoxOverride = null;
  });

  tearDownAll(() {
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('formulário canônico não executa upsert_produtos_live_inline', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();
    await _seedEstoque(fake, p);
    final ctx = CatalogoSyncAttemptContext.synthetic(
      attemptId: const Uuid().v4(),
      startedAtUtc: DateTime.now().toUtc(),
    );

    await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      writeOrigin: 'test.form.canonical',
      enqueueOnFailure: false,
      catalogoDiagContext: ctx,
      catalogoLiveInlinePolicy:
          CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
    );

    expect(ProdutosFirestoreService.debugInlineUpsertCallCount, 0);
    final liveSnap = await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('produtos')
        .doc(_docId)
        .get();
    expect(liveSnap.exists, isFalse);
  });

  test('formulário canônico publica draft e live uma vez com mesmo attemptId',
      () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    final box = await Hive.openBox<String>(
      'diag_canonical_${DateTime.now().microsecondsSinceEpoch}',
    );
    CatalogoSyncDiagnosticsService.debugBoxOverride = box;
    final p = await _produtoEmBox();
    await _seedEstoque(fake, p);
    final attemptId = const Uuid().v4();
    final ctx = CatalogoSyncAttemptContext.synthetic(
      attemptId: attemptId,
      startedAtUtc: DateTime.now().toUtc(),
    );

    await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      enqueueOnFailure: false,
      catalogoDiagContext: ctx,
      catalogoLiveInlinePolicy:
          CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
    );

    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
      catalogoDiagContext: ctx,
    );

    final live = await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('produtos')
        .doc(_docId)
        .get();
    final draft = await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('draft_produtos')
        .doc(_docId)
        .get();
    expect(live.exists, isTrue);
    expect(draft.exists, isTrue);

    final record = jsonDecode(box.get(attemptId)!) as Map<String, dynamic>;
    final ops = (record['operacoes'] as List).cast<Map<String, dynamic>>();
    expect(
      ops.where((o) => o['operationName'] == 'upsert_draft_produtos').length,
      1,
    );
    expect(
      ops.where((o) => o['operationName'] == 'upsert_produtos_live').length,
      1,
    );
    final inline = ops.firstWhere(
      (o) => o['operationName'] == 'upsert_produtos_live_inline',
    );
    expect(inline['status'], 'skipped');
    expect(inline['skipReason'], 'canonical_post_save');
  });

  test('inline ignorado não cria falha nem aviso amarelo', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();
    await _seedEstoque(fake, p);
    final attemptId = const Uuid().v4();
    final ctx = CatalogoSyncAttemptContext.synthetic(
      attemptId: attemptId,
      startedAtUtc: DateTime.now().toUtc(),
    );

    await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      enqueueOnFailure: false,
      catalogoDiagContext: ctx,
      catalogoLiveInlinePolicy:
          CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
    );
    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
      catalogoDiagContext: ctx,
    );

    expect(
      ProdutosFirestoreService.falhasCanonicalDoAttempt(attemptId),
      isEmpty,
    );
    expect(
      ProdutoSyncErroUtil.mensagemCadastroConfirmado(publicar: true),
      isNot(contains('permission-denied')),
    );
  });

  test('falha real em live canônico gera aviso e filtra por attemptId', () async {
    final fake = FakeFirebaseFirestore();
    CatalogoSyncService.debugFirestoreOverride = fake;
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();
    final attemptId = const Uuid().v4();
    final ctx = CatalogoSyncAttemptContext.synthetic(
      attemptId: attemptId,
      startedAtUtc: DateTime.now().toUtc(),
    );

    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.live;
    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
      catalogoDiagContext: ctx,
    );

    final falhas = ProdutosFirestoreService.falhasCanonicalDoAttempt(attemptId);
    expect(falhas.length, 1);
    expect(falhas.first.operacao, 'upsert_produtos_live');
    expect(falhas.first.attemptId, attemptId);
    final msg = ProdutoSyncErroUtil.mensagemCadastroFalhaParcialCatalogo(
      falhas: falhas,
    );
    expect(msg, contains('upsert_produtos_live'));
  });

  test('fluxo legado continua executando inline', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();
    await _seedEstoque(fake, p);

    await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      enqueueOnFailure: false,
    );

    expect(ProdutosFirestoreService.debugInlineUpsertCallCount, 1);
    final live = await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('produtos')
        .doc(_docId)
        .get();
    expect(live.exists, isTrue);
  });

  test('falha inline legado não contamina snackbar do formulário canônico',
      () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();
    await _seedEstoque(fake, p);

    final legacyAttempt = const Uuid().v4();
    ProdutosFirestoreService.registrarFalhaUpsertCatalogo(
      lojaId: _lojaId,
      produtoId: _docId,
      path: 'lojas/$_lojaId/produtos/$_docId',
      operacao: 'upsert_produtos_live_inline',
      error: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'legacy inline',
      ),
      attemptId: legacyAttempt,
      origin: 'produtos_firestore.inline_fallback',
    );

    final formAttempt = const Uuid().v4();
    expect(
      ProdutosFirestoreService.falhasCanonicalDoAttempt(formAttempt),
      isEmpty,
    );
  });
}
