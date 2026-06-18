// Baixa de Conta a Receber legada não deve usar exclusão manual.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/financeiro_lancamento_legacy_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-rel-cr-nao-excluir';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_rel_cr_nao_exc_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('Recebimento — Junho com observação CR é baixa, não manual', () {
    final l = LancamentoFinanceiro(
      id: 'legacy-cr-junho',
      lojaId: 'loja-x',
      descricao: 'Recebimento — Junho',
      valor: 50,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );

    expect(
      FinanceiroLancamentoExclusaoService.lancamentoEhBaixaContaReceber(l),
      isTrue,
    );
    final info = FinanceiroLancamentoLegacyResolver.classificar(l);
    expect(info.ehBaixaCr, isTrue);
    expect(info.ehManual, isFalse);
  });

  test('excluirLancamentoManual bloqueia baixa CR legada', () async {
    final l = LancamentoFinanceiro(
      id: 'cr-bloq-exc',
      lojaId: lojaId,
      descricao: 'Recebimento — Junho',
      valor: 50,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 1),
      observacao: 'Conta a receber',
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isFalse);
    expect(r.mensagemErro, contains('Estornar baixa'));
    expect(box.get(l.id), isNotNull);
  });
}
