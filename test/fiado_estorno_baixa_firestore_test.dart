// Estorno de baixa: Firestore + Hive.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  const lojaId = 'loja-estorno-fs';
  const vendaId = 'estorno-venda-fs';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_est_fs_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  test('estornarBaixaRemota reabre saldo no Firestore', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final c = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'João',
      valor: 100,
      valorOriginal: 100,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );
    final docId = resolveContaReceberDocId(c);
    c.garantirDocIdFirestore(docId);
    await ContaReceberFirestoreService.upsertContaReceber(c);

    final data = DateTime(2026, 6, 10);
    await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: lojaId,
      conta: c,
      valorRecebido: 100,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );

    final bx = baixaIdDeterministico(
      contaReceberId: docId,
      valor: 100,
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
    expect(snap.data()?['saldoAtual'], closeTo(100, 0.01));
    expect(snap.data()?['valorPago'], closeTo(0, 0.01));

    final hist = snap.data()?['historicoPagamentos'] as List;
    expect(hist.first['estornada'], isTrue);

    ContaReceberFirestoreService.debugFirestoreOverride = null;
  });

  test('estorno idempotente no Firestore não duplica saldo', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    const loja2 = 'loja-estorno-idem';

    final c = ContaReceber(
      lojaId: loja2,
      clienteNome: 'Maria',
      valor: 60,
      valorOriginal: 60,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );
    final docId = resolveContaReceberDocId(c);
    await ContaReceberFirestoreService.upsertContaReceber(c);
    final data = DateTime(2026, 6, 11);
    await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: loja2,
      conta: c,
      valorRecebido: 60,
      formaPagamento: 'Dinheiro',
      dataRecebimento: data,
    );
    final bx = baixaIdDeterministico(
      contaReceberId: docId,
      valor: 60,
      dataRecebimento: data,
      formaPagamento: 'Dinheiro',
    );

    await ContaReceberFirestoreService.estornarBaixaRemota(
      lojaId: loja2,
      contaReceberDocId: docId,
      baixaId: bx,
    );
    await ContaReceberFirestoreService.estornarBaixaRemota(
      lojaId: loja2,
      contaReceberDocId: docId,
      baixaId: bx,
    );

    final snap = await firestore
        .collection('lojas')
        .doc(loja2)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.data()?['saldoAtual'], closeTo(60, 0.01));

    ContaReceberFirestoreService.debugFirestoreOverride = null;
  });
}
