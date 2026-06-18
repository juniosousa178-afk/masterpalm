// Exclusão manual legada não altera Contas a Receber nem simula estorno.

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
  const lojaId = 'loja-fin-legado-nao-cr';
  const vendaId = 'venda-intocada-legado';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_leg_iso_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('excluir manual legado não mexe na parcela em aberto', () async {
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Marta',
        valor: 80,
        valorOriginal: 80,
        dataVencimento: DateTime(2026, 8, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );
    final conta = crBox.values.first;
    final saldoAntes = conta.saldoRestante;

    final lanc = LancamentoFinanceiro(
      id: 'manual-legado-entrada-extra',
      lojaId: lojaId,
      descricao: 'Entrada avulsa antiga',
      valor: 20,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2022, 5, 1),
      origem: FinanceiroOrigemLancamento.manual,
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(lanc.id, lanc);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: lanc,
    );

    expect(r.sucesso, isTrue);
    expect(conta.saldoRestante, closeTo(saldoAntes, 0.01));
    expect(conta.valorPago, closeTo(0, 0.01));
    expect(finBox.get(lanc.id), isNull);
  });
}
