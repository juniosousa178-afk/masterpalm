// Testes do diagnóstico local de sync de catálogo.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_sync_attempt_context.dart';
import 'package:master_palm/services/catalogo_sync_diagnostic_mask_util.dart';
import 'package:master_palm/services/catalogo_sync_diagnostics_access.dart';
import 'package:master_palm/services/catalogo_sync_diagnostics_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produto_cadastro_pos_save_service.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _lojaId = 'loja-diag-catalogo';
const _docId = 'prod-diag-catalogo-teste';
const _uidCompleto = '57YhMPjFH6SV5Nbig2eUp0BrbOw1';
const _email = 'mariaisaabel42@gmail.com';

Produto _produtoPublicado() {
  return Produto(
    nome: 'Anel Diagnóstico',
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
    descricao: 'Descrição secreta não deve aparecer',
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    publicadoNoCatalogo: true,
    updatedAt: DateTime(2026, 6, 8, 12),
    custoEditadoNoCadastro: true,
  );
}

CatalogoSyncAttemptContext _ctx(String attemptId) =>
    CatalogoSyncAttemptContext.synthetic(
      attemptId: attemptId,
      origin: 'test.save',
      startedAtUtc: DateTime.now().toUtc(),
      sessionStoreIdMasked: 'lo…',
      resolvedStoreIdMasked: 'lo…',
      authUidMasked: CatalogoSyncDiagnosticMaskUtil.mascararUid(_uidCompleto),
    );

Future<Box<String>> _openDiagBox() async {
  final name =
      'catalogo_sync_diagnostics_test_${DateTime.now().microsecondsSinceEpoch}';
  final box = await Hive.openBox<String>(name);
  CatalogoSyncDiagnosticsService.debugBoxOverride = box;
  return box;
}

Future<Produto> _produtoEmBox() async {
  final box = await Hive.openBox<Produto>('produtos_$_lojaId');
  await box.clear();
  final p = _produtoPublicado();
  await box.add(p);
  return box.getAt(0)!;
}

String? _boxJsonOrNull(Box<String> box, String attemptId) => box.get(attemptId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hiveDir = Directory.systemTemp.createTempSync('catalogo_sync_diag_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDown(() async {
    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutosFirestoreService.limparFalhasUpsertCatalogo();
    final box = CatalogoSyncDiagnosticsService.debugBoxOverride;
    CatalogoSyncDiagnosticsService.debugBoxOverride = null;
    if (box != null && box.isOpen) {
      await box.close();
    }
    CatalogoSyncDiagnosticsAccess.resetForTests();
  });

  tearDownAll(() {
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('save gera um único attemptId compartilhado por inline draft live', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    final box = await _openDiagBox();
    final p = await _produtoEmBox();

    final attemptId = const Uuid().v4();
    final ctx = _ctx(attemptId);

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

    await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      writeOrigin: 'test.inline',
      enqueueOnFailure: false,
      catalogoDiagContext: ctx,
    );

    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.live;

    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
      catalogoDiagContext: ctx,
    );

    final raw = _boxJsonOrNull(box, attemptId);
    expect(raw, isNotNull);
    final record = jsonDecode(raw!) as Map<String, dynamic>;
    expect(record['attemptId'], attemptId);
    final ops = (record['operacoes'] as List).cast<Map<String, dynamic>>();
    expect(ops.map((o) => o['operationName']),
        containsAll(['upsert_produtos_live_inline', 'upsert_draft_produtos', 'upsert_produtos_live']));
    final inline =
        ops.firstWhere((o) => o['operationName'] == 'upsert_produtos_live_inline');
    expect(inline['status'], 'success');
    expect(
      ops.firstWhere((o) => o['operationName'] == 'upsert_draft_produtos')['status'],
      'success',
    );
    final live =
        ops.firstWhere((o) => o['operationName'] == 'upsert_produtos_live');
    expect(live['status'], 'failure');
    expect(live['firebaseErrorCode'], 'permission-denied');
    expect(live['firebaseErrorCategory'], 'permission_denied');
  });

  test('saves distintos usam attemptIds distintos', () async {
    await _openDiagBox();
    final a = const Uuid().v4();
    final b = const Uuid().v4();
    await CatalogoSyncDiagnosticsService.ensureAttemptShell(_ctx(a));
    await CatalogoSyncDiagnosticsService.ensureAttemptShell(_ctx(b));
    final list = await CatalogoSyncDiagnosticsService.listAttempts();
    final ids = list.map((r) => r['attemptId']).toSet();
    expect(ids.contains(a), isTrue);
    expect(ids.contains(b), isTrue);
    expect(a == b, isFalse);
  });

  test('falha live não remove resultado de draft', () async {
    final box = await _openDiagBox();
    final attemptId = const Uuid().v4();
    final ctx = _ctx(attemptId);

    final draftHandle = await CatalogoSyncDiagnosticsService.startOperation(
      context: ctx,
      operationName: 'upsert_draft_produtos',
      collectionName: 'draft_produtos',
      storeId: _lojaId,
      produtoId: _docId,
      path: 'lojas/$_lojaId/draft_produtos/$_docId',
      firestoreMethod: 'set',
      mutationIntent: CatalogoSyncMutationIntent.set,
      documentStateHint: CatalogoSyncDocumentStateHint.unknown,
      sourceMethod: 'test',
    );
    await CatalogoSyncDiagnosticsService.completeSuccess(draftHandle);

    final liveHandle = await CatalogoSyncDiagnosticsService.startOperation(
      context: ctx,
      operationName: 'upsert_produtos_live',
      collectionName: 'produtos',
      storeId: _lojaId,
      produtoId: _docId,
      path: 'lojas/$_lojaId/produtos/$_docId',
      firestoreMethod: 'set',
      mutationIntent: CatalogoSyncMutationIntent.set,
      documentStateHint: CatalogoSyncDocumentStateHint.unknown,
      sourceMethod: 'test',
    );
    await CatalogoSyncDiagnosticsService.completeFailure(
      liveHandle,
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'denied',
      ),
    );

    final raw = _boxJsonOrNull(box, attemptId);
    expect(raw, isNotNull);
    final ops = (jsonDecode(raw!)['operacoes'] as List)
        .cast<Map<String, dynamic>>();
    expect(ops.length, 2);
    expect(
      ops.firstWhere((o) => o['operationName'] == 'upsert_draft_produtos')['status'],
      'success',
    );
    expect(
      ops.firstWhere((o) => o['operationName'] == 'upsert_produtos_live')['status'],
      'failure',
    );
  });

  test('falha inline não impede registro de live no mesmo attemptId', () async {
    final fake = FakeFirebaseFirestore();
    CatalogoSyncService.debugFirestoreOverride = fake;
    final box = await _openDiagBox();
    final attemptId = const Uuid().v4();
    final ctx = _ctx(attemptId);
    final p = await _produtoEmBox();

    final inlineHandle = await CatalogoSyncDiagnosticsService.startOperation(
      context: ctx,
      operationName: 'upsert_produtos_live_inline',
      collectionName: 'produtos',
      storeId: _lojaId,
      produtoId: _docId,
      path: 'lojas/$_lojaId/produtos/$_docId',
      firestoreMethod: 'set',
      mutationIntent: CatalogoSyncMutationIntent.set,
      documentStateHint: CatalogoSyncDocumentStateHint.knownAbsentFromExistingState,
      sourceMethod: 'test',
    );
    await CatalogoSyncDiagnosticsService.completeFailure(
      inlineHandle,
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'inline denied',
      ),
    );

    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
      catalogoDiagContext: ctx,
    );

    final raw = _boxJsonOrNull(box, attemptId);
    expect(raw, isNotNull);
    final ops = (jsonDecode(raw!)['operacoes'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      ops.firstWhere((o) => o['operationName'] == 'upsert_produtos_live_inline')['status'],
      'failure',
    );
    expect(
      ops.firstWhere((o) => o['operationName'] == 'upsert_produtos_live')['status'],
      'success',
    );
  });

  test('diagnóstico não contém dados sensíveis no JSON', () async {
    final box = await _openDiagBox();
    final attemptId = const Uuid().v4();
    final ctx = CatalogoSyncAttemptContext.synthetic(
      attemptId: attemptId,
      authUidMasked: CatalogoSyncDiagnosticMaskUtil.mascararUid(_uidCompleto),
    );
    final handle = await CatalogoSyncDiagnosticsService.startOperation(
      context: ctx,
      operationName: 'upsert_produtos_live_inline',
      collectionName: 'produtos',
      storeId: _lojaId,
      produtoId: _docId,
      path: 'lojas/$_lojaId/produtos/$_docId',
      firestoreMethod: 'set',
      mutationIntent: CatalogoSyncMutationIntent.set,
      documentStateHint: CatalogoSyncDocumentStateHint.knownAbsentFromExistingState,
      sourceMethod: 'test',
    );
    await CatalogoSyncDiagnosticsService.completeFailure(
      handle,
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig',
      ),
    );

    final raw = _boxJsonOrNull(box, attemptId);
    expect(raw, isNotNull);
    expect(raw!.contains(_uidCompleto), isFalse);
    expect(raw.contains(_email), isFalse);
    expect(raw.contains('Bearer '), isFalse);
    expect(raw.contains('eyJ'), isFalse);
    expect(raw.contains(_docId), isFalse);
    expect(raw.contains('Descrição secreta'), isFalse);
    expect(raw.contains('firebasestorage'), isFalse);
    expect(
      raw.contains(CatalogoSyncDiagnosticMaskUtil.mascararProdutoId(_docId)),
      isTrue,
    );
    expect(raw.contains('create'), isFalse);
    expect(raw.contains('update'), isFalse);
  });

  test('histórico limita a 30 tentativas', () async {
    final box = await _openDiagBox();
    for (var i = 0; i < 35; i++) {
      final id = 'attempt-$i-${const Uuid().v4()}';
      await CatalogoSyncDiagnosticsService.ensureAttemptShell(
        CatalogoSyncAttemptContext.synthetic(attemptId: id),
      );
    }
    final list = await CatalogoSyncDiagnosticsService.listAttempts();
    expect(list.length, lessThanOrEqualTo(30));
  });

  test('registros com mais de 24h expiram', () async {
    final box = await _openDiagBox();
    final velho = const Uuid().v4();
    final recente = const Uuid().v4();
    await CatalogoSyncDiagnosticsService.ensureAttemptShell(
      CatalogoSyncAttemptContext.synthetic(
        attemptId: recente,
        startedAtUtc: DateTime.now().toUtc(),
      ),
    );
    final antigoRecord = {
      'attemptId': velho,
      'attemptIdCurto': velho.substring(0, 8),
      'timestampUtc':
          DateTime.now().toUtc().subtract(const Duration(hours: 30)).toIso8601String(),
      'origin': 'old',
      'contextoSanitizado': _ctx(velho).toSanitizedMap(),
      'operacoes': <Map<String, dynamic>>[],
    };
    await box.put(velho, jsonEncode(antigoRecord));
    final index = List<String>.from(
      jsonDecode(box.get('_attempt_index') ?? '[]') as List,
    );
    index.add(velho);
    await box.put('_attempt_index', jsonEncode(index));
    final list = await CatalogoSyncDiagnosticsService.listAttempts();
    expect(list.any((r) => r['attemptId'] == velho), isFalse);
    expect(list.any((r) => r['attemptId'] == recente), isTrue);
  });

  test('copy report não contém dados sensíveis', () async {
    final box = await _openDiagBox();
    final attemptId = const Uuid().v4();
    await CatalogoSyncDiagnosticsService.ensureAttemptShell(_ctx(attemptId));
    final raw = _boxJsonOrNull(box, attemptId);
    expect(raw, isNotNull);
    final record = jsonDecode(raw!) as Map<String, dynamic>;
    final report = CatalogoSyncDiagnosticsService.buildSafeReport(record);
    expect(report.contains(_uidCompleto), isFalse);
    expect(report.contains(_email), isFalse);
    expect(report.contains('JWT'), isFalse);
  });

  test('acesso admin forçado e vendedor bloqueado', () async {
    CatalogoSyncDiagnosticsAccess.debugForcePodeAcessar = true;
    expect(await CatalogoSyncDiagnosticsAccess.podeAcessar(), isTrue);
    CatalogoSyncDiagnosticsAccess.debugForcePodeAcessar = false;
    expect(await CatalogoSyncDiagnosticsAccess.podeAcessar(), isFalse);
  });

  test('mascaramento de path e produtoId', () {
    final path = CatalogoSyncDiagnosticMaskUtil.mascararPath(
      'lojas/mirjoias/produtos/mirjoias-anel-teste-xyz',
    );
    expect(path.contains('mirjoias-anel-teste-xyz'), isFalse);
    expect(path.startsWith('lojas/'), isTrue);
    expect(
      CatalogoSyncDiagnosticMaskUtil.mascararUid(_uidCompleto),
      isNot(contains(_uidCompleto)),
    );
  });

  test('snackbar parcial continua com falha live simulada', () async {
    final fake = FakeFirebaseFirestore();
    CatalogoSyncService.debugFirestoreOverride = fake;
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    await _openDiagBox();
    final p = await _produtoEmBox();
    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.live;

    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
      catalogoDiagContext: _ctx(const Uuid().v4()),
    );

    expect(ProdutosFirestoreService.temFalhasUpsertCatalogo, isTrue);
    expect(
      ProdutosFirestoreService.falhasUpsertCatalogo.first.operacao,
      'upsert_produtos_live',
    );
    final msg = ProdutoSyncErroUtil.mensagemCadastroFalhaParcialCatalogo(
      falhas: ProdutosFirestoreService.falhasUpsertCatalogo,
    );
    expect(msg, contains('salvo no estoque'));
  });

  test('mutationIntent permanece set sem afirmar create/update', () async {
    final box = await _openDiagBox();
    final attemptId = const Uuid().v4();
    final handle = await CatalogoSyncDiagnosticsService.startOperation(
      context: _ctx(attemptId),
      operationName: 'upsert_produtos_live',
      collectionName: 'produtos',
      storeId: _lojaId,
      produtoId: _docId,
      path: 'lojas/$_lojaId/produtos/$_docId',
      firestoreMethod: 'set',
      mutationIntent: CatalogoSyncMutationIntent.set,
      documentStateHint: CatalogoSyncDocumentStateHint.unknown,
      sourceMethod: 'test',
    );
    await CatalogoSyncDiagnosticsService.completeSuccess(handle);
    final rawOp = _boxJsonOrNull(box, attemptId);
    expect(rawOp, isNotNull);
    final op = (jsonDecode(rawOp!)['operacoes'] as List)
        .cast<Map<String, dynamic>>()
        .single;
    expect(op['mutationIntent'], 'set');
    expect(op['documentStateHint'], 'unknown');
  });
}
