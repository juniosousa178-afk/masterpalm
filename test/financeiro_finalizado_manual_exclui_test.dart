import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-finalizado-exc';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_fin_fin_exc')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('manual com status finalizado exclui e some da UI', () async {
    final l = LancamentoFinanceiro(
      id: 'fin-manual-1',
      lojaId: lojaId,
      descricao: 'Despesa finalizada',
      valor: 40,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 10),
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    expect(FinanceiroLancamentoExclusaoService.lancamentoExcluivelNaUi(l), isTrue);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(r.sucesso, isTrue);
    expect(box.get(l.id), isNull);
  });
}
