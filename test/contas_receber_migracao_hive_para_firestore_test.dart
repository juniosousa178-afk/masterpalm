// Migração Policy A: Hive-only → Firestore sem duplicar remoto existente.

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
  const lojaId = 'loja-cr-migr';
  const vendaId = 'venda-migr-uuid-001';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_migr_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  test('migrar publica Hive-only sem sobrescrever remoto existente', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

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
      'clienteNome': 'Remoto novo',
      'valorOriginal': 100.0,
      'valorPago': 0.0,
      'saldoAtual': 100.0,
      'valor': 100.0,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': DateTime(2026, 8, 1),
      'dataVenda': DateTime(2026, 6, 1),
      'historicoPagamentos': [],
      'cancelada': false,
      'schemaVersion': 1,
    });

    final box = await ContaReceberService.openBoxLoja(lojaId);
    await box.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Local velho',
        valor: 50,
        valorOriginal: 50,
        dataVencimento: DateTime(2026, 8, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );

    final mig = await ContaReceberFirestoreService
        .migrarLojaHiveParaFirestorePolicyA(lojaId);
    expect(mig.pulados, 1);
    expect(mig.enviados, 0);

    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.data()?['clienteNome'], 'Remoto novo');
    expect(snap.data()?['saldoAtual'], closeTo(100, 0.01));

    final mig2 = await ContaReceberFirestoreService
        .migrarLojaHiveParaFirestorePolicyA(lojaId);
    expect(mig2.enviados, 0);

    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await box.close();
    await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(lojaId));
  });

  test('migrar envia conta Hive-only quando remoto não existe', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    const loja2 = 'loja-cr-migr-nova';

    final box = await ContaReceberService.openBoxLoja(loja2);
    final c = ContaReceber(
      lojaId: loja2,
      clienteNome: 'Só Hive',
      valor: 90,
      dataVencimento: DateTime(2026, 9, 1),
      dataVenda: DateTime(2026, 6, 2),
      vendaIdFirebase: vendaId,
      parcelaNumero: 2,
    );
    await box.add(c);

    final mig = await ContaReceberFirestoreService
        .migrarLojaHiveParaFirestorePolicyA(loja2);
    expect(mig.enviados, 1);

    final docId = resolveContaReceberDocId(c);
    final snap = await firestore
        .collection('lojas')
        .doc(loja2)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isTrue);
    expect(c.idFirebase, docId);

    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await box.close();
    await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(loja2));
  });

  test('conta manual sem vendaIdFirebase publica com cr_legacy_ estável', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    const loja3 = 'loja-cr-migr-manual';

    final box = await ContaReceberService.openBoxLoja(loja3);
    final c = ContaReceber(
      lojaId: loja3,
      clienteNome: '  Maria Manual  ',
      valor: 45,
      valorOriginal: 45,
      dataVencimento: DateTime(2026, 10, 5),
      dataVenda: DateTime(2026, 6, 3),
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    await box.add(c);

    final docId = resolveContaReceberDocId(c);
    expect(docId.startsWith('cr_legacy_'), isTrue);

    final mig = await ContaReceberFirestoreService.publicarContasHivePendentes(loja3);
    expect(mig.enviados, 1);

    final snap = await firestore
        .collection('lojas')
        .doc(loja3)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()?['clienteNome'], contains('Maria'));

    final mig2 = await ContaReceberFirestoreService.publicarContasHivePendentes(loja3);
    expect(mig2.enviados, 0);
    expect(mig2.pulados, 1);

    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await box.close();
    await Hive.deleteBoxFromDisk(HiveBoxNames.contasReceber(loja3));
  });
}
