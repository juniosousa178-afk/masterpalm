import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-exc-cr';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_exc_cr')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('exclui somente financeiro CR sem vínculo', () async {
    final l = LancamentoFinanceiro(
      id: 'cr-junho-gestao',
      lojaId: lojaId,
      descricao: 'Recebimento — Junho',
      valor: 8,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
      categoria: 'recebimentos_fiado',
      tipo: FinanceiroTipoLancamento.entradaExtra,
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r =
        await FinanceiroLancamentoExclusaoService.excluirSomenteLancamentoFinanceiroLegado(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isTrue);
    expect(box.get(l.id), isNull);
  });
}
