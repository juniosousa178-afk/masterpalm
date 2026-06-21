import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/financeiro_lancamento_duplicidade_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  const lojaId = 'loja-dup-mes';
  const valor = 75.0;
  final dataBaixa = DateTime(2026, 4, 20);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_mes')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('encontra par fora da competência visível na Gestão Financeira', () async {
    const vendaId = 'venda-mes';
    const stable = '${vendaId}_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: dataBaixa,
    );
    const idDuplicado = 'mp_cr2_venda-mes__bx_mes';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.clear();
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente Mes',
        valor: valor,
        valorOriginal: valor,
        dataVencimento: DateTime(2026, 5, 1),
        dataVenda: DateTime(2026, 4, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        idFirebase: vendaId,
        pago: true,
        valorPago: valor,
      ),
    );

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Cliente Mes',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: dataBaixa,
        dataPagamento: dataBaixa,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberStable(
          contaReceberStableId: stable,
          parcelaNumero: 1,
          valor: valor,
          dataRecebimento: dataBaixa,
        ),
      ),
    );
    await finBox.put(
      idDuplicado,
      LancamentoFinanceiro(
        id: idDuplicado,
        lojaId: lojaId,
        descricao: 'Recebimento — Cliente Mes',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: dataBaixa,
        dataPagamento: dataBaixa,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberFirestore(
          contaReceberDocId: vendaId,
          baixaId: 'bx_mes',
        ),
      ),
    );

    final visiveisJunho = finBox.values.where((l) {
      final d = l.dataPagamento ?? l.dataLancamento;
      return d.year == 2026 && d.month == 6;
    }).toList();
    expect(visiveisJunho, isEmpty);

    final duplicado = finBox.get(idDuplicado)!;
    final diag = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: duplicado,
      lancamentos: finBox.values,
      contas: crBox.values,
      lojaId: lojaId,
    );

    expect(diag.podeExcluirDuplicado, isTrue);
    expect(diag.lancamentoAManter?.id, idCorreto);
  });
}
