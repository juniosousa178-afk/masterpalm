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
  const lojaId = 'loja-tombstone-ref';
  const idRedundante = 'mp_cr_21_1_9990_20260610';
  const refRedundante = 'cr_receb:21:1:9990:20260610';
  const idCanon = 'mp_cr_0_1_9990_20260609';
  const refCanon = 'cr_receb:0:1:9990:20260609';
  final data = DateTime(2026, 6, 10);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_tomb_ref')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('tombstone remoto remove legado local por referenciaExterna exata', () async {
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
      'dataLancamento': Timestamp.fromDate(data),
      'deletedAt': Timestamp.fromDate(DateTime(2026, 6, 21, 16, 27)),
      'estornado': false,
      'motivoExclusao': 'exclusao_lancamento_duplicado_baixa_cr_auditoria_20260621',
    });

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();

    const hiveKeyLegado = 21;
    await finBox.put(
      hiveKeyLegado,
      LancamentoFinanceiro(
        id: idRedundante,
        lojaId: lojaId,
        descricao: 'Recebimento — Rafaela Abelha',
        valor: 99.9,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
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
        referenciaExterna: refCanon,
      ),
    );

    final removidos =
        await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);

    expect(removidos, 1);
    expect(finBox.get(hiveKeyLegado), isNull);
    expect(finBox.get(idCanon), isNotNull);
    expect(finBox.length, 1);
  });
}
