// Estorno parcial: saldo reaberto proporcionalmente.

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
  const lojaId = 'loja-fin-estorno-parcial';
  const vendaId = 'venda-parcial-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_est_parc_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('estorno parcial deixa parcela parcialmente pendente', () async {
    const valorOriginal = 200.0;
    const baixa1 = 50.0;
    const baixa2 = 30.0;
    final data1 = DateTime(2026, 6, 5);
    final data2 = DateTime(2026, 6, 6);
    final stable = '${vendaId}_p1';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Pedro',
        valor: valorOriginal,
        valorOriginal: valorOriginal,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: baixa1,
      formaPagamento: 'Pix',
      dataRecebimento: data1,
    );
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: baixa2,
      formaPagamento: 'Dinheiro',
      dataRecebimento: data2,
    );
    await conta.save();
    expect(conta.saldoRestante, closeTo(120, 0.01));
    expect(conta.status, ContaReceberStatus.parcial);

    final lanc2 = LancamentoFinanceiro(
      id: lancamentoFinanceiroDocIdParaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: baixa2,
        dataRecebimento: data2,
      ),
      lojaId: lojaId,
      descricao: 'R2',
      valor: baixa2,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data2,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: baixa2,
        dataRecebimento: data2,
      ),
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(lanc2.id, lanc2);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: lanc2,
    );

    expect(r.sucesso, isTrue);
    expect(conta.saldoRestante, closeTo(150, 0.01));
    expect(conta.valorPago, closeTo(50, 0.01));
    expect(conta.status, ContaReceberStatus.parcial);
  });
}
