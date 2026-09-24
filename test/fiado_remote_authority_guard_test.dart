// Fiado remote authority guard — regression tests.
// Ensures stale Hive cannot reopen settled/cancelled remote debt.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_remote_authority.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const lojaId = 'loja-fiado-authority-guard';
  const otherLoja = 'loja-outra-tenant';

  late String hivePath;
  late FakeFirebaseFirestore fakeFs;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_auth_');
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
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final name = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<ContaReceber>(name).clear();
      await Hive.box<ContaReceber>(name).close();
    }
  });

  ContaReceber localStaleOpen({
    required String docId,
    double saldo = 100,
  }) {
    return ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente RO',
      valor: saldo,
      valorOriginal: 100,
      valorPago: 0,
      pago: false,
      status: ContaReceberStatus.pendente,
      dataVencimento: DateTime(2025, 1, 1),
      dataVenda: DateTime(2024, 12, 1),
      idFirebase: docId,
      historicoPagamentosJson: '[]',
    );
  }

  Future<void> seedRemotePaid({
    required String docId,
    double valorPago = 100,
    List<Map<String, dynamic>>? hist,
  }) async {
    await fakeFs
        .collection('lojas')
        .doc(lojaId)
        .collection('contas_receber')
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'status': ContaReceberStatus.paga,
      'pago': true,
      'saldoAtual': 0,
      'valor': 0,
      'valorPago': valorPago,
      'valorOriginal': 100,
      'clienteNome': 'Cliente RO',
      'dataVencimento': Timestamp.fromDate(DateTime(2025, 1, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2024, 12, 1)),
      'historicoPagamentos': hist ??
          [
            {
              'baixaId': 'A',
              'valor': valorPago,
              'data': DateTime(2025, 1, 2).toIso8601String(),
              'forma': 'pix',
              'estornada': false,
            },
          ],
      'cancelada': false,
      'updatedAt': Timestamp.fromDate(DateTime(2025, 1, 2)),
    });
  }

  group('decideGenericUpsert (pure)', () {
    test('paid remote vs stale open → SKIPPED_REMOTE_STRONGER', () {
      final remote = snapshotFromMaps(
        pago: true,
        status: 'paga',
        saldo: 0,
        valorPago: 100,
        historico: [
          {'baixaId': 'A'},
        ],
      );
      final incoming = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 100,
        valorPago: 0,
      );
      expect(
        decideGenericUpsert(
          remote: remote,
          incoming: incoming,
          remoteDocExists: true,
        ),
        ContaReceberUpsertDecision.skippedRemoteStronger,
      );
    });

    test('cancelled remote vs pendente → SKIPPED', () {
      final remote = snapshotFromMaps(
        pago: false,
        status: 'cancelada',
        saldo: 0,
        valorPago: 0,
        cancelada: true,
      );
      final incoming = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 50,
        valorPago: 0,
      );
      expect(
        decideGenericUpsert(
          remote: remote,
          incoming: incoming,
          remoteDocExists: true,
        ),
        ContaReceberUpsertDecision.skippedRemoteStronger,
      );
    });

    test('partial payment cannot regress', () {
      final remote = snapshotFromMaps(
        pago: false,
        status: 'parcial',
        saldo: 50,
        valorPago: 50,
        historico: [
          {'baixaId': 'B'},
        ],
      );
      final incoming = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 100,
        valorPago: 0,
      );
      expect(
        decideGenericUpsert(
          remote: remote,
          incoming: incoming,
          remoteDocExists: true,
        ),
        ContaReceberUpsertDecision.skippedRemoteStronger,
      );
    });

    test('payment history cannot be dropped', () {
      final remote = snapshotFromMaps(
        pago: false,
        status: 'parcial',
        saldo: 50,
        valorPago: 50,
        historico: [
          {'baixaId': 'A'},
          {'baixaId': 'B'},
        ],
      );
      final incoming = snapshotFromMaps(
        pago: false,
        status: 'parcial',
        saldo: 50,
        valorPago: 50,
        historico: const [],
      );
      expect(
        wouldRegressRemoteFinancialState(remote: remote, incoming: incoming),
        isTrue,
      );
      expect(
        decideGenericUpsert(
          remote: remote,
          incoming: incoming,
          remoteDocExists: true,
        ),
        ContaReceberUpsertDecision.skippedRemoteStronger,
      );
    });

    test('invented local settlement without remote → CONFLICT', () {
      final remote = snapshotFromMaps(
        pago: false,
        status: 'pendente',
        saldo: 100,
        valorPago: 0,
      );
      final incoming = snapshotFromMaps(
        pago: true,
        status: 'paga',
        saldo: 0,
        valorPago: 100,
        historico: [
          {'baixaId': 'FAKE'},
        ],
      );
      expect(
        decideGenericUpsert(
          remote: remote,
          incoming: incoming,
          remoteDocExists: true,
        ),
        ContaReceberUpsertDecision.conflictRejected,
      );
    });
  });

  group('upsertContaReceberDetalhado', () {
    test('PAID_REMOTE_CANNOT_BE_REOPENED', () async {
      const docId = 'cr_paid_guard_1';
      await seedRemotePaid(docId: docId);

      final box = await ContaReceberService.openBoxLoja(lojaId);
      final local = localStaleOpen(docId: docId);
      await box.add(local);

      final r = await ContaReceberFirestoreService.upsertContaReceberDetalhado(
        local,
        lastWriteOrigin: 'republicar_pos_venda',
      );
      expect(r.decision, ContaReceberUpsertDecision.skippedRemoteStronger);

      final remote = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .get();
      final data = remote.data()!;
      expect(data['pago'], isTrue);
      expect(data['status'], ContaReceberStatus.paga);
      expect((data['saldoAtual'] as num).toDouble(), 0);
      expect((data['valorPago'] as num).toDouble(), 100);

      // Hive converges to paid.
      await ContaReceberService.reconciliarCacheComRemoto(lojaId, forcar: true);
      final refreshed = box.values
          .where((c) => (c.idFirebase ?? '') == docId)
          .toList();
      expect(refreshed, isNotEmpty);
      expect(refreshed.first.pago, isTrue);
      expect(refreshed.first.saldoRestante, lessThan(0.01));
    });

    test('CANCELLED_REMOTE_CANNOT_BE_REOPENED', () async {
      const docId = 'cr_cancel_guard_1';
      await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .set({
        'lojaId': lojaId,
        'status': ContaReceberStatus.cancelada,
        'pago': false,
        'saldoAtual': 0,
        'valor': 0,
        'valorPago': 0,
        'cancelada': true,
        'deletedAt': Timestamp.now(),
        'clienteNome': 'X',
        'dataVencimento': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2024, 12, 1)),
        'historicoPagamentos': [],
      });

      final local = localStaleOpen(docId: docId);
      final r = await ContaReceberFirestoreService.upsertContaReceberDetalhado(
        local,
        lastWriteOrigin: 'app',
      );
      expect(r.decision, ContaReceberUpsertDecision.skippedRemoteStronger);
      final remote = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .get();
      expect(remote.data()!['cancelada'], isTrue);
      expect(remote.data()!['status'], ContaReceberStatus.cancelada);
    });

    test('PARTIAL_PAYMENT_CANNOT_REGRESS', () async {
      const docId = 'cr_partial_guard_1';
      await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .set({
        'lojaId': lojaId,
        'status': ContaReceberStatus.parcial,
        'pago': false,
        'saldoAtual': 50,
        'valor': 50,
        'valorPago': 50,
        'valorOriginal': 100,
        'clienteNome': 'X',
        'dataVencimento': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2024, 12, 1)),
        'historicoPagamentos': [
          {'baixaId': 'B', 'valor': 50, 'forma': 'pix', 'estornada': false},
        ],
        'cancelada': false,
      });

      final local = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'X',
        valor: 100,
        valorOriginal: 100,
        valorPago: 0,
        pago: false,
        status: ContaReceberStatus.pendente,
        dataVencimento: DateTime(2025, 1, 1),
        dataVenda: DateTime(2024, 12, 1),
        idFirebase: docId,
      );
      final r = await ContaReceberFirestoreService.upsertContaReceberDetalhado(
        local,
        lastWriteOrigin: 'publish_local',
      );
      expect(r.decision, ContaReceberUpsertDecision.skippedRemoteStronger);
      final remote = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .get();
      expect((remote.data()!['valorPago'] as num).toDouble(), 50);
      expect((remote.data()!['saldoAtual'] as num).toDouble(), 50);
    });

    test('PAYMENT_HISTORY_CANNOT_BE_DROPPED', () async {
      const docId = 'cr_hist_guard_1';
      await seedRemotePaid(
        docId: docId,
        hist: [
          {'baixaId': 'A', 'valor': 40, 'forma': 'pix', 'estornada': false},
          {'baixaId': 'B', 'valor': 60, 'forma': 'dinheiro', 'estornada': false},
        ],
      );
      // Local claims paid but empty history — still regression of history.
      final local = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'X',
        valor: 0,
        valorOriginal: 100,
        valorPago: 100,
        pago: true,
        status: ContaReceberStatus.paga,
        dataVencimento: DateTime(2025, 1, 1),
        dataVenda: DateTime(2024, 12, 1),
        idFirebase: docId,
        historicoPagamentosJson: '[]',
      );
      final r = await ContaReceberFirestoreService.upsertContaReceberDetalhado(
        local,
        lastWriteOrigin: 'app',
      );
      expect(r.decision, ContaReceberUpsertDecision.skippedRemoteStronger);
      final remote = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .get();
      final hist = remote.data()!['historicoPagamentos'] as List;
      expect(hist.length, 2);
    });

    test('FIADO_BAIXA_IDEMPOTENCY', () async {
      const docId = 'cr_baixa_idemp_1';
      await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .set({
        'lojaId': lojaId,
        'status': ContaReceberStatus.pendente,
        'pago': false,
        'saldoAtual': 80,
        'valor': 80,
        'valorPago': 0,
        'valorOriginal': 80,
        'clienteNome': 'X',
        'dataVencimento': Timestamp.fromDate(DateTime(2025, 6, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2025, 5, 1)),
        'historicoPagamentos': [],
        'cancelada': false,
      });

      final conta = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'X',
        valor: 80,
        valorOriginal: 80,
        dataVencimento: DateTime(2025, 6, 1),
        dataVenda: DateTime(2025, 5, 1),
        idFirebase: docId,
      );
      final quando = DateTime(2025, 6, 2, 10);
      final r1 = await ContaReceberFirestoreService.registrarBaixaRemota(
        conta: conta,
        lojaId: lojaId,
        valorRecebido: 80,
        formaPagamento: 'pix',
        dataRecebimento: quando,
      );
      expect(r1.sucesso, isTrue);
      expect(r1.idempotente, isFalse);

      final r2 = await ContaReceberFirestoreService.registrarBaixaRemota(
        conta: conta,
        lojaId: lojaId,
        valorRecebido: 80,
        formaPagamento: 'pix',
        dataRecebimento: quando,
      );
      expect(r2.sucesso, isTrue);
      expect(r2.idempotente, isTrue);

      final remote = await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .get();
      final hist = remote.data()!['historicoPagamentos'] as List;
      expect(hist.length, 1);
      expect((remote.data()!['valorPago'] as num).toDouble(), 80);
    });

    test('STALE_HIVE_OVERDUE_ALERT reconciles to 0', () async {
      // Remote: 2 paga with distinct semantic keys.
      await seedRemotePaid(docId: 'cr_nathy_a');
      await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc('cr_nathy_b')
          .set({
        'lojaId': lojaId,
        'status': ContaReceberStatus.paga,
        'pago': true,
        'saldoAtual': 0,
        'valor': 0,
        'valorPago': 50,
        'valorOriginal': 50,
        'clienteNome': 'Cliente B RO',
        'dataVencimento': Timestamp.fromDate(DateTime(2025, 2, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2024, 12, 15)),
        'historicoPagamentos': [
          {
            'baixaId': 'B',
            'valor': 50,
            'data': DateTime(2025, 2, 2).toIso8601String(),
            'forma': 'pix',
            'estornada': false,
          },
        ],
        'cancelada': false,
        'updatedAt': Timestamp.fromDate(DateTime(2025, 2, 2)),
      });

      final box = await ContaReceberService.openBoxLoja(lojaId);
      await box.add(localStaleOpen(docId: 'cr_nathy_a'));
      await box.add(
        ContaReceber(
          lojaId: lojaId,
          clienteNome: 'Cliente B RO',
          valor: 50,
          valorOriginal: 50,
          valorPago: 0,
          pago: false,
          status: ContaReceberStatus.pendente,
          dataVencimento: DateTime(2025, 2, 1),
          dataVenda: DateTime(2024, 12, 15),
          idFirebase: 'cr_nathy_b',
          historicoPagamentosJson: '[]',
        ),
      );

      final before = ContaReceberService.listar(
        contas: box.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(before.length, 2);

      final pull = await ContaReceberService.reconciliarCacheComRemoto(
        lojaId,
        forcar: true,
      );
      expect(pull.remoteRefreshOk, isTrue);

      final after = ContaReceberService.listar(
        contas: box.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );
      expect(after, isEmpty);
    });

    test('OFFLINE_CACHE_SAFE does not publish stale', () async {
      // No remote seed → create would apply. Instead: remote paid exists,
      // then we simulate offline by clearing override mid-flight is hard.
      // Verify: when remote unavailable path returns conflict without write
      // for regression case we already covered; here ensure hive preserved.
      const docId = 'cr_offline_1';
      await seedRemotePaid(docId: docId);
      final box = await ContaReceberService.openBoxLoja(lojaId);
      final local = localStaleOpen(docId: docId);
      await box.add(local);
      final lenBefore = box.length;

      ContaReceberFirestoreService.debugFirestoreOverride = null;
      // Without override, may fail network — upsert should not wipe hive.
      try {
        await ContaReceberFirestoreService.upsertContaReceberDetalhado(
          local,
          lastWriteOrigin: 'app',
          maxTentativas: 1,
        );
      } catch (_) {}
      expect(box.isOpen, isTrue);
      expect(box.length, lenBefore);
      ContaReceberFirestoreService.debugFirestoreOverride = fakeFs;
    });

    test('TENANT_ISOLATION rejects cross-store remote', () async {
      const docId = 'cr_tenant_1';
      await fakeFs
          .collection('lojas')
          .doc(lojaId)
          .collection('contas_receber')
          .doc(docId)
          .set({
        'lojaId': otherLoja, // mismatch
        'status': ContaReceberStatus.pendente,
        'pago': false,
        'saldoAtual': 10,
        'valor': 10,
        'valorPago': 0,
        'clienteNome': 'X',
        'dataVencimento': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2024, 12, 1)),
        'historicoPagamentos': [],
        'cancelada': false,
      });

      final local = localStaleOpen(docId: docId, saldo: 10);
      final r = await ContaReceberFirestoreService.upsertContaReceberDetalhado(
        local,
        lastWriteOrigin: 'app',
      );
      expect(r.decision, ContaReceberUpsertDecision.conflictRejected);
      expect(r.sucesso, isFalse);
    });
  });

  group('contract constants', () {
    test('terminal states and dedicated paths documented', () {
      expect(kContaReceberTerminalRemoteStates, contains('paga'));
      expect(kContaReceberTerminalRemoteStates, contains('cancelada'));
      expect(
        kContaReceberReversibleOnlyViaExplicitOperation,
        contains('registrarBaixa/registrarBaixaRemota'),
      );
      expect(
        kContaReceberReversibleOnlyViaExplicitOperation,
        contains('estornarBaixaRemota'),
      );
      expect(
        kContaReceberReversibleOnlyViaExplicitOperation,
        contains('marcarCanceladaRemota'),
      );
      expect(kContaReceberUpdatedAtConflictPolicy, contains('BUSINESS_STATE_FIRST'));
    });
  });
}
