import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/financeiro_lancamento_duplicidade_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-dup-manter';
  const valor = 30.0;
  final data = DateTime(2026, 6, 13);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_manter')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('mantém lançamento correto após excluir duplicado', () async {
    const stable = 'venda-manter_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    );
    const idDuplicado = 'mp_cr2_venda-manter__bx_abc';

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    final correto = LancamentoFinanceiro(
      id: idCorreto,
      lojaId: lojaId,
      descricao: 'Recebimento — Cliente',
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
    );
    final duplicado = LancamentoFinanceiro(
      id: idDuplicado,
      lojaId: lojaId,
      descricao: 'Recebimento — Cliente',
      valor: valor,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      dataPagamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberFirestore(
        contaReceberDocId: 'venda-manter',
        baixaId: 'bx_abc',
      ),
    );
    await finBox.put(idCorreto, correto);
    await finBox.put(idDuplicado, duplicado);

    final diag = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: duplicado,
      lancamentos: finBox.values,
      lojaId: lojaId,
    );
    expect(diag.lancamentoAManter?.id, idCorreto);

    await FinanceiroLancamentoExclusaoService
        .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: duplicado,
      lancamentosLoja: finBox.values,
    );

    expect(finBox.get(idCorreto)?.valor, valor);
    expect(finBox.get(idDuplicado), isNull);
  });
}
