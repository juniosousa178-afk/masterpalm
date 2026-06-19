import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-refresh-fin';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_ref_fin')).path);
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('lista do mês fica vazia após excluir finalizado', () async {
    final ref = DateTime(2026, 6, 20);
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final l = LancamentoFinanceiro(
      id: 'fin-del',
      lojaId: lojaId,
      descricao: 'Finalizado',
      valor: 9,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: ref,
    );
    await box!.put(l.id, l);
    expect(
      FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
        box: box,
        lojaId: lojaId,
        referencia: ref,
      ).length,
      1,
    );
    await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(
      FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
        box: box,
        lojaId: lojaId,
        referencia: ref,
      ),
      isEmpty,
    );
  });
}
