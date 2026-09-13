// 040B3 — cliente usa backend confiável; sem reopen direto em produção.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  const lojaId = 'loja-fiado-040b3';
  const vendaId = 'venda-040b3-uuid';

  tearDown(() {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugTrustedRefundOverride = null;
  });

  test('callable de estorno não envia estado financeiro do cliente', () async {
    Map<String, dynamic>? seen;
    ContaReceberFirestoreService.debugTrustedRefundOverride = (data) async {
      seen = Map<String, dynamic>.from(data);
      return {'ok': true, 'idempotent': false};
    };

    final ok = await ContaReceberFirestoreService.estornarBaixaRemota(
      lojaId: lojaId,
      contaReceberDocId: 'cr_${vendaId}_p1',
      baixaId: 'bx-1',
    );
    expect(ok, isTrue);
    expect(seen, isNotNull);
    expect(seen!.keys.toSet(), {'lojaId', 'contaReceberId', 'baixaId'});
    expect(seen!.containsKey('saldo'), isFalse);
    expect(seen!.containsKey('pago'), isFalse);
    expect(seen!.containsKey('lastWriteOrigin'), isFalse);
    expect(seen!.containsKey('status'), isFalse);
  });

  test('override do callable falha de forma fechada', () async {
    ContaReceberFirestoreService.debugTrustedRefundOverride = (_) async {
      throw StateError('denied');
    };
    final ok = await ContaReceberFirestoreService.estornarBaixaRemota(
      lojaId: lojaId,
      contaReceberDocId: 'cr_${vendaId}_p1',
      baixaId: 'bx-1',
    );
    expect(ok, isFalse);
  });

  test('Fake FS aplica semântica Admin-like sem lastWriteOrigin de confiança',
      () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final c = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Ana',
      valor: 40,
      valorOriginal: 40,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );
    final docId = resolveContaReceberDocId(c);
    c.garantirDocIdFirestore(docId);
    await ContaReceberFirestoreService.upsertContaReceber(c);
    final data = DateTime(2026, 6, 12);
    await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: lojaId,
      conta: c,
      valorRecebido: 40,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    final bx = baixaIdDeterministico(
      contaReceberId: docId,
      valor: 40,
      dataRecebimento: data,
      formaPagamento: 'Pix',
    );

    final ok = await ContaReceberFirestoreService.estornarBaixaRemota(
      lojaId: lojaId,
      contaReceberDocId: docId,
      baixaId: bx,
    );
    expect(ok, isTrue);

    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.data()?['pago'], isFalse);
    expect(snap.data()?['saldoAtual'], closeTo(40, 0.01));
    expect(snap.data()?['lastWriteOrigin'], 'trusted_refund_fn');
  });

  test('entrada do callable confiável é a Function estornarBaixaContaReceber',
      () {
    expect(
      ContaReceberFirestoreService.trustedRefundCallableName,
      'estornarBaixaContaReceber',
    );
  });
}
