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
  const lojaId = 'loja-tombstone-relatorio';
  const idRedundante = 'mp_cr_21_1_9990_20260610';
  const refRedundante = 'cr_receb:21:1:9990:20260610';
  const idCanon = 'mp_cr_0_1_9990_20260609';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_tomb_rel')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('fluxo relatório: pull + tombstone remove duplicado legado local', () async {
    final firestore = FakeFirebaseFirestore();
    FinanceiroFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(idRedundante)
        .set({
      'lojaId': lojaId,
      'descricao': 'Recebimento — Rafaela Abelha',
      'valor': 99.9,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'status': 'excluido',
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'referenciaExterna': refRedundante,
      'dataLancamento': Timestamp.fromDate(DateTime(2026, 6, 10)),
      'deletedAt': Timestamp.fromDate(DateTime(2026, 6, 21, 16, 27)),
      'estornado': false,
    });
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(idCanon)
        .set({
      'lojaId': lojaId,
      'descricao': 'Recebimento — Rafaela Abelha',
      'valor': 99.9,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'status': FinanceiroStatusLancamento.pago,
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'referenciaExterna': 'cr_receb:0:1:9990:20260609',
      'dataLancamento': Timestamp.fromDate(DateTime(2026, 6, 9)),
    });

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      21,
      LancamentoFinanceiro(
        id: idRedundante,
        lojaId: lojaId,
        descricao: 'Recebimento — Rafaela Abelha',
        valor: 99.9,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: DateTime(2026, 6, 10),
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: refRedundante,
      ),
    );
    await finBox.put(
      idCanon,
      LancamentoFinanceiro(
        id: idCanon,
        lojaId: lojaId,
        descricao: 'Recebimento — Rafaela Abelha',
        valor: 99.9,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: DateTime(2026, 6, 9),
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: 'cr_receb:0:1:9990:20260609',
      ),
    );

    await FinanceiroFirestoreService.pullLojaFirestoreParaHiveFase2d(lojaId);
    await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);

    final ativos9990 = finBox.values
        .where((l) => (l.valor - 99.9).abs() < 0.01)
        .where((l) => l.status == FinanceiroStatusLancamento.pago)
        .toList();
    expect(ativos9990.length, 1);
    expect(ativos9990.single.id, idCanon);
    expect(finBox.get(21), isNull);
  });
}
