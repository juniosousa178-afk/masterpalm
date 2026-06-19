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
  const lojaId = 'loja-fin-fin-cr-est';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_fin_fin_cr_est')).path);
    if (!Hive.isAdapterRegistered(29)) Hive.registerAdapter(ContaReceberAdapter());
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('baixa CR finalizada estorna com vínculo seguro', () async {
    const valor = 55.0;
    final data = DateTime(2025, 8, 12);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Rafaela Abelha',
      valor: 100,
      valorOriginal: 100,
      dataVencimento: DateTime(2025, 9, 1),
      dataVenda: DateTime(2025, 8, 1),
      vendaIdFirebase: 'v-raf',
      parcelaNumero: 1,
    ));
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valor,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    await conta.save();

    final l = LancamentoFinanceiro(
      id: 'cr-fin-raf',
      lojaId: lojaId,
      descricao: 'Recebimento — Rafaela Abelha',
      valor: valor,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: data,
      dataPagamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(r.sucesso, isTrue);
    await conta.save();
    expect(conta.saldoRestante, closeTo(100, 0.02));
    expect(finBox.get(l.id), isNull);
  });
}
