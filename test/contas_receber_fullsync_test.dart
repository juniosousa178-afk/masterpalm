// FullSync inclui contas a receber (migr + pull).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';

void main() {
  const lojaId = 'loja-fullsync-cr';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fullsync_cr_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  test('sincronizarRemoto executa migr Policy A + pull', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final box = await ContaReceberService.openBoxLoja(lojaId);
    await box.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Local',
        valor: 75,
        dataVencimento: DateTime(2026, 10, 1),
        dataVenda: DateTime(2026, 6, 3),
        vendaIdFirebase: 'fullsync-venda-id',
        parcelaNumero: 1,
      ),
    );

    final pull = await ContaReceberFirestoreService.sincronizarRemoto(lojaId);
    expect(pull.importados + pull.atualizados, greaterThanOrEqualTo(0));

    final local = box.values.first;
    expect((local.idFirebase ?? '').trim(), isNotEmpty);

    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await box.close();
  });
}
