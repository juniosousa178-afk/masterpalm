// Conta quitada/cancelada no Hive local não é republicada.

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
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-nao-republica-inativa';
  const vendaId = 'venda-maio-quitada';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_skip_pub_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final name = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(name)) await Hive.box<ContaReceber>(name).close();
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
  });

  test('conta paga de maio no Hive não republica para Firestore', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final box = await ContaReceberService.openBoxLoja(lojaId);
    final c = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente Maio',
      valor: 0,
      valorOriginal: 80,
      valorPago: 80,
      pago: true,
      status: ContaReceberStatus.paga,
      dataVencimento: DateTime(2026, 5, 15),
      dataVenda: DateTime(2026, 5, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(c);
    await box.add(c);

    final mig = await ContaReceberFirestoreService.publicarContasHivePendentes(lojaId);
    expect(mig.enviados, 0);

    final docId = 'cr_${vendaId}_p1';
    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isFalse);
  });
}
