// Sync direto Hive ↔ Firestore para contas a receber.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-fs-sync';
  const vendaId = 'venda-uuid-cr-fs-001';

  late Directory hiveDir;
  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_cr_fs_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDownAll(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final name = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<ContaReceber>(name).close();
    }
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
  });

  ContaReceber contaFiada({double valor = 200}) {
    return ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente FS',
      valor: valor,
      valorOriginal: valor,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );
  }

  test('upsertContaReceber grava documento remoto com id estável', () async {
    final c = contaFiada();
    final ok = await ContaReceberFirestoreService.upsertContaReceber(c);
    expect(ok, isTrue);

    final docId = resolveContaReceberDocId(c);
    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()?['vendaIdFirebase'], vendaId);
    expect(snap.data()?['saldoAtual'], closeTo(200, 0.01));
  });

  test('pull atualiza Hive local a partir do Firestore', () async {
    final docId = 'cr_${vendaId}_p1';
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Remoto',
      'valorOriginal': 150.0,
      'valorPago': 50.0,
      'saldoAtual': 100.0,
      'valor': 100.0,
      'status': ContaReceberStatus.parcial,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 7, 10)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 5)),
      'observacao': 'Parcela',
      'historicoPagamentos': [
        {
          'baixaId': 'bx1',
          'valor': 50.0,
          'data': DateTime(2026, 6, 8).toIso8601String(),
          'forma': 'Pix',
          'estornada': false,
        },
      ],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 9)),
    });

    final pull = await ContaReceberFirestoreService.pullLojaFirestoreParaHive(lojaId);
    expect(pull.importados, 1);

    final box = await ContaReceberService.openBoxLoja(lojaId);
    expect(box.length, 1);
    final local = box.values.first;
    expect(local.clienteNome, 'Remoto');
    expect(local.saldoRestante, closeTo(100, 0.01));
    expect(local.idFirebase, docId);
  });

  test('registrarBaixaRemota é idempotente por baixaId', () async {
    final c = contaFiada(valor: 80);
    await ContaReceberFirestoreService.upsertContaReceber(c);
    final data = DateTime(2026, 6, 14);

    final r1 = await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: lojaId,
      conta: c,
      valorRecebido: 80,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    expect(r1.sucesso, isTrue);
    expect(r1.idempotente, isFalse);

    final r2 = await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: lojaId,
      conta: c,
      valorRecebido: 80,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    expect(r2.sucesso, isTrue);
    expect(r2.idempotente, isTrue);

    final docId = resolveContaReceberDocId(c);
    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    final hist = snap.data()?['historicoPagamentos'] as List;
    expect(hist.length, 1);
    expect(snap.data()?['saldoAtual'], closeTo(0, 0.01));
  });
}
