// Fluxo da tela: init abre box + sincronizarRemoto + listar pendentes.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

/// Replica o núcleo de [_ContasReceberScreenState._init] sem widget tree.
Future<List<ContaReceber>> simularContasReceberScreenInit(String lojaId) async {
  final box = await ContaReceberService.openBoxLoja(lojaId);
  await ContaReceberService.sincronizarRemoto(lojaId);
  return ContaReceberService.listar(
    contas: box.values,
    lojaId: lojaId,
    filtro: 'pendentes',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-screen-init';
  const vendaId = 'venda-screen-init-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_screen_init_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final crName = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(crName)) {
      await Hive.box<ContaReceber>(crName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(crName);
    } catch (_) {}
  });

  test('simulação init da tela puxa remoto e exibe parcelas pendentes', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    for (final n in [1, 2]) {
      final docId = 'cr_${vendaId}_p$n';
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.contasReceberCol)
          .doc(docId)
          .set({
        'lojaId': lojaId,
        'contaReceberId': docId,
        'vendaIdFirebase': vendaId,
        'clienteNome': 'Tela Init',
        'valorOriginal': 50.0,
        'valorPago': 0.0,
        'saldoAtual': 50.0,
        'valor': 50.0,
        'status': ContaReceberStatus.pendente,
        'pago': false,
        'parcelaNumero': n,
        'parcelaTotal': 2,
        'dataVencimento': Timestamp.fromDate(DateTime(2026, 7, n * 10)),
        'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 15)),
        'cancelada': false,
        'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 15, 12)),
      });
    }

    final pendentes = await simularContasReceberScreenInit(lojaId);
    expect(pendentes.length, 2);
    expect(
      pendentes.map((c) => c.parcelaNumero).toList()..sort(),
      [1, 2],
    );
  });
}
