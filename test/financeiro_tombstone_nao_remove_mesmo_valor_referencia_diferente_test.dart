import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  const lojaId = 'loja-tombstone-seguro';
  const idRemoto = 'mp_cr_21_1_9990_20260610';
  const refRemota = 'cr_receb:21:1:9990:20260610';
  const refLocalOutro = 'cr_receb:0:1:9990:20260609';
  final data = DateTime(2026, 6, 10);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_tomb_seg')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('não remove lançamento local com mesmo valor e referenciaExterna diferente', () async {
    final firestore = FakeFirebaseFirestore();
    FinanceiroFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(idRemoto)
        .set({
      'lojaId': lojaId,
      'descricao': 'Recebimento — Rafaela Abelha',
      'valor': 99.9,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'status': 'excluido',
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'referenciaExterna': refRemota,
      'dataLancamento': Timestamp.fromDate(data),
      'deletedAt': '2026-06-21T16:27:25.404Z',
      'estornado': false,
    });

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      'mp_cr_0_1_9990_20260609',
      LancamentoFinanceiro(
        id: 'mp_cr_0_1_9990_20260609',
        lojaId: lojaId,
        descricao: 'Recebimento — Rafaela Abelha',
        valor: 99.9,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: DateTime(2026, 6, 9),
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: refLocalOutro,
      ),
    );

    final removidos =
        await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);

    expect(removidos, 0);
    expect(finBox.length, 1);
    expect(finBox.get('mp_cr_0_1_9990_20260609'), isNotNull);
  });
}
