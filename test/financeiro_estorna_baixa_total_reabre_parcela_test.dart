// Estorno total: parcela volta a pendente.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-estorno-total';
  const vendaId = 'venda-total-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_est_tot_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('estorno total reabre parcela quitada', () async {
    const valor = 90.0;
    final data = DateTime(2026, 6, 7);
    final stable = '${vendaId}_p1';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Luiza',
        valor: valor,
        valorOriginal: valor,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valor,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    await conta.save();
    expect(conta.pago, isTrue);
    expect(conta.status, ContaReceberStatus.paga);

    final lanc = LancamentoFinanceiro(
      id: lancamentoFinanceiroDocIdParaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valor,
        dataRecebimento: data,
      ),
      lojaId: lojaId,
      descricao: 'R',
      valor: valor,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valor,
        dataRecebimento: data,
      ),
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(lanc.id, lanc);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: lanc,
    );

    expect(r.sucesso, isTrue);
    expect(conta.pago, isFalse);
    expect(conta.status, ContaReceberStatus.pendente);
    expect(conta.saldoRestante, closeTo(valor, 0.01));
    expect(conta.valorPago, closeTo(0, 0.01));
  });
}
