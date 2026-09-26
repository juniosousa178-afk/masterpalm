import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/client_build_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/v2/conta_pagar_remote_mirror.dart';
import 'package:master_palm/financeiro/v2/payable_mirror_diagnostic_store.dart';
import 'package:master_palm/models/compra_fornecedor.dart';
import 'package:master_palm/models/compra_fornecedor_constants.dart';
import 'package:master_palm/models/compra_fornecedor_item.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/compra_fornecedor_hive_store.dart';
import 'package:master_palm/services/conta_pagar_hive_store.dart';
import 'package:master_palm/services/conta_pagar_service.dart';

void main() {
  const pilot = 'nathy-pratas-e-folheados';
  const mir = 'mirjoias';
  const secret = 'SEGREDO-FORNECEDOR-XYZ';

  late Directory hiveDir;
  late FakeFirebaseFirestore fake;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_cp_mirror_1c1_');
    Hive.init(hiveDir.path);
    ContaPagarHiveStore.ensureAdapterRegistered();
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
    if (!Hive.isAdapterRegistered(32)) {
      Hive.registerAdapter(CompraFornecedorAdapter());
    }
    if (!Hive.isAdapterRegistered(33)) {
      Hive.registerAdapter(CompraFornecedorItemAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() {
    fake = FakeFirebaseFirestore();
    ContaPagarRemoteMirrorService.debugFirestoreOverride = fake;
    ContaPagarRemoteMirrorService.debugEnabledOverride = null;
    ContaPagarRemoteMirrorService.debugPilotStoreIdOverride = pilot;
    ContaPagarRemoteMirrorService.debugWriteFault = null;
    ContaPagarRemoteMirrorService.debugFlagReadFault = null;
    ContaPagarRemoteMirrorService.debugResetDiagnostics();
  });

  tearDown(() {
    ContaPagarRemoteMirrorService.debugFirestoreOverride = null;
    ContaPagarRemoteMirrorService.debugEnabledOverride = null;
    ContaPagarRemoteMirrorService.debugPilotStoreIdOverride = null;
    ContaPagarRemoteMirrorService.debugWriteFault = null;
    ContaPagarRemoteMirrorService.debugFlagReadFault = null;
    ContaPagarRemoteMirrorService.debugResetDiagnostics();
  });

  Future<void> armPilot() {
    return fake
        .collection('lojas')
        .doc(pilot)
        .collection(kPayablesPilotCollection)
        .doc(kPayablesPilotDocId)
        .set({
      'storeId': pilot,
      'payablesRemoteMirrorEnabled': true,
    });
  }

  Future<int> remoteCount(String store) async {
    final snap = await fake
        .collection('lojas')
        .doc(store)
        .collection('contas_pagar')
        .get();
    return snap.docs.length;
  }

  Future<void> seedCompra(String store, String compraId) async {
    final box = await CompraFornecedorHiveStore.openBox(store);
    await box!.put(
      compraId,
      CompraFornecedor(
        id: compraId,
        lojaId: store,
        fornecedorHiveKey: 1,
        fornecedorNome: secret,
        dataCompra: DateTime(2026, 3, 1),
        tipoCompra: CompraFornecedorTipo.financeira,
        valorInformado: 100,
        observacao: secret,
      ),
    );
  }

  ContaPagar pendente({
    required String store,
    required String id,
    String compraId = 'compra-1c1',
  }) {
    return ContaPagar(
      id: id,
      lojaId: store,
      fornecedorId: 1,
      fornecedorNome: secret,
      compraId: compraId,
      descricao: secret,
      valorTotalCompra: 100,
      valorParcela: 100,
      parcelaNumero: 1,
      parcelaTotal: 1,
      dataVencimento: DateTime(2026, 4, 10),
      dataCompra: DateTime(2026, 3, 1),
      observacao: secret,
      status: ContaPagarStatus.pendente,
    );
  }

  Future<List<PayableMirrorDiagnosticRecord>> events(String store) {
    return PayableMirrorDiagnosticStore.read(store);
  }

  test('GENERATE_INSTALLMENTS_MIRROR_HOOK_TEST_PASS', () async {
    await armPilot();
    await seedCompra(pilot, 'compra-ger');
    final compraBox = await CompraFornecedorHiveStore.openBox(pilot);
    final r = await ContaPagarService.gerarParcelasCompra(
      lojaId: pilot,
      compra: compraBox!.get('compra-ger')!,
      numeroParcelas: 1,
      primeiroVencimento: DateTime(2026, 5, 1),
    );
    expect(r.criadas, 1);
    expect(await remoteCount(pilot), 1);
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.action == PayableMirrorAction.createFromPurchase &&
          e.result == PayableMirrorDiagnosticResult.success),
      isTrue,
    );
  });

  test('SAVE_MIRROR_HOOK_TEST_PASS', () async {
    await armPilot();
    final box = await ContaPagarHiveStore.openBox(pilot);
    await ContaPagarService.salvar(
      box!,
      pendente(store: pilot, id: 'save-1'),
    );
    expect(await remoteCount(pilot), 1);
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.action == PayableMirrorAction.save &&
          e.result == PayableMirrorDiagnosticResult.success),
      isTrue,
    );
  });

  test('MARK_PAID_MIRROR_HOOK_TEST_PASS', () async {
    await armPilot();
    await seedCompra(pilot, 'compra-pay');
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'pay-1', compraId: 'compra-pay');
    await box!.put(conta.id, conta);
    final ok = await ContaPagarService.marcarComoPago(
      lojaId: pilot,
      conta: conta,
      formaPagamento: 'dinheiro',
    );
    expect(ok, isTrue);
    expect(await remoteCount(pilot), greaterThan(0));
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.action == PayableMirrorAction.markPaid &&
          e.result == PayableMirrorDiagnosticResult.success),
      isTrue,
    );
  });

  test('CANCEL_MIRROR_HOOK_TEST_PASS', () async {
    await armPilot();
    await seedCompra(pilot, 'compra-can');
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'can-1', compraId: 'compra-can');
    await box!.put(conta.id, conta);
    final r = await ContaPagarService.cancelar(lojaId: pilot, conta: conta);
    expect(r.contaCancelada, isTrue);
    expect(await remoteCount(pilot), greaterThan(0));
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.action == PayableMirrorAction.cancel &&
          e.result == PayableMirrorDiagnosticResult.success),
      isTrue,
    );
  });

  test('UPDATE_DUE_DATE_MIRROR_HOOK_TEST_PASS', () async {
    await armPilot();
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'due-1');
    await box!.put(conta.id, conta);
    final nova = DateTime(2026, 8, 15);
    await ContaPagarService.atualizarVencimento(
      lojaId: pilot,
      conta: conta,
      novaData: nova,
    );
    expect(box.get(conta.id)!.dataVencimento, nova);
    expect(await remoteCount(pilot), 1);
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.action == PayableMirrorAction.updateDueDate &&
          e.result == PayableMirrorDiagnosticResult.success),
      isTrue,
    );
  });

  test('NON_PILOT_REMOTE_WRITE_TEST_PASS', () async {
    await seedCompra(mir, 'compra-mir');
    final compraBox = await CompraFornecedorHiveStore.openBox(mir);
    await ContaPagarService.gerarParcelasCompra(
      lojaId: mir,
      compra: compraBox!.get('compra-mir')!,
      numeroParcelas: 1,
      primeiroVencimento: DateTime(2026, 5, 1),
    );
    final box = await ContaPagarHiveStore.openBox(mir);
    await ContaPagarService.salvar(box!, pendente(store: mir, id: 'mir-save'));
    final pay = pendente(store: mir, id: 'mir-pay', compraId: 'compra-mir');
    await box.put(pay.id, pay);
    expect(
      await ContaPagarService.marcarComoPago(
        lojaId: mir,
        conta: pay,
        formaPagamento: 'dinheiro',
      ),
      isTrue,
    );
    final can = pendente(store: mir, id: 'mir-can', compraId: 'compra-mir');
    await box.put(can.id, can);
    await ContaPagarService.cancelar(lojaId: mir, conta: can);
    final due = pendente(store: mir, id: 'mir-due');
    await box.put(due.id, due);
    await ContaPagarService.atualizarVencimento(
      lojaId: mir,
      conta: due,
      novaData: DateTime(2026, 9, 1),
    );
    expect(await remoteCount(mir), 0);
    expect(await remoteCount(pilot), 0);
    final log = await events(mir);
    final actions = log.map((e) => e.action).toSet();
    expect(actions, contains(PayableMirrorAction.createFromPurchase));
    expect(actions, contains(PayableMirrorAction.save));
    expect(actions, contains(PayableMirrorAction.markPaid));
    expect(actions, contains(PayableMirrorAction.cancel));
    expect(actions, contains(PayableMirrorAction.updateDueDate));
    expect(
      log.every((e) =>
          e.result == PayableMirrorDiagnosticResult.skippedStoreMismatch),
      isTrue,
    );
  });

  test('SUCCESS_DIAGNOSTIC_PERSISTED_TEST_PASS', () async {
    await armPilot();
    final box = await ContaPagarHiveStore.openBox(pilot);
    await ContaPagarService.salvar(
      box!,
      pendente(store: pilot, id: 'ok-1'),
    );
    final log = await events(pilot);
    final success = log.lastWhere(
      (e) => e.result == PayableMirrorDiagnosticResult.success,
    );
    expect(success.action, PayableMirrorAction.save);
    expect(success.storeId, pilot);
    expect(success.payableId, 'ok-1');
    expect(success.flagState, 'enabled');
  });

  test('FLAG_FALSE_DIAGNOSTIC_PERSISTED_TEST_PASS', () async {
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'flag-off');
    await box!.put(conta.id, conta);
    await ContaPagarService.atualizarVencimento(
      lojaId: pilot,
      conta: conta,
      novaData: DateTime(2026, 10, 1),
    );
    expect(await remoteCount(pilot), 0);
    expect(box.get(conta.id)!.dataVencimento, DateTime(2026, 10, 1));
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.result == PayableMirrorDiagnosticResult.flagReadAttempt &&
          e.flagState == 'missing'),
      isTrue,
    );
    expect(
      log.any((e) =>
          e.result == PayableMirrorDiagnosticResult.skippedFlagFalse &&
          e.action == PayableMirrorAction.updateDueDate),
      isTrue,
    );
  });

  test('FLAG_READ_FAILURE_DIAGNOSTIC_PERSISTED_TEST_PASS', () async {
    ContaPagarRemoteMirrorService.debugFlagReadFault = () async {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: secret,
      );
    };
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'flag-err');
    await box!.put(conta.id, conta);
    await ContaPagarService.atualizarVencimento(
      lojaId: pilot,
      conta: conta,
      novaData: DateTime(2026, 11, 2),
    );
    expect(box.get(conta.id)!.dataVencimento, DateTime(2026, 11, 2));
    expect(await remoteCount(pilot), 0);
    final log = await events(pilot);
    final failed = log.lastWhere(
      (e) => e.result == PayableMirrorDiagnosticResult.flagReadFailed,
    );
    expect(failed.flagState, 'read-error');
    expect(failed.errorCode, 'unavailable');
    expect(failed.action, PayableMirrorAction.updateDueDate);
  });

  test('PERMISSION_DENIED_DIAGNOSTIC_PERSISTED_TEST_PASS', () async {
    await armPilot();
    ContaPagarRemoteMirrorService.debugWriteFault = () async {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: secret,
      );
    };
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'denied-1');
    await box!.put(conta.id, conta);
    await ContaPagarService.atualizarVencimento(
      lojaId: pilot,
      conta: conta,
      novaData: DateTime(2026, 12, 3),
    );
    expect(box.get(conta.id)!.dataVencimento, DateTime(2026, 12, 3));
    expect(await remoteCount(pilot), 0);
    final log = await events(pilot);
    final denied = log.lastWhere(
      (e) => e.result == PayableMirrorDiagnosticResult.permissionDenied,
    );
    expect(denied.errorCode, 'permission-denied');
    expect(denied.result, isNot(PayableMirrorDiagnosticResult.success));
  });

  test('NETWORK_FAILURE_DIAGNOSTIC_PERSISTED_TEST_PASS', () async {
    await armPilot();
    ContaPagarRemoteMirrorService.debugWriteFault = () async {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
      );
    };
    final box = await ContaPagarHiveStore.openBox(pilot);
    final conta = pendente(store: pilot, id: 'net-1');
    await box!.put(conta.id, conta);
    await ContaPagarService.atualizarVencimento(
      lojaId: pilot,
      conta: conta,
      novaData: DateTime(2026, 12, 20),
    );
    expect(box.get(conta.id)!.dataVencimento, DateTime(2026, 12, 20));
    final log = await events(pilot);
    expect(
      log.any((e) =>
          e.result == PayableMirrorDiagnosticResult.networkFailure &&
          e.errorCode == 'deadline-exceeded'),
      isTrue,
    );
  });

  test('DIAGNOSTIC_SURVIVES_SERVICE_RECREATE_TEST_PASS', () async {
    await armPilot();
    final box = await ContaPagarHiveStore.openBox(pilot);
    await ContaPagarService.salvar(
      box!,
      pendente(store: pilot, id: 'survive-1'),
    );
    final name = HiveBoxNames.payableMirrorDiagnostics(pilot);
    await Hive.box(name).close();
    final log = await PayableMirrorDiagnosticStore.read(pilot);
    expect(
      log.any((e) =>
          e.payableId == 'survive-1' &&
          e.result == PayableMirrorDiagnosticResult.success),
      isTrue,
    );
  });

  test('DIAGNOSTIC_CONTAINS_BUILD_PROVENANCE_TEST_PASS', () async {
    await armPilot();
    final box = await ContaPagarHiveStore.openBox(pilot);
    await ContaPagarService.salvar(
      box!,
      pendente(store: pilot, id: 'prov-1'),
    );
    final text = await PayableMirrorDiagnosticStore.exportJson(pilot);
    expect(text, contains(kClientAppVersion));
    expect(text, contains(kClientBuildId));
    expect(text, contains(kClientGitCommit));
    expect(text, contains('"remoteDiagnosticWrites":0'));
    final log = await events(pilot);
    expect(log.last.buildId, kClientBuildId);
    expect(log.last.appVersion, kClientAppVersion);
    expect(log.last.gitCommit, kClientGitCommit);
  });

  test('DIAGNOSTIC_EXCLUDES_SENSITIVE_DESCRIPTION_TEST_PASS', () async {
    await armPilot();
    final box = await ContaPagarHiveStore.openBox(pilot);
    await ContaPagarService.salvar(
      box!,
      pendente(store: pilot, id: 'secret-1'),
    );
    final text = await PayableMirrorDiagnosticStore.exportJson(pilot);
    expect(text.contains(secret), isFalse);
    expect(text.contains('descricao'), isFalse);
    expect(text.contains('observacao'), isFalse);
    expect(text.contains('fornecedorNome'), isFalse);
  });
}
