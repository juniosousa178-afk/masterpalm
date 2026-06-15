// Contas a receber: path Firestore e box Hive seguem loja operacional, não owner root.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaOperacional = 'nathy-pratas-e-folheados';
  const lojaRoot = 'masterpalm26';
  const vendaId = 'venda-loja-ativa-cr-test';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_loja_ativa_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    for (final loja in [lojaOperacional, lojaRoot]) {
      final name = HiveBoxNames.contasReceber(loja);
      if (Hive.isBoxOpen(name)) {
        await Hive.box<ContaReceber>(name).close();
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('sessão Nathy vence owner masterpalm26 na validação pura', () {
    final id = LojaAtivaResolver.sessionStoreIfValid(
      storeIdFromSessao: lojaOperacional,
      storeIdFromConfig: lojaRoot,
      lastLojaIdFromConfig: lojaRoot,
      principalSessao: 'masterpalm26@gmail.com',
      authEmail: 'masterpalm26@gmail.com',
    );
    expect(id, lojaOperacional);
    expect(id, isNot(lojaRoot));
  });

  test('upsert grava em lojas/nathy/... e não em lojas/masterpalm26/...', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final crBox = await ContaReceberService.openBoxLoja(lojaOperacional);
    expect(crBox.name, HiveBoxNames.contasReceber(lojaOperacional));

    final conta = ContaReceber(
      lojaId: lojaOperacional,
      clienteNome: 'Cliente Nathy',
      valor: 50,
      valorOriginal: 50,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 14),
      vendaKey: 1,
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    await crBox.add(conta);
    normalizarContaReceberId(conta);

    final ok = await ContaReceberFirestoreService.upsertContaReceber(
      conta,
      lastWriteOrigin: 'venda_fiada',
    );
    expect(ok, isTrue);

    final docId = 'cr_${vendaId}_p1';
    final snapNathy = await firestore
        .collection('lojas')
        .doc(lojaOperacional)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snapNathy.exists, isTrue);
    expect(snapNathy.data()?['lojaId'], lojaOperacional);

    final snapRoot = await firestore
        .collection('lojas')
        .doc(lojaRoot)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snapRoot.exists, isFalse);

    await crBox.close();
  });
}
