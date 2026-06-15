// Mobile pull: parcelas publicadas na loja operacional aparecem no box correto.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaAtiva = 'nathy-pratas-e-folheados';
  const lojaErrada = 'masterpalm26';
  const vendaId = 'venda-sync-cross-loja-ativa';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_sync_loja_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    for (final loja in [lojaAtiva, lojaErrada]) {
      final name = HiveBoxNames.contasReceber(loja);
      if (Hive.isBoxOpen(name)) {
        await Hive.box<ContaReceber>(name).close();
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('pull remoto preenche contas_receber_{lojaAtiva} e ignora loja root', () async {
    expect(
      LojaAtivaResolver.sessionStoreIfValid(
        storeIdFromSessao: lojaAtiva,
        storeIdFromConfig: lojaErrada,
        lastLojaIdFromConfig: lojaErrada,
        principalSessao: 'masterpalm26@gmail.com',
        authEmail: 'masterpalm26@gmail.com',
      ),
      lojaAtiva,
    );

    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final docId = 'cr_${vendaId}_p1';
    await firestore
        .collection('lojas')
        .doc(lojaAtiva)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaAtiva,
      'contaReceberId': docId,
      'clienteNome': 'Cliente Mobile',
      'valor': 120.0,
      'valorOriginal': 120.0,
      'valorPago': 0.0,
      'saldoAtual': 120.0,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 7, 10)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 14)),
      'vendaIdFirebase': vendaId,
      'parcelaNumero': 1,
      'parcelaTotal': 2,
      'historicoPagamentos': <Map<String, dynamic>>[],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 14, 12)),
    });

    final pullAtiva = await ContaReceberService.sincronizarRemoto(lojaAtiva);
    expect(pullAtiva.importados + pullAtiva.atualizados, greaterThan(0));

    final crBoxAtiva = await ContaReceberService.openBoxLoja(lojaAtiva);
    expect(
      crBoxAtiva.values.where((c) => c.vendaIdFirebase == vendaId).length,
      1,
    );
    await crBoxAtiva.close();

    final pullRoot = await ContaReceberService.sincronizarRemoto(lojaErrada);
    expect(pullRoot.importados + pullRoot.atualizados, 0);

    final crBoxRoot = await ContaReceberService.openBoxLoja(lojaErrada);
    expect(crBoxRoot.isEmpty, isTrue);
    await crBoxRoot.close();
  });
}
