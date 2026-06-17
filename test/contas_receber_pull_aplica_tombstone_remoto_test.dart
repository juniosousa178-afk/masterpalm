// Pull aplica tombstone de conta cancelada no Firestore → remove do Hive local.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-tombstone-pull';
  const vendaId = 'venda-tombstone-pull-uuid';
  const docId = 'cr_venda-tombstone-pull-uuid_p1';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_tomb_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final crName = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(crName)) await Hive.box<ContaReceber>(crName).close();
    try {
      await Hive.deleteBoxFromDisk(crName);
    } catch (_) {}
  });

  test('pull remove conta local quando remoto está cancelado', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Tombstone',
      'valorOriginal': 90.0,
      'valorPago': 0.0,
      'saldoAtual': 0.0,
      'valor': 0.0,
      'status': 'cancelada',
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
      'cancelada': true,
      'deletedAt': Timestamp.fromDate(DateTime(2026, 6, 16)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 16)),
    });

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Tombstone',
        valor: 90,
        valorOriginal: 90,
        dataVencimento: DateTime(2026, 8, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        idFirebase: docId,
        parcelaNumero: 1,
        parcelaTotal: 1,
      ),
    );
    expect(crBox.length, 1);

    await ContaReceberFirestoreService.pullContasReceberRemotas(lojaId);

    expect(crBox.length, 0);
    expect(
      ContaReceberService.listar(
        contas: crBox.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      ),
      isEmpty,
    );
    await crBox.close();
  });
}
