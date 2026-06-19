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
  const lojaId = 'loja-dup-sync';
  const idDuplicado = 'mp_cr2_sync-doc__bx_sync';
  const valor = 12.0;
  final data = DateTime(2026, 6, 17);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_sync')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('duplicado excluído não volta após pull/sync', () async {
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
      'descricao': 'Recebimento — Sync',
      'valor': valor,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'status': FinanceiroStatusLancamento.pago,
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'referenciaExterna': referenciaExternaContaReceberFirestore(
        contaReceberDocId: 'sync-doc',
        baixaId: 'bx_sync',
      ),
      'dataLancamento': Timestamp.fromDate(data),
      'deletedAt': Timestamp.fromDate(DateTime(2026, 6, 17, 12)),
      'status': 'excluido',
      'motivoExclusao': 'exclusao_lancamento_duplicado_baixa_cr',
    });

    const idCorreto = 'mp_cr2_venda-sync_p1_1200_20260617';
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Sync',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: 'cr_receb2:venda-sync_p1:1:1200:20260617',
      ),
    );
    await finBox.put(
      idDuplicado,
      LancamentoFinanceiro(
        id: idDuplicado,
        lojaId: lojaId,
        descricao: 'Recebimento — Sync',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberFirestore(
          contaReceberDocId: 'sync-doc',
          baixaId: 'bx_sync',
        ),
      ),
    );

    await FinanceiroLancamentoExclusaoService
        .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: finBox.get(idDuplicado)!,
      lancamentosLoja: finBox.values,
    );
    expect(finBox.get(idDuplicado), isNull);

    await FinanceiroFirestoreService.pullLojaFirestoreParaHiveFase2d(lojaId);
    expect(finBox.get(idDuplicado), isNull);
    expect(finBox.get(idCorreto), isNotNull);
  });
}
