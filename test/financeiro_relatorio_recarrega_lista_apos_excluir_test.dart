// Simula refresh da listagem após exclusão (mesma query do Relatório Financeiro).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-rel-refresh-lista';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_rel_refresh_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('listagem do mês fica vazia após excluir manual legado', () async {
    final ref = DateTime(2026, 6, 20);
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final a = LancamentoFinanceiro(
      id: 'manter',
      lojaId: lojaId,
      descricao: 'Outro',
      valor: 10,
      dataLancamento: ref,
    );
    final b = LancamentoFinanceiro(
      id: 'excluir',
      lojaId: lojaId,
      descricao: 'Manual antigo',
      valor: 20,
      dataLancamento: ref,
      origem: '',
      referenciaExterna: '',
    );
    await box!.put(a.id, a);
    await box.put(b.id, b);

    expect(
      FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
        box: box,
        lojaId: lojaId,
        referencia: ref,
      ).length,
      2,
    );

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: b,
    );
    expect(r.sucesso, isTrue);

    final lista =
        FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: box,
      lojaId: lojaId,
      referencia: ref,
    );
    expect(lista.length, 1);
    expect(lista.first.id, 'manter');
  });
}
