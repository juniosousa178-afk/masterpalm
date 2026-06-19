import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-exc-fin';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_exc_fin')).path);
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('gestão exclui manual finalizado', () async {
    final l = LancamentoFinanceiro(
      id: 'g-exc',
      lojaId: lojaId,
      descricao: 'Finalizado manual',
      valor: 22,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 12),
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);
    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(r.sucesso, isTrue);
    expect(box.length, 0);
  });
}
