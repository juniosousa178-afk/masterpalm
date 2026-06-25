// Persistência do reparo de sessão após reinício simulado.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/produto_sync_recovery_access.dart';
import 'package:master_palm/services/produto_sync_recovery_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaSessao = 'mariaisaabel42';
  const lojaCanonica = 'mirjoias';
  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_sess_restart_');
    hivePath = dir.path;
    Hive.init(hivePath);
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    ProdutoSyncRecoveryAccess.debugForcePodeAcessar = true;
    ProdutoSyncRecoveryAccess.debugForceCanonicalOwner = true;
    await ProdutoSyncRecoverySessionService.resetHistoryForTests();
  });

  tearDown(() async {
    ProdutoSyncRecoveryAccess.resetForTests();
    if (Hive.isBoxOpen('sessao')) await Hive.box('sessao').close();
    if (Hive.isBoxOpen('config')) await Hive.box('config').close();
  });

  test('reparo persiste após fechar e reabrir Hive', () async {
    final sessao = await Hive.openBox('sessao');
    final cfg = await Hive.openBox('config');
    await sessao.put('store_id', lojaSessao);
    await cfg.put('store_id', lojaSessao);

    final record =
        await ProdutoSyncRecoverySessionService.repararSessaoParaLojaCanonica(
      lojaCanonica: lojaCanonica,
    );
    expect(record?.storeIdNovo, lojaCanonica);

    await sessao.close();
    await cfg.close();
    await Hive.close();

    Hive.init(hivePath);
    final sessao2 = await Hive.openBox('sessao');
    final cfg2 = await Hive.openBox('config');

    expect(sessao2.get('store_id'), lojaCanonica);
    expect(cfg2.get('store_id'), lojaCanonica);
    expect(cfg2.get('last_loja_id'), lojaCanonica);

    final sessionRead =
        await ProdutoSyncRecoverySessionService.listarHistorico();
    expect(sessionRead.length, 1);
    expect(sessionRead.first.storeIdAnterior, lojaSessao);
    expect(sessionRead.first.motivo, 'recuperacao_assistida');
  });

  test('reparo bloqueado sem permissão mantém sessão', () async {
    ProdutoSyncRecoveryAccess.debugForcePodeAcessar = false;
    final sessao = await Hive.openBox('sessao');
    await sessao.put('store_id', lojaSessao);

    final record =
        await ProdutoSyncRecoverySessionService.repararSessaoParaLojaCanonica(
      lojaCanonica: lojaCanonica,
    );
    expect(record, isNull);
    expect(sessao.get('store_id'), lojaSessao);
    expect(
      (await ProdutoSyncRecoverySessionService.listarHistorico()).isEmpty,
      isTrue,
    );
  });

  test('reparo bloqueado se owner não confirma loja', () async {
    ProdutoSyncRecoveryAccess.debugForcePodeAcessar = true;
    ProdutoSyncRecoveryAccess.debugForceCanonicalOwner = false;
    final sessao = await Hive.openBox('sessao');
    await sessao.put('store_id', lojaSessao);

    final record =
        await ProdutoSyncRecoverySessionService.repararSessaoParaLojaCanonica(
      lojaCanonica: lojaCanonica,
    );
    expect(record, isNull);
    expect(sessao.get('store_id'), lojaSessao);
  });
}
