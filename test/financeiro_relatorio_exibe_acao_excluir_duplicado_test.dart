import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-rel-dup';
  const valor = 22.0;
  final data = DateTime(2026, 6, 3);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_rel_dup')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('Relatório Financeiro resolve ação excluir duplicado com hive completa', () async {
    const stable = 'venda-rel_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    );
    const idDuplicado = 'mp_cr2_venda-rel__bx_rel';

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Relatório',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        dataPagamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberStable(
          contaReceberStableId: stable,
          parcelaNumero: 1,
          valor: valor,
          dataRecebimento: data,
        ),
      ),
    );
    await finBox.put(
      idDuplicado,
      LancamentoFinanceiro(
        id: idDuplicado,
        lojaId: lojaId,
        descricao: 'Recebimento — Relatório',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        dataPagamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberFirestore(
          contaReceberDocId: 'venda-rel',
          baixaId: 'bx_rel',
        ),
      ),
    );

    final apenasMes = finBox.values
        .where((l) => (l.dataPagamento ?? l.dataLancamento).month == 6)
        .toList();
    final duplicado = finBox.get(idDuplicado)!;

    final acaoRelatorio = FinanceiroLancamentoExclusaoService.acaoParaUi(
      duplicado,
      lojaId: lojaId,
      lancamentosLoja: finBox.values,
    );
    final acaoFiltradaErrada = FinanceiroLancamentoExclusaoService.acaoParaUi(
      duplicado,
      lojaId: lojaId,
      lancamentosLoja: [duplicado],
    );

    expect(acaoRelatorio.mostrarExcluirDuplicado, isTrue);
    expect(acaoFiltradaErrada.mostrarExcluirDuplicado, isFalse);
    expect(apenasMes.length, 2);
  });
}
