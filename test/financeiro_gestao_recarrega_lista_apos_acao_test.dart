import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-refresh';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_refresh')).path);
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('lista recarrega após exclusão', () async {
    final ref = DateTime(2026, 6, 15);
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final a = LancamentoFinanceiro(
      id: 'keep',
      lojaId: lojaId,
      descricao: 'Manter',
      valor: 1,
      dataLancamento: ref,
    );
    final b = LancamentoFinanceiro(
      id: 'go',
      lojaId: lojaId,
      descricao: 'Sair',
      valor: 2,
      dataLancamento: ref,
    );
    await box!.put(a.id, a);
    await box.put(b.id, b);
    await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: b,
    );
    final lista = FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: box,
      lojaId: lojaId,
      referencia: ref,
    );
    expect(lista.length, 1);
    expect(lista.first.id, 'keep');
  });
}
