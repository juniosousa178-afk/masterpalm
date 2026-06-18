// Baixa legada: origem fiado + descrição, sem referenciaExterna — heurística segura.

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
  const lojaId = 'loja-fin-estorno-legado-ok';
  const vendaId = 'venda-legado-heuristica';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_est_leg_ok_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('estorna baixa legada com uuid id e origem fiado', () async {
    const valorBaixa = 45.0;
    final data = DateTime(2025, 11, 5);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Carlos',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2025, 12, 1),
        dataVenda: DateTime(2025, 11, 1),
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
      id: 'uuid-antigo-sem-ref-2025',
      lojaId: lojaId,
      descricao: 'Recebimento — Carlos',
      valor: valorBaixa,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.pago,
      formaPagamento: 'Pix',
      dataLancamento: data,
      dataPagamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: '',
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(lanc.id, lanc);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: lanc,
    );

    expect(r.sucesso, isTrue);
    expect(r.legado, isTrue);
    expect(conta.saldoRestante, closeTo(100, 0.01));
    expect(finBox.get(lanc.id), isNull);
  });
}
