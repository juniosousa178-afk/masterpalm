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
  const valor = 18.0;
  final referencia = DateTime(2026, 6, 19);
  final data = DateTime(2026, 6, 19);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_rel_dup')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('relatório remove apenas duplicado e mantém total correto', () async {
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
        descricao: 'Recebimento — Rel',
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
    final dup = LancamentoFinanceiro(
      id: idDuplicado,
      lojaId: lojaId,
      descricao: 'Recebimento — Rel',
      valor: valor,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      dataPagamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberFirestore(
        contaReceberDocId: 'venda-rel',
        baixaId: 'bx_rel',
      ),
    );
    await finBox.put(idDuplicado, dup);

    final antes = FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: finBox,
      lojaId: lojaId,
      referencia: referencia,
    );
    expect(antes.length, 2);
    expect(
      antes.fold<double>(0, (s, l) => s + l.valor),
      closeTo(valor * 2, 0.02),
    );

    await FinanceiroLancamentoExclusaoService
        .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: dup,
      lancamentosLoja: finBox.values,
    );

    final depois = FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: finBox,
      lojaId: lojaId,
      referencia: referencia,
    );
    expect(depois.length, 1);
    expect(depois.first.id, idCorreto);
    expect(
      depois.fold<double>(0, (s, l) => s + l.valor),
      closeTo(valor, 0.02),
    );
  });
}
