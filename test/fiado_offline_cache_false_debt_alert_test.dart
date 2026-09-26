// Fiado offline cache / false overdue alert — unit tests.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';

import 'package:master_palm/core/conta_receber_cache_authority.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'nathy-pratas-e-folheados-test';
  late String hivePath;
  late FakeFirebaseFirestore fakeFs;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_offline_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    fakeFs = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = fakeFs;
    ContaReceberAlertSessionGate.instance.debugReset();
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final name = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<ContaReceber>(name).clear();
      await Hive.box<ContaReceber>(name).close();
    }
  });

  ContaReceber staleOpen({
    required String docId,
    required String nome,
    required double valor,
  }) {
    return ContaReceber(
      lojaId: lojaId,
      clienteNome: nome,
      valor: valor,
      valorOriginal: valor,
      valorPago: 0,
      pago: false,
      status: ContaReceberStatus.pendente,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 7, 1),
      idFirebase: docId,
      historicoPagamentosJson: '[]',
    );
  }

  Future<void> seedRemotePaid({
    required String docId,
    required String nome,
    required double valor,
  }) async {
    await fakeFs
        .collection('lojas')
        .doc(lojaId)
        .collection('contas_receber')
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'clienteNome': nome,
      'status': ContaReceberStatus.paga,
      'pago': true,
      'saldoAtual': 0,
      'valor': 0,
      'valorOriginal': valor,
      'valorPago': valor,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'historicoPagamentos': [
        {
          'valor': valor,
          'data': '2026-09-13T20:00:00.000',
          'forma': 'Dinheiro',
          'baixaId': 'bx_$docId',
          'estornada': false,
        }
      ],
      'cancelada': false,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 9, 13)),
    });
  }

  test('Nathy fixture: online reconcile clears stale opens + watermark', () async {
    final fixtures = [
      ('cr_maria', 'maria nivalda', 105.80),
      ('cr_rosa1', 'Rosângela Cna', 176.80),
      ('cr_rosa2', 'Rosângela Cna', 164.70),
      ('cr_leti', 'Letícia Sousa', 74.96),
    ];
    final box = await ContaReceberService.openBoxLoja(lojaId);
    for (final f in fixtures) {
      await box.add(staleOpen(docId: f.$1, nome: f.$2, valor: f.$3));
      await seedRemotePaid(docId: f.$1, nome: f.$2, valor: f.$3);
    }
    expect(
      ContaReceberService.listar(
        contas: box.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      ).length,
      4,
    );

    final pull = await ContaReceberService.reconciliarCacheComRemoto(
      lojaId,
      forcar: true,
    );
    expect(pull.remoteRefreshOk, isTrue);

    final pendentes = ContaReceberService.listar(
      contas: box.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes, isEmpty); // ONLINE_RECONCILE_REMOVES_STALE_OPEN
    expect(
      box.values.where((c) => !c.pago && c.valor >= 0.01).length,
      0,
    ); // STALE_LOCAL_OPEN_AFTER_REMOTE_PAID_COUNT=0

    for (final c in box.values) {
      expect(c.remoteAuthorityConfirmed, isTrue);
      expect(c.remoteTerminalState, ContaReceberRemoteTerminalState.paid);
      expect(c.pago, isTrue);
    }

    // Offline restart simulation: decision must not debt-alert.
    final offlineDecision = decideContaReceberOverdueAlert(
      contas: box.values,
      lojaId: lojaId,
      remoteRefreshOk: false,
    );
    expect(offlineDecision.showDebtAlert, isFalse);
    expect(offlineDecision.vencidas, isEmpty);
    expect(offlineDecision.totalPendente, 0);
  });

  test('UNCERTAIN_CACHE_NO_FALSE_DEBT_ALERT', () {
    final stale = [
      staleOpen(docId: 'a', nome: 'maria nivalda', valor: 105.80),
      staleOpen(docId: 'b', nome: 'Rosângela Cna', valor: 176.80),
      staleOpen(docId: 'c', nome: 'Rosângela Cna', valor: 164.70),
      staleOpen(docId: 'd', nome: 'Letícia Sousa', valor: 74.96),
    ];
    final d = decideContaReceberOverdueAlert(
      contas: stale,
      lojaId: lojaId,
      remoteRefreshOk: false,
    );
    expect(d.showDebtAlert, isFalse);
    expect(d.showNeutralSyncWarning, isFalse);
    expect(d.totalPendente, 0);
  });

  test('REMOTE_UNAVAILABLE_UNCERTAIN_CACHE_NO_DIALOG', () {
    final stale = [
      staleOpen(docId: 'u1', nome: 'A', valor: 10),
      staleOpen(docId: 'u2', nome: 'B', valor: 20),
    ];
    final d = decideContaReceberOverdueAlert(
      contas: stale,
      lojaId: lojaId,
      remoteRefreshOk: false,
    );
    expect(d.showDebtAlert, isFalse);
    expect(d.showNeutralSyncWarning, isFalse);
  });

  test('STALE_PAID_CACHE_NO_DIALOG', () {
    final paid = staleOpen(docId: 'p1', nome: 'Paid', valor: 105.80);
    stampContaReceberRemoteAuthority(
      paid,
      terminalState: ContaReceberRemoteTerminalState.paid,
    );
    paid.pago = true;
    paid.valor = 0;
    final d = decideContaReceberOverdueAlert(
      contas: [paid],
      lojaId: lojaId,
      remoteRefreshOk: false,
    );
    expect(d.showDebtAlert, isFalse);
    expect(d.showNeutralSyncWarning, isFalse);
  });

  test('REMOTE_ZERO_OVERDUE_NO_DIALOG', () {
    final paid = staleOpen(docId: 'z1', nome: 'Z', valor: 0);
    paid.pago = true;
    stampContaReceberRemoteAuthority(
      paid,
      terminalState: ContaReceberRemoteTerminalState.paid,
    );
    final d = decideContaReceberOverdueAlert(
      contas: [paid],
      lojaId: lojaId,
      remoteRefreshOk: true,
    );
    expect(d.showDebtAlert, isFalse);
    expect(d.showNeutralSyncWarning, isFalse);
  });
  test('REMOTE_TERMINAL_WATERMARK_PRESERVED_OFFLINE blocks resurrect', () {
    final c = staleOpen(docId: 'x', nome: 'X', valor: 50);
    // Corrupt local open but watermark paid.
    stampContaReceberRemoteAuthority(
      c,
      terminalState: ContaReceberRemoteTerminalState.paid,
    );
    c.pago = false;
    c.valor = 50;
    c.status = ContaReceberStatus.pendente;

    expect(isRemoteTerminalWatermarkBlockingOpen(c), isTrue);
    expect(contaReceberVisibleInActiveReceivables(c), isFalse);

    final d = decideContaReceberOverdueAlert(
      contas: [c],
      lojaId: lojaId,
      remoteRefreshOk: false,
    );
    expect(d.showDebtAlert, isFalse);
  });

  test('REAL_OPEN_DEBT_ALERT with trusted watermark', () {
    final c = staleOpen(docId: 'open1', nome: 'Debtor', valor: 40);
    stampContaReceberRemoteAuthority(
      c,
      terminalState: ContaReceberRemoteTerminalState.open,
    );
    final d = decideContaReceberOverdueAlert(
      contas: [c],
      lojaId: lojaId,
      remoteRefreshOk: false,
    );
    expect(d.showDebtAlert, isTrue);
    expect(d.vencidas.length, 1);
  });

  test('SAME_ALERT_NOT_REPEATED_SESSION + SNOOZE', () {
    final gate = ContaReceberAlertSessionGate.instance;
    const fp = 'loja|a|10.00|1|0';
    expect(gate.shouldShowDebtAlert(fp), isTrue);
    gate.markDebtAlertShown(fp);
    expect(gate.shouldShowDebtAlert(fp), isFalse);

    gate.debugReset();
    expect(gate.shouldShowDebtAlert(fp), isTrue);
    gate.snoozeDebtAlert(fp);
    expect(gate.shouldShowDebtAlert(fp), isFalse);
  });

  test('PARTIAL_PAYMENT_REMAINS_OPEN_CORRECTLY', () {
    final c = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Partial',
      valor: 30,
      valorOriginal: 100,
      valorPago: 70,
      pago: false,
      status: ContaReceberStatus.parcial,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 7, 1),
      idFirebase: 'partial1',
    );
    stampContaReceberRemoteAuthority(
      c,
      terminalState: ContaReceberRemoteTerminalState.partial,
    );
    expect(contaReceberVisibleInActiveReceivables(c), isTrue);
    final d = decideContaReceberOverdueAlert(
      contas: [c],
      lojaId: lojaId,
      remoteRefreshOk: true,
    );
    expect(d.showDebtAlert, isTrue);
  });

  test('REMOTE_CANCELLED_BEATS_LOCAL_OPEN via watermark', () {
    final c = staleOpen(docId: 'can1', nome: 'C', valor: 10);
    stampContaReceberRemoteAuthority(
      c,
      terminalState: ContaReceberRemoteTerminalState.cancelled,
    );
    expect(contaReceberVisibleInActiveReceivables(c), isFalse);
  });

  test('TENANT_ISOLATION on alert decision', () {
    final c = staleOpen(docId: 't1', nome: 'T', valor: 10);
    c.lojaId = 'other-store';
    stampContaReceberRemoteAuthority(
      c,
      terminalState: ContaReceberRemoteTerminalState.open,
    );
    final d = decideContaReceberOverdueAlert(
      contas: [c],
      lojaId: lojaId,
      remoteRefreshOk: true,
    );
    expect(d.showDebtAlert, isFalse);
  });
}
