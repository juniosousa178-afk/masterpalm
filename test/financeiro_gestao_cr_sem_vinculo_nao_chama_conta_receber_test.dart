import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-cr-intact';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_cr_ok')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('excluir somente financeiro não altera Conta a Receber', () async {
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente Qualquer',
      valor: 100,
      valorOriginal: 100,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: 'v1',
      parcelaNumero: 1,
    ));
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: 20,
      formaPagamento: 'Pix',
      dataRecebimento: DateTime(2026, 6, 3),
    );
    await conta.save();
    final pago = conta.valorPago;
    final saldo = conta.saldoRestante;

    final l = LancamentoFinanceiro(
      id: 'cr-orfao',
      lojaId: lojaId,
      descricao: 'Recebimento — Junho',
      valor: 8,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
      categoria: 'recebimentos_fiado',
      tipo: FinanceiroTipoLancamento.entradaExtra,
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(l.id, l);

    final r =
        await FinanceiroLancamentoExclusaoService.excluirSomenteLancamentoFinanceiroLegado(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isTrue);
    await conta.save();
    expect(conta.valorPago, closeTo(pago, 0.02));
    expect(conta.saldoRestante, closeTo(saldo, 0.02));
    expect(crBox.length, 1);
  });
}
