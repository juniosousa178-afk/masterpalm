// PC publica cr_{vendaId}_p1 e cr_{vendaId}_p2 ao finalizar venda fiada parcelada.

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

  const lojaId = 'loja-fiado-parcelado-publica-fs';
  const vendaId = 'venda-parcelada-publica-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_parc_pub_');
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

  test('upsert de 2 parcelas locais grava cr_{vendaId}_p1 e p2 no Firestore', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final contas = <ContaReceber>[
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente PC',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 7, 15),
        dataVenda: DateTime(2026, 6, 14),
        vendaKey: 1,
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        parcelaTotal: 2,
      ),
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente PC',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 8, 14),
        dataVenda: DateTime(2026, 6, 14),
        vendaKey: 1,
        vendaIdFirebase: vendaId,
        parcelaNumero: 2,
        parcelaTotal: 2,
      ),
    ];

    for (final conta in contas) {
      await crBox.add(conta);
      normalizarContaReceberId(conta);
      final ok = await ContaReceberFirestoreService.upsertContaReceber(
        conta,
        lastWriteOrigin: 'venda_fiada',
      );
      expect(ok, isTrue);
    }

    for (var n = 1; n <= 2; n++) {
      final docId = 'cr_${vendaId}_p$n';
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.contasReceberCol)
          .doc(docId)
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()?['vendaIdFirebase'], vendaId);
      expect(snap.data()?['contaReceberId'], docId);
      expect(snap.data()?['parcelaNumero'], n);
      expect(snap.data()?['parcelaTotal'], 2);
      expect(snap.data()?['lojaId'], lojaId);
    }

    await crBox.close();
  });

  test('publicarContasHivePendentes republica parcelas ainda ausentes no remoto', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente PC',
        valor: 75,
        valorOriginal: 75,
        dataVencimento: DateTime(2026, 7, 20),
        dataVenda: DateTime(2026, 6, 14),
        vendaKey: 2,
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        parcelaTotal: 2,
      ),
    );

    final docId = 'cr_${vendaId}_p1';
    expect(
      (await firestore
              .collection('lojas')
              .doc(lojaId)
              .collection(FSPaths.contasReceberCol)
              .doc(docId)
              .get())
          .exists,
      isFalse,
    );

    final mig =
        await ContaReceberFirestoreService.publicarContasHivePendentes(lojaId);
    expect(mig.enviados, greaterThanOrEqualTo(1));

    final depois = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(depois.exists, isTrue);

    await crBox.close();
  });
}
