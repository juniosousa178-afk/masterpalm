import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-leg-id';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_leg_id')).path);
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('id vazio com chave hive exclui', () async {
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final l = LancamentoFinanceiro(
      id: '',
      lojaId: lojaId,
      descricao: 'Legado',
      valor: 11,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 4),
    );
    final k = await box!.add(l);
    final stored = box.get(k)!;
    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: stored,
    );
    expect(r.sucesso, isTrue);
    expect(box.length, 0);
  });
}
