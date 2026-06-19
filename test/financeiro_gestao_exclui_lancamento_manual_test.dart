import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-exc-man';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_exc_man')).path);
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('exclui manual pago', () async {
    final l = LancamentoFinanceiro(
      id: 'exc-man',
      lojaId: lojaId,
      descricao: 'Manual',
      valor: 3,
      dataLancamento: DateTime(2026, 6, 1),
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
