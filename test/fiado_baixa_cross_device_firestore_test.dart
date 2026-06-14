// Baixa cross-device via Firestore (desktop → mobile pull).

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
  const lojaId = 'loja-fiado-cross-fs';
  const vendaId = 'cross-venda-uuid-20260614';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cross_fs_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
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

  test('desktop baixa no Firestore e mobile pull vê saldo atualizado', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final docId = resolveContaReceberDocId(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Ana',
        valor: 120,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Ana',
      'valorOriginal': 120.0,
      'valorPago': 0.0,
      'saldoAtual': 120.0,
      'valor': 120.0,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
      'historicoPagamentos': [],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
    });

    // Sessão mobile: conta local stale com saldo cheio
    final box = await ContaReceberService.openBoxLoja(lojaId);
    await box.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Ana',
        valor: 120,
        valorOriginal: 120,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        idFirebase: docId,
      ),
    );

    // Sessão desktop: baixa remota
    final contaRemota = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Ana',
      valor: 120,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      idFirebase: docId,
    );
    final baixa = await ContaReceberFirestoreService.registrarBaixaRemota(
      lojaId: lojaId,
      conta: contaRemota,
      valorRecebido: 120,
      formaPagamento: 'Pix',
      dataRecebimento: DateTime(2026, 6, 14),
    );
    expect(baixa.sucesso, isTrue);

    // Mobile pull
    final pull = await ContaReceberFirestoreService.pullLojaFirestoreParaHive(
      lojaId,
      forcarMesmoSemTimestamp: true,
    );
    expect(pull.atualizados + pull.importados, greaterThanOrEqualTo(1));

    final local = box.values.firstWhere(
      (c) => c.vendaIdFirebase == vendaId,
    );
    expect(local.saldoRestante, closeTo(0, 0.01));
    expect(local.pago, isTrue);

    // Mobile tenta baixar de novo
    final key = local.key as int;
    final r = await ContaReceberService.registrarBaixa(
      conta: local,
      valorRecebido: 120,
      formaPagamento: 'Pix',
      lojaId: lojaId,
      contaHiveKey: key,
    );
    expect(r.sucesso, isFalse);
  });
}
