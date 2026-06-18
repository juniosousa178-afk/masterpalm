// Exclusão de lançamento manual antigo (sem origem/referenciaExterna novas).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-manual-legado';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_man_leg_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('manual legado sem origem/referenciaExterna exclui do Hive', () async {
    final l = LancamentoFinanceiro(
      id: 'uuid-legado-manual-1999',
      lojaId: lojaId,
      descricao: 'Ajuste antigo',
      valor: 33,
      tipo: FinanceiroTipoLancamento.despesaOperacional,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2024, 3, 10),
      origem: '',
      referenciaExterna: '',
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isTrue);
    expect(r.legado, isTrue);
    expect(box.get(l.id), isNull);
  });
}
