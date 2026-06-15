// Mobile sem Hive local: pull de 2 parcelas remotas → tela lista pendentes.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-pull-parcelas-mobile';
  const vendaId = 'venda-pull-parcelas-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_pull_parc_');
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

  Future<void> seedParcelaRemota(
    FakeFirebaseFirestore firestore, {
    required int numero,
    required double valor,
    required DateTime vencimento,
  }) async {
    final docId = 'cr_${vendaId}_p$numero';
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
      'valorOriginal': valor,
      'valorPago': 0.0,
      'saldoAtual': valor,
      'valor': valor,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': numero,
      'parcelaTotal': 2,
      'dataVencimento': Timestamp.fromDate(vencimento),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 14)),
      'observacao': 'Parcela $numero/2',
      'historicoPagamentos': <Map<String, dynamic>>[],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 14, 12)),
    });
  }

  test('pull remoto popula Hive e listar pendentes exibe 2 parcelas', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    await seedParcelaRemota(
      firestore,
      numero: 1,
      valor: 25,
      vencimento: DateTime(2026, 7, 15),
    );
    await seedParcelaRemota(
      firestore,
      numero: 2,
      valor: 25,
      vencimento: DateTime(2026, 8, 14),
    );

    final crAntes = await ContaReceberService.openBoxLoja(lojaId);
    expect(crAntes, isEmpty);
    await crAntes.close();

    final pull = await ContaReceberService.sincronizarRemoto(lojaId);
    expect(pull.ignoradoJaEmExecucao, isFalse);
    expect(pull.importados + pull.atualizados, greaterThanOrEqualTo(2));

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(crBox.length, 2);

    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 2);
    expect(
      pendentes.fold<double>(0, (s, c) => s + c.valor),
      closeTo(50, 0.01),
    );
    expect(pendentes.every((c) => c.vendaIdFirebase == vendaId), isTrue);
    expect(pendentes.every((c) => !c.pago && c.valor >= 0.01), isTrue);

    await crBox.close();
  });

  test('pull não esconde parcelas pendentes por status/deletedAt', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    await seedParcelaRemota(
      firestore,
      numero: 1,
      valor: 40,
      vencimento: DateTime(2026, 7, 1),
    );

    await ContaReceberService.sincronizarRemoto(lojaId);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final todas = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'todas',
    );
    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(todas.length, 1);
    expect(pendentes.length, 1);
    expect(pendentes.first.valor, closeTo(40, 0.01));

    await crBox.close();
  });
}
