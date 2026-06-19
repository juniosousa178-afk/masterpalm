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
  const lojaId = 'loja-cr-sem-vinc-parc';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_cr_parc')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('Giovana sem vínculo não altera parcela ao excluir financeiro', () async {
    const valor = 80.0;
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Outra Cliente',
      valor: 200,
      valorOriginal: 200,
      dataVencimento: DateTime(2026, 7, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: 'v-outra',
      parcelaNumero: 1,
    ));
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: 50,
      formaPagamento: 'Pix',
      dataRecebimento: DateTime(2026, 6, 5),
    );
    await conta.save();
    final pagoAntes = conta.valorPago;
    final saldoAntes = conta.saldoRestante;

    final l = LancamentoFinanceiro(
      id: 'cr-giovana',
      lojaId: lojaId,
      descricao: 'Recebimento — Giovana Almeida',
      valor: valor,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 1),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
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
    expect(conta.valorPago, closeTo(pagoAntes, 0.02));
    expect(conta.saldoRestante, closeTo(saldoAntes, 0.02));
    expect(finBox.get(l.id), isNull);
  });
}
