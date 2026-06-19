import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_exclusao_service.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  const lojaId = 'loja-cr-exc-tombstone';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_exc_tomb')).path);
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

  test('exclusão publica tombstone no Firestore', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Rafaela Abelha',
      valor: 85.50,
      valorOriginal: 85.50,
      dataVencimento: DateTime(2026, 7, 15),
      dataVenda: DateTime(2026, 6, 1),
      observacao:
          'Venda recuperada manualmente após perda durante edição',
    );
    normalizarContaReceberId(conta);
    final docId = resolveContaReceberDocId(conta);
    expect(docId, isNotEmpty);

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'clienteNome': conta.clienteNome,
      'valorOriginal': 85.50,
      'saldoAtual': 85.50,
      'valor': 85.50,
      'status': 'pendente',
      'pago': false,
      'dataVencimento': Timestamp.fromDate(conta.dataVencimento),
      'dataVenda': Timestamp.fromDate(conta.dataVenda),
      'observacao': conta.observacao,
    });

    final box = await ContaReceberService.openBoxLoja(lojaId);
    await box.add(conta..idFirebase = docId);

    final r =
        await ContaReceberExclusaoService.excluirContaReceberManualOuRecuperada(
      lojaId: lojaId,
      conta: conta,
    );
    expect(r.sucesso, isTrue);

    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.data()?['deletedAt'], isNotNull);
    expect(snap.data()?['cancelada'], isTrue);
    expect(snap.data()?['motivoCancelamento'], 'exclusao_recuperada_manual');
  });
}
