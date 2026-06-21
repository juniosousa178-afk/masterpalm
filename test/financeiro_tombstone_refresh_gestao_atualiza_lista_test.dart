import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_service.dart';

void main() {
  const lojaId = 'loja-tombstone-gestao';
  const idRedundante = 'mp_cr_21_1_9990_20260610';
  const refRedundante = 'cr_receb:21:1:9990:20260610';
  const idCanon = 'mp_cr_0_1_9990_20260609';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_tomb_gestao')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('fluxo gestão: tombstone remoto deixa um único R\$ 99,90 no resumo', () async {
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
      'deletedAt': '2026-06-21T16:27:25.404Z',
      'estornado': false,
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
        tipo: FinanceiroTipoLancamento.entradaExtra,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: DateTime(2026, 6, 10),
        dataPagamento: DateTime(2026, 6, 10),
        competenciaMes: 6,
        competenciaAno: 2026,
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
        tipo: FinanceiroTipoLancamento.entradaExtra,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: DateTime(2026, 6, 9),
        dataPagamento: DateTime(2026, 6, 9),
        competenciaMes: 6,
        competenciaAno: 2026,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: 'cr_receb:0:1:9990:20260609',
      ),
    );

    expect(
      finBox.values.where((l) => l.valor == 99.9).length,
      2,
    );

    await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);

    final ativos = finBox.values
        .where((l) => l.lojaId == lojaId && l.status == FinanceiroStatusLancamento.pago)
        .where((l) => (l.valor - 99.9).abs() < 0.01)
        .toList();
    expect(ativos.length, 1);
    expect(ativos.single.id, idCanon);

    final resumo = FinanceiroService.resumoMesCalendario(
      box: finBox,
      lojaId: lojaId,
      ano: 2026,
      mes: 6,
    );
    expect(resumo.totalEntradasExtras, closeTo(99.9, 0.01));
  });
}
