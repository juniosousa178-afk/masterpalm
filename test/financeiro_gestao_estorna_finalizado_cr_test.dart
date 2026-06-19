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
  const lojaId = 'loja-gestao-est-fin';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_est_fin')).path);
    if (!Hive.isAdapterRegistered(29)) Hive.registerAdapter(ContaReceberAdapter());
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  test('gestão estorna baixa CR finalizada', () async {
    const v = 30.0;
    final dt = DateTime(2025, 10, 3);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente',
      valor: 60,
      valorOriginal: 60,
      dataVencimento: DateTime(2025, 11, 1),
      dataVenda: DateTime(2025, 10, 1),
      vendaIdFirebase: 'v1',
      parcelaNumero: 1,
    ));
    final c = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: c,
      valorRecebido: v,
      formaPagamento: 'Pix',
      dataRecebimento: dt,
    );
    await c.save();

    final l = LancamentoFinanceiro(
      id: 'lf-cr-fin',
      lojaId: lojaId,
      descricao: 'Recebimento — Cliente',
      valor: v,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: dt,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(r.sucesso, isTrue);
    expect(box.get(l.id), isNull);
  });
}
