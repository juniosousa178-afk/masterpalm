// PC: sync completo não duplica parcelas legado+canônico na listagem.

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

  const lojaId = 'loja-pc-sync-sem-dup';
  const vendaId = 'venda-pc-sync-maio';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_pc_nodup_');
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

  test('sincronizarRemoto + listar não duplica legado e remoto canônico', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final box = await ContaReceberService.openBoxLoja(lojaId);
    final legacy = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Junio',
      valor: 40,
      valorOriginal: 40,
      dataVencimento: DateTime(2026, 5, 18),
      dataVenda: DateTime(2026, 5, 2),
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(legacy);
    await box.add(legacy);

    const docId = 'cr_${vendaId}_p1';
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Junio',
      'valorOriginal': 40,
      'valorPago': 0,
      'saldoAtual': 40,
      'valor': 40,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': DateTime(2026, 5, 18),
      'dataVenda': DateTime(2026, 5, 2),
      'historicoPagamentos': <Map<String, dynamic>>[],
      'cancelada': false,
      'schemaVersion': 1,
    });

    await ContaReceberService.sincronizarRemoto(lojaId);

    final qs = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .get();
    expect(qs.docs.length, 1);

    final pendentes = ContaReceberService.listar(
      contas: box.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 1);
    expect(pendentes.first.vendaIdFirebase, vendaId);
  });
}
