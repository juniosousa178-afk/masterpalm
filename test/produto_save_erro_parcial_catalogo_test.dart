import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produto_cadastro_pos_save_service.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-parcial-catalogo';
const _docId = 'prod-parcial-catalogo';

Produto _produtoPublicado() {
  return Produto(
    nome: 'Anel Teste Parcial',
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
    descricao: 'Descricao local',
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    publicadoNoCatalogo: true,
    variacoes: {'20': {'rosa': 1}},
    estoquePorTamanho: const {'20': 1},
    tamanhos: const ['20'],
    updatedAt: DateTime(2026, 6, 8, 12),
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hiveDir = Directory.systemTemp.createTempSync('produto_parcial_catalogo_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDown(() {
    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutosFirestoreService.limparFalhasUpsertCatalogo();
  });

  tearDownAll(() {
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Produto> _produtoEmBox() async {
    final box = await Hive.openBox<Produto>('produtos_$_lojaId');
    await box.clear();
    final p = _produtoPublicado();
    await box.add(p);
    return box.getAt(0)!;
  }

  test('estoque confirmado + falha draft registra aviso parcial', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();

    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.draft;

    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
    );

    expect(ProdutosFirestoreService.temFalhasUpsertCatalogo, isTrue);
    final falhas = ProdutosFirestoreService.falhasUpsertCatalogo;
    expect(falhas.any((f) => f.operacao == 'upsert_draft_produtos'), isTrue);
    expect(
      falhas.firstWhere((f) => f.operacao == 'upsert_draft_produtos').erro,
      contains('permission-denied'),
    );

    final msg = ProdutoSyncErroUtil.mensagemCadastroFalhaParcialCatalogo(
      falhas: falhas,
    );
    expect(msg, contains('salvo no estoque'));
    expect(msg, contains('falha ao atualizar o catálogo/draft'));
  });

  test('estoque confirmado + falha live registra aviso parcial', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    ProdutosFirestoreService.limparFalhasUpsertCatalogo();
    final p = await _produtoEmBox();

    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.live;

    await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
      produto: p,
      lojaId: _lojaId,
      remoteStatus: ProdutoSyncRemotoStatus.confirmado,
    );

    final falhas = ProdutosFirestoreService.falhasUpsertCatalogo;
    expect(falhas.length, 1);
    expect(falhas.first.operacao, 'upsert_produtos_live');
    expect(falhas.first.path, 'lojas/$_lojaId/produtos/$_docId');
  });

  test('sync estoque confirmado mesmo com produto em Hive', () async {
    final fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    final p = await _produtoEmBox();

    await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('estoque_produtos')
        .doc(_docId)
        .set({
      'id': _docId,
      'nome': p.nome,
      'descricao': p.descricao,
      'quantidade': 2,
      'preco': 90,
      'publicadoNoCatalogo': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });

    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      writeOrigin: 'test.inline',
      enqueueOnFailure: false,
    );

    expect(status, ProdutoSyncRemotoStatus.confirmado);
    final estoque = await fake
        .collection('lojas')
        .doc(_lojaId)
        .collection('estoque_produtos')
        .doc(_docId)
        .get();
    expect(estoque.exists, isTrue);
  });
}
