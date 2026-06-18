// Lançamento antigo com chave Hive numérica (sem id) some da listagem do relatório.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-rel-exc-legacy-lista';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_rel_exc_leg_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('excluir legacy por hive key remove da listagem do mês', () async {
    final agora = DateTime(2026, 6, 15);
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final l = LancamentoFinanceiro(
      id: '',
      lojaId: lojaId,
      descricao: 'Recebimento — Junho',
      valor: 80,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: agora,
      dataPagamento: agora,
    );
    final hiveKey = await box!.add(l);
    final stored = box.get(hiveKey)!;
    expect(stored.key, hiveKey);

    final antes =
        FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: box,
      lojaId: lojaId,
      referencia: agora,
    );
    expect(antes.length, 1);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: stored,
    );

    expect(r.sucesso, isTrue);
    expect(r.legado, isTrue);

    final depois =
        FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: box,
      lojaId: lojaId,
      referencia: agora,
    );
    expect(depois, isEmpty);
    expect(box.length, 0);
  });
}
