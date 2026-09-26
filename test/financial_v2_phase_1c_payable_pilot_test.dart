import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/v2/conta_pagar_remote_mirror.dart';
import 'package:master_palm/financeiro/v2/financial_v2_flags.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';

void main() {
  const pilot = 'nathy-pratas-e-folheados';
  const mir = 'mirjoias';
  late FakeFirebaseFirestore fake;

  ContaPagar conta({
    String store = pilot,
    String id = 'compraA_p1',
    String compraId = 'compraA',
    int parcela = 1,
    double valor = 80,
    String status = ContaPagarStatus.pendente,
    DateTime? atualizadoEm,
  }) {
    final criado = DateTime.utc(2026, 3, 1, 12);
    return ContaPagar(
      id: id,
      lojaId: store,
      fornecedorId: 3,
      fornecedorNome: 'Fornecedor',
      compraId: compraId,
      descricao: 'Parcela $parcela',
      valorTotalCompra: valor,
      valorParcela: valor,
      parcelaNumero: parcela,
      parcelaTotal: 2,
      dataVencimento: DateTime.utc(2026, 4, parcela),
      status: status,
      criadoEm: criado,
      atualizadoEm: atualizadoEm ?? criado,
      dataCompra: DateTime.utc(2026, 3, 1),
    );
  }

  setUp(() {
    fake = FakeFirebaseFirestore();
    ContaPagarRemoteMirrorService.debugFirestoreOverride = fake;
    ContaPagarRemoteMirrorService.debugEnabledOverride = null;
    ContaPagarRemoteMirrorService.debugPilotStoreIdOverride = pilot;
    ContaPagarRemoteMirrorService.debugWriteFault = null;
    ContaPagarRemoteMirrorService.debugResetDiagnostics();
  });

  tearDown(() {
    ContaPagarRemoteMirrorService.debugFirestoreOverride = null;
    ContaPagarRemoteMirrorService.debugEnabledOverride = null;
    ContaPagarRemoteMirrorService.debugPilotStoreIdOverride = null;
    ContaPagarRemoteMirrorService.debugWriteFault = null;
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

  Future<Map<String, dynamic>?> doc(String store, String id) async {
    final snap = await fake
        .collection('lojas')
        .doc(store)
        .collection('contas_pagar')
        .doc(id)
        .get();
    return snap.data();
  }

  Future<int> count(String store) async {
    final snap = await fake
        .collection('lojas')
        .doc(store)
        .collection('contas_pagar')
        .get();
    return snap.docs.length;
  }

  test('flag global permanece falsa e as outras também', () {
    expect(FinancialV2Flags.payablesRemoteMirrorEnabled, isFalse);
    expect(FinancialV2Flags.financialV2Enabled, isFalse);
    expect(FinancialV2Flags.financialLedgerEnabled, isFalse);
    expect(FinancialV2Flags.cashFlowEnabled, isFalse);
    expect(FinancialV2Flags.dreEnabled, isFalse);
    expect(FinancialV2Flags.financialAccountsEnabled, isFalse);
    expect(FinancialV2Flags.cardReceivablesEnabled, isFalse);
    expect(FinancialV2Flags.payablesRemoteMirrorPilotStoreId, pilot);
    expect(kPayableRemoteToLocalSyncEnabled, isFalse);
  });

  test('sem documento piloto a loja piloto não grava', () async {
    final result = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: conta(),
    );
    expect(result.kind, ContaPagarMirrorWriteKind.skippedFlagOff);
    expect(await count(pilot), 0);
    expect(
      ContaPagarRemoteMirrorService.debugDiagnostics,
      isEmpty,
    );
  });

  test('NON_PILOT_STORE_REMOTE_WRITES', () async {
    await armPilot();
    final result = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: mir,
      conta: conta(store: mir, id: 'mir_p1', compraId: 'mirCompra'),
    );
    expect(result.kind, ContaPagarMirrorWriteKind.skippedFlagOff);
    expect(await count(mir), 0);
    expect(await count(pilot), 0);
  });

  test('piloto ligado espelha uma vez e não duplica', () async {
    await armPilot();
    final created = conta();
    final first = await ContaPagarRemoteMirrorService.mirrorIfEnabled(
      storeId: pilot,
      conta: created,
    );
    final second = await ContaPagarRemoteMirrorService.mirrorIfEnabled(
      storeId: pilot,
      conta: created,
    );
    expect(first.kind, ContaPagarMirrorWriteKind.applied);
    expect(second.kind, ContaPagarMirrorWriteKind.noChange);
    expect(first.remoteId, created.id);
    expect(await count(pilot), 1);
    final remote = await doc(pilot, created.id);
    expect(remote?['mirrorOnly'], isTrue);
    expect(remote?['authoritative'], isFalse);
    expect(remote?['payableId'], created.id);
    expect(remote?['storeId'], pilot);
    final events = ContaPagarRemoteMirrorService.debugDiagnostics
        .map((e) => e.event)
        .toList();
    expect(events, contains('PAYABLE_MIRROR_ATTEMPT'));
    expect(events, contains('PAYABLE_MIRROR_SUCCESS'));
    expect(events, contains('PAYABLE_MIRROR_NO_CHANGE'));
  });

  test('OLDER_PENDING_CANNOT_REOPEN_PAID', () async {
    await armPilot();
    final paid = conta(
      status: ContaPagarStatus.pago,
      atualizadoEm: DateTime.utc(2026, 5, 2),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: pilot, conta: paid);
    final older = conta(
      status: ContaPagarStatus.pendente,
      atualizadoEm: DateTime.utc(2026, 3, 1),
    );
    final replay = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: older,
    );
    expect(replay.kind, ContaPagarMirrorWriteKind.rejectedTerminal);
    expect((await doc(pilot, paid.id))?['status'], ContaPagarStatus.pago);
  });

  test('OLDER_PENDING_CANNOT_REOPEN_CANCELLED', () async {
    await armPilot();
    final cancelled = conta(
      status: ContaPagarStatus.cancelado,
      atualizadoEm: DateTime.utc(2026, 5, 2),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: cancelled,
    );
    final replay = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: conta(atualizadoEm: DateTime.utc(2026, 3, 1)),
    );
    expect(replay.kind, ContaPagarMirrorWriteKind.rejectedTerminal);
    expect((await doc(pilot, cancelled.id))?['status'], ContaPagarStatus.cancelado);
  });

  test('OLDER_PAYLOAD_CANNOT_REMOVE_DELETED_AT', () async {
    await armPilot();
    final base = conta(atualizadoEm: DateTime.utc(2026, 5, 2));
    await ContaPagarRemoteMirrorService.mirrorSoftDelete(
      storeId: pilot,
      conta: base,
      deletedAt: DateTime.utc(2026, 5, 3),
    );
    final before = await doc(pilot, base.id);
    expect(before?['deletedAt'], isNotNull);
    final replay = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: conta(
        status: ContaPagarStatus.pendente,
        atualizadoEm: DateTime.utc(2026, 6, 1),
      ),
    );
    expect(replay.kind, ContaPagarMirrorWriteKind.rejectedTerminal);
    expect((await doc(pilot, base.id))?['deletedAt'], before?['deletedAt']);
    expect(await count(pilot), 1);
  });

  test('MIRROR_FAILURE_BREAKS_LOCAL_OPERATION false', () async {
    await armPilot();
    final local = <ContaPagar>[conta()];
    ContaPagarRemoteMirrorService.debugWriteFault = () async {
      throw StateError('firestore indisponível');
    };
    final result = await ContaPagarRemoteMirrorService.mirrorIfEnabled(
      storeId: pilot,
      conta: local.single,
    );
    expect(result.kind, ContaPagarMirrorWriteKind.failure);
    expect(local, hasLength(1));
    expect(await count(pilot), 0);
    expect(
      ContaPagarRemoteMirrorService.debugDiagnostics
          .map((e) => e.event),
      contains('PAYABLE_MIRROR_FAILURE'),
    );
  });

  test('comparador não cria local e soma só o que foi espelhado', () async {
    await armPilot();
    final mirrored = conta(valor: 40);
    final historical = conta(
      id: 'antiga_p1',
      compraId: 'antiga',
      valor: 999,
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: mirrored,
    );
    final local = [mirrored, historical];
    final report = await ContaPagarRemoteMirrorService.compare(
      storeId: pilot,
      local: local,
    );
    expect(local, hasLength(2));
    expect(report.matched, 1);
    expect(report.localOnly, 1);
    expect(report.countOf(PayableMirrorMismatchType.localNotMirrored), 1);
    expect(report.countOf(PayableMirrorMismatchType.fieldMismatch), 0);
    expect(report.localMirroredAmountSum, 40);
    expect(report.remoteMirroredAmountSum, 40);
    expect(report.purchaseInstallmentDuplicateCount, 0);
    expect(
      ContaPagarRemoteMirrorService.executeBootstrap,
      throwsA(isA<StateError>()),
    );
  });

  test('parcela de compra não duplica o documento', () async {
    await armPilot();
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: conta(id: 'compraZ_p1', compraId: 'compraZ', parcela: 1),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: conta(id: 'compraZ_p2', compraId: 'compraZ', parcela: 2),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: pilot,
      conta: conta(id: 'compraZ_p1', compraId: 'compraZ', parcela: 1),
    );
    final report = await ContaPagarRemoteMirrorService.compare(
      storeId: pilot,
      local: [
        conta(id: 'compraZ_p1', compraId: 'compraZ', parcela: 1),
        conta(id: 'compraZ_p2', compraId: 'compraZ', parcela: 2),
      ],
    );
    expect(await count(pilot), 2);
    expect(report.purchaseInstallmentDuplicateCount, 0);
    expect(report.matched, 2);
  });
}
