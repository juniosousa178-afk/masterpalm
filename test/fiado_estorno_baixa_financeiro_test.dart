// Estorno: excluir lançamento fiado reverte saldo da conta a receber.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_financeiro_sync_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  const lojaId = 'loja-fiado-estorno';
  const vendaId = 'estorno-venda-uuid-20260614';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_est_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('reverterBaixaPorLancamento reabre saldo da conta', () async {
    const valorBaixa = 60.0;
    const valorOriginal = 150.0;
    final data = DateTime(2026, 6, 8);
    final stable = '${vendaId}_p1';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'João',
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
      valorRecebido: valorBaixa,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    await conta.save();
    expect(conta.saldoRestante, closeTo(90, 0.01));

    final lanc = LancamentoFinanceiro(
      id: lancamentoFinanceiroDocIdParaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valorBaixa,
        dataRecebimento: data,
      ),
      lojaId: lojaId,
      descricao: 'Recebimento — João',
      valor: valorBaixa,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      formaPagamento: 'Pix',
      dataLancamento: data,
      dataPagamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valorBaixa,
        dataRecebimento: data,
      ),
    );

    final resultado = await ContaReceberFinanceiroSyncService.reverterBaixaPorLancamento(
      lojaId: lojaId,
      lancamento: lanc,
    );

    expect(resultado.sucesso, isTrue);
    expect(resultado.contaAtualizada, isTrue);
    expect(conta.saldoRestante, closeTo(valorOriginal, 0.01));
    expect(conta.valorPago, closeTo(0, 0.01));
    expect(conta.status, ContaReceberStatus.pendente);
  });

  test('estorno idempotente não altera saldo duas vezes', () async {
    const lojaIsolada = '${lojaId}_idem';
    const valorBaixa = 40.0;
    final data = DateTime(2026, 6, 9);
    final stable = '${vendaId}_p1';

    final crBox = await ContaReceberService.openBoxLoja(lojaIsolada);
    await crBox.add(
      ContaReceber(
        lojaId: lojaIsolada,
        clienteNome: 'Ana',
        valor: 100,
        valorOriginal: 100,
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
      formaPagamento: 'Dinheiro',
      dataRecebimento: data,
    );
    await conta.save();

    final lanc = LancamentoFinanceiro(
      id: 'mp_cr2_test',
      lojaId: lojaIsolada,
      descricao: 'R',
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

    final r1 = await ContaReceberFinanceiroSyncService.reverterBaixaPorLancamento(
      lojaId: lojaIsolada,
      lancamento: lanc,
    );
    final saldoApos1 = conta.saldoRestante;

    final r2 = await ContaReceberFinanceiroSyncService.reverterBaixaPorLancamento(
      lojaId: lojaIsolada,
      lancamento: lanc,
    );

    expect(r1.contaAtualizada, isTrue);
    expect(r2.jaEstavaEstornada, isTrue);
    expect(conta.saldoRestante, closeTo(saldoApos1, 0.01));
    await crBox.close();
  });
}
