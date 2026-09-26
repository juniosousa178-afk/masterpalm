import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/v2/conta_pagar_remote_mirror.dart';
import 'package:master_palm/financeiro/v2/financial_v2_flags.dart';
import 'package:master_palm/models/conta_pagar.dart';
import 'package:master_palm/models/conta_pagar_constants.dart';

void main() {
  const nathy = 'nathy-pratas';
  const mir = 'mir-joias';
  late FakeFirebaseFirestore fake;

  ContaPagar conta({
    String store = nathy,
    String id = 'compraA_p1',
    String compraId = 'compraA',
    int parcela = 1,
    double valor = 100,
    String status = ContaPagarStatus.pendente,
    DateTime? atualizadoEm,
    DateTime? dataPagamento,
    String forma = '',
    String observacao = '',
  }) {
    final criado = DateTime.utc(2026, 3, 1, 12);
    return ContaPagar(
      id: id,
      lojaId: store,
      fornecedorId: 7,
      fornecedorNome: 'Fornecedor',
      compraId: compraId,
      descricao: 'Parcela $parcela',
      valorTotalCompra: valor,
      valorParcela: valor,
      parcelaNumero: parcela,
      parcelaTotal: 2,
      dataVencimento: DateTime.utc(2026, 4, parcela),
      dataPagamento: dataPagamento,
      status: status,
      formaPagamento: forma,
      observacao: observacao,
      criadoEm: criado,
      atualizadoEm: atualizadoEm ?? criado,
      dataCompra: DateTime.utc(2026, 3, 1),
    );
  }

  setUp(() {
    fake = FakeFirebaseFirestore();
    ContaPagarRemoteMirrorService.debugFirestoreOverride = fake;
    ContaPagarRemoteMirrorService.debugEnabledOverride = true;
  });

  tearDown(() {
    ContaPagarRemoteMirrorService.debugFirestoreOverride = null;
    ContaPagarRemoteMirrorService.debugEnabledOverride = null;
  });

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

  test('PAYABLE_MIRROR_IDEMPOTENT_TEST_PASS', () async {
    final c = conta();
    final first = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: c,
    );
    final second = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: c,
    );
    expect(first.kind, ContaPagarMirrorWriteKind.applied);
    expect(second.kind, ContaPagarMirrorWriteKind.noChange);
    expect(await count(nathy), 1);
    expect((await doc(nathy, 'compraA_p1'))!['mirrorRevision'], 1);
    expect(payableRemoteDocId(c.id), c.id);
  });

  test('PAYABLE_CREATE_MIRROR_TEST_PASS', () async {
    final c = conta();
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: c);
    final data = (await doc(nathy, c.id))!;
    expect(data['storeId'], nathy);
    expect(data['payableId'], c.id);
    expect(data['source'], kContaPagarMirrorSource);
    expect(data['schemaVersion'], 1);
    expect(data['mirrorOnly'], isTrue);
    expect(data['authoritative'], isFalse);
    expect(data['mirroredAt'], isNotNull);
    expect(data['status'], ContaPagarStatus.pendente);
    expect(data['valorParcela'], 100);
    expect(data['compraId'], 'compraA');
    expect(data['parcelaNumero'], 1);
  });

  test('PAYABLE_UPDATE_MIRROR_TEST_PASS', () async {
    final c = conta();
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: c);
    final edited = c.copyWith(
      observacao: 'ajuste',
      atualizadoEm: DateTime.utc(2026, 3, 2, 12),
    );
    final result = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: edited,
    );
    expect(result.kind, ContaPagarMirrorWriteKind.applied);
    final data = (await doc(nathy, c.id))!;
    expect(data['observacao'], 'ajuste');
    expect(data['mirrorRevision'], 2);
    expect(await count(nathy), 1);
  });

  test('PAYABLE_PAID_MIRROR_TEST_PASS', () async {
    final paga = conta(
      status: ContaPagarStatus.pago,
      dataPagamento: DateTime.utc(2026, 3, 5),
      forma: 'Pix',
      atualizadoEm: DateTime.utc(2026, 3, 5),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: paga,
    );
    final data = (await doc(nathy, paga.id))!;
    expect(data['status'], ContaPagarStatus.pago);
    expect(data['formaPagamento'], 'Pix');
    expect(data['dataPagamento'], isNotNull);
    final lancamentos = await fake
        .collection('lojas')
        .doc(nathy)
        .collection('lancamentos_financeiros')
        .get();
    expect(lancamentos.docs, isEmpty);
  });

  test('PAYABLE_CANCELLED_MIRROR_TEST_PASS', () async {
    final c = conta();
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: c);
    final cancelada = c.copyWith(
      status: ContaPagarStatus.cancelado,
      atualizadoEm: DateTime.utc(2026, 3, 6),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: cancelada,
    );
    final data = (await doc(nathy, c.id))!;
    expect(data['status'], ContaPagarStatus.cancelado);
    expect(data['deletedAt'], isNull);
    expect(await count(nathy), 1);
  });

  test('PAYABLE_SOFT_DELETE_MIRROR_TEST_PASS', () async {
    final c = conta();
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: c);
    final deleted = await ContaPagarRemoteMirrorService.mirrorSoftDelete(
      storeId: nathy,
      conta: c,
      deletedAt: DateTime.utc(2026, 3, 7),
    );
    final again = await ContaPagarRemoteMirrorService.mirrorSoftDelete(
      storeId: nathy,
      conta: c,
      deletedAt: DateTime.utc(2026, 3, 8),
    );
    expect(deleted.kind, ContaPagarMirrorWriteKind.applied);
    expect(again.kind, ContaPagarMirrorWriteKind.noChange);
    final data = (await doc(nathy, c.id))!;
    expect(data['deletedAt'], isNotNull);
    expect(data['status'], ContaPagarStatus.pendente);
    expect(await count(nathy), 1);
  });

  test('OLDER_PAYLOAD_CANNOT_REOPEN_PAID_TEST_PASS', () async {
    final paga = conta(
      status: ContaPagarStatus.pago,
      dataPagamento: DateTime.utc(2026, 3, 5),
      atualizadoEm: DateTime.utc(2026, 3, 5),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: paga,
    );
    final reabre = conta(
      status: ContaPagarStatus.pendente,
      atualizadoEm: DateTime.utc(2026, 3, 9),
    );
    final result = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: reabre,
    );
    expect(result.kind, ContaPagarMirrorWriteKind.rejectedTerminal);
    expect((await doc(nathy, paga.id))!['status'], ContaPagarStatus.pago);
  });

  test('OLDER_PAYLOAD_CANNOT_REOPEN_CANCELLED_TEST_PASS', () async {
    final cancelada = conta(
      status: ContaPagarStatus.cancelado,
      atualizadoEm: DateTime.utc(2026, 3, 6),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: cancelada,
    );
    final result = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: conta(atualizadoEm: DateTime.utc(2026, 3, 10)),
    );
    expect(result.kind, ContaPagarMirrorWriteKind.rejectedTerminal);
    expect(
      (await doc(nathy, cancelada.id))!['status'],
      ContaPagarStatus.cancelado,
    );
  });

  test('PURCHASE_INSTALLMENT_MIRROR_NO_DUPLICATE_TEST_PASS', () async {
    final p1 = conta(id: 'compraA_p1', parcela: 1, valor: 50);
    final p2 = conta(id: 'compraA_p2', parcela: 2, valor: 50);
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: p1);
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: p2);
    final again = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: p1,
    );
    expect(again.kind, ContaPagarMirrorWriteKind.noChange);
    expect(await count(nathy), 2);
    expect(payableRemoteDocId(p1.id), 'compraA_p1');
    expect(payableRemoteDocId(p2.id), 'compraA_p2');
  });

  test('FLAG_FALSE_REMOTE_WRITES_TEST_PASS', () async {
    expect(FinancialV2Flags.payablesRemoteMirrorEnabled, isFalse);
    ContaPagarRemoteMirrorService.debugEnabledOverride = false;
    final c = conta();
    final upsert = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: c,
    );
    final soft = await ContaPagarRemoteMirrorService.mirrorSoftDelete(
      storeId: nathy,
      conta: c,
    );
    final hooked = await ContaPagarRemoteMirrorService.mirrorIfEnabled(
      storeId: nathy,
      conta: c,
    );
    expect(upsert.kind, ContaPagarMirrorWriteKind.skippedFlagOff);
    expect(soft.kind, ContaPagarMirrorWriteKind.skippedFlagOff);
    expect(hooked.kind, ContaPagarMirrorWriteKind.skippedFlagOff);
    expect(upsert.wrote, isFalse);
    expect(await count(nathy), 0);
  });

  test('SHADOW_COMPARE_MATCH_TEST_PASS', () async {
    final c = conta();
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: c);
    final report = await ContaPagarRemoteMirrorService.compare(
      storeId: nathy,
      local: [c],
    );
    expect(report.total, 1);
    expect(report.matched, 1);
    expect(report.mismatched, 0);
    expect(report.rows.single.match, isTrue);
    expect(report.rows.single.localId, c.id);
    expect(report.rows.single.remoteId, c.id);
    expect(report.rows.single.localAmount, report.rows.single.remoteAmount);
  });

  test('SHADOW_COMPARE_MISMATCH_TEST_PASS', () async {
    final c = conta();
    await ContaPagarRemoteMirrorService.mirrorUpsert(storeId: nathy, conta: c);
    final divergente = c.copyWith(
      valorParcela: 25,
      atualizadoEm: DateTime.utc(2026, 3, 4),
    );
    final report = await ContaPagarRemoteMirrorService.compare(
      storeId: nathy,
      local: [divergente],
    );
    expect(report.matched, 0);
    expect(report.mismatched, 1);
    expect(report.rows.single.match, isFalse);
    expect(
      report.rows.single.mismatchType,
      PayableMirrorMismatchType.localNewer,
    );
    expect((await doc(nathy, c.id))!['valorParcela'], 100);
    expect(divergente.valorParcela, 25);
  });

  test('REMOTE_ONLY_DOES_NOT_CREATE_LOCAL_TEST_PASS', () async {
    await fake.collection('lojas').doc(nathy).collection('contas_pagar').doc('so-remoto').set({
      'storeId': nathy,
      'payableId': 'so-remoto',
      'lojaId': nathy,
      'status': ContaPagarStatus.pendente,
      'valorParcela': 15,
      'dataVencimento': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
    });
    final locais = <ContaPagar>[];
    final report = await ContaPagarRemoteMirrorService.compare(
      storeId: nathy,
      local: locais,
    );
    expect(report.remoteOnly, 1);
    expect(report.rows.single.mismatchType, PayableMirrorMismatchType.remoteOnly);
    expect(locais, isEmpty);
  });

  test('LOCAL_ONLY_DOES_NOT_AUTO_DELETE_TEST_PASS', () async {
    final c = conta();
    final locais = [c];
    final report = await ContaPagarRemoteMirrorService.compare(
      storeId: nathy,
      local: locais,
    );
    expect(report.localOnly, 1);
    expect(
      report.rows.single.mismatchType,
      PayableMirrorMismatchType.localNotMirrored,
    );
    expect(locais, hasLength(1));
    expect(locais.single.status, ContaPagarStatus.pendente);
    expect(await count(nathy), 0);
  });

  test('TENANT_ISOLATION_TEST_PASS', () async {
    final daMir = conta(store: mir, id: 'compraB_p1', compraId: 'compraB');
    final cruzado = await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: daMir,
    );
    expect(cruzado.kind, ContaPagarMirrorWriteKind.rejectedTenant);
    expect(await count(nathy), 0);
    expect(await count(mir), 0);

    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: nathy,
      conta: conta(),
    );
    await ContaPagarRemoteMirrorService.mirrorUpsert(
      storeId: mir,
      conta: daMir,
    );
    final nathyReport = await ContaPagarRemoteMirrorService.compare(
      storeId: nathy,
      local: [conta(), daMir],
    );
    expect(nathyReport.matched, 1);
    expect(nathyReport.total, 1);
    expect(nathyReport.rows.every((r) => r.localId != 'compraB_p1'), isTrue);
  });

  test('bootstrap preview não grava', () async {
    final preview = ContaPagarRemoteMirrorService.preview(
      storeId: nathy,
      local: [conta(), conta(store: mir, id: 'x', compraId: 'x')],
    );
    expect(preview.count, 1);
    expect(preview.amountSum, 100);
    expect(preview.remoteIds, ['compraA_p1']);
    expect(preview.writesPerformed, isFalse);
    expect(await count(nathy), 0);
    expect(
      ContaPagarRemoteMirrorService.executeBootstrap,
      throwsA(isA<StateError>()),
    );
  });
}
