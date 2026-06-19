import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-dup-tombstone';
  const idDuplicado = 'mp_cr2_doc__bx_tomb';
  const valor = 66.0;
  final data = DateTime(2026, 6, 16);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_tomb')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('exclusão de duplicado publica tombstone no Firestore', () async {
    final firestore = FakeFirebaseFirestore();
    FinanceiroFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(idDuplicado)
        .set({
      'lojaId': lojaId,
      'id': idDuplicado,
      'descricao': 'Recebimento — Tomb',
      'valor': valor,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'status': FinanceiroStatusLancamento.pago,
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'referenciaExterna': referenciaExternaContaReceberFirestore(
        contaReceberDocId: 'doc',
        baixaId: 'bx_tomb',
      ),
      'dataLancamento': Timestamp.fromDate(data),
    });

    const idCorreto = 'mp_cr2_venda-tomb_p1_6600_20260616';
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Tomb',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: 'cr_receb2:venda-tomb_p1:1:6600:20260616',
      ),
    );
    final dup = LancamentoFinanceiro(
      id: idDuplicado,
      lojaId: lojaId,
      descricao: 'Recebimento — Tomb',
      valor: valor,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberFirestore(
        contaReceberDocId: 'doc',
        baixaId: 'bx_tomb',
      ),
    );
    await finBox.put(idDuplicado, dup);

    final r =
        await FinanceiroLancamentoExclusaoService
            .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: dup,
      lancamentosLoja: finBox.values,
    );
    expect(r.sucesso, isTrue);
    expect(r.apenasLocal, isFalse);

    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(idDuplicado)
        .get();
    expect(snap.data()?['deletedAt'], isNotNull);
    expect(snap.data()?['status'], 'excluido');
    expect(snap.data()?['motivoExclusao'], 'exclusao_lancamento_duplicado_baixa_cr');
  });
}
