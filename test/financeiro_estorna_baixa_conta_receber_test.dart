// Estorno de baixa de Conta a Receber via lançamento financeiro.

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
  const lojaId = 'loja-fin-estorno-cr';
  const vendaId = 'venda-estorno-cr-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_est_cr_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('estornarBaixaContaReceber reabre parcela e remove LF', () async {
    const valorBaixa = 70.0;
    final data = DateTime(2026, 6, 8);
    final stable = '${vendaId}_p1';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Maria',
        valor: 120,
        valorOriginal: 120,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valorBaixa,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    await conta.save();

    final lanc = LancamentoFinanceiro(
      id: lancamentoFinanceiroDocIdParaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valorBaixa,
        dataRecebimento: data,
      ),
      lojaId: lojaId,
      descricao: 'Recebimento — Maria',
      valor: valorBaixa,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valorBaixa,
        dataRecebimento: data,
      ),
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(lanc.id, lanc);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: lanc,
      motivoEstorno: 'parcela errada',
    );

    expect(r.sucesso, isTrue);
    expect(r.contaReceberAtualizada, isTrue);
    expect(conta.saldoRestante, closeTo(120, 0.01));
    expect(finBox.get(lanc.id), isNull);
  });
}
