import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-cr-sem-vinc-exc';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_sem_vinc')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('Recebimento — Junho sem vínculo exclui somente financeiro', () async {
    final l = LancamentoFinanceiro(
      id: 'cr-junho',
      lojaId: lojaId,
      descricao: 'Recebimento — Junho',
      valor: 8,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r =
        await FinanceiroLancamentoExclusaoService.excluirSomenteLancamentoFinanceiroLegado(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isTrue);
    expect(r.contaReceberAtualizada, isFalse);
    expect(box.get(l.id), isNull);
  });
}
