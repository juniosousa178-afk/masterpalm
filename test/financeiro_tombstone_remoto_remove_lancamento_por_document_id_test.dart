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
  const lojaId = 'loja-tombstone-id';
  const idRemoto = 'mp_cr2_doc__bx_id';
  const refRemota = 'mp_cr2_doc__bx_id';
  final data = DateTime(2026, 6, 18);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_tomb_id')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('tombstone remoto remove local quando id coincide mas chave Hive é int', () async {
    final firestore = FakeFirebaseFirestore();
    FinanceiroFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(idRemoto)
        .set({
      'lojaId': lojaId,
      'descricao': 'Recebimento — Id',
      'valor': 50.0,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'status': 'excluido',
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'referenciaExterna': refRemota,
      'dataLancamento': Timestamp.fromDate(data),
      'deletedAt': Timestamp.fromDate(DateTime(2026, 6, 18, 10)),
      'estornado': false,
    });

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      7,
      LancamentoFinanceiro(
        id: idRemoto,
        lojaId: lojaId,
        descricao: 'Recebimento — Id',
        valor: 50.0,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: refRemota,
      ),
    );

    final removidos =
        await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);

    expect(removidos, 1);
    expect(finBox.get(7), isNull);
    expect(finBox.length, 0);
  });
}
