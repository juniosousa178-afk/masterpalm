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
  const lojaId = 'loja-dup-nao-reabre';
  const vendaId = 'venda-nao-reabre';
  const valor = 42.0;
  final data = DateTime(2026, 6, 14);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_nao_reab')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('excluir duplicado não reabre parcela em Contas a Receber', () async {
    final stable = '${vendaId}_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    );
    const idDuplicado = 'mp_cr2_venda-nao-reabre__bx_x';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.clear();
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Ana',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        idFirebase: vendaId,
      ),
    );
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valor,
      formaPagamento: 'Dinheiro',
      dataRecebimento: data,
    );
    await conta.save();
    final saldoAntes = conta.saldoRestante;
    final pagoAntes = conta.pago;

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Ana',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberStable(
          contaReceberStableId: stable,
          parcelaNumero: 1,
          valor: valor,
          dataRecebimento: data,
        ),
      ),
    );
    final dup = LancamentoFinanceiro(
      id: idDuplicado,
      lojaId: lojaId,
      descricao: 'Recebimento — Ana',
      valor: valor,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberFirestore(
        contaReceberDocId: vendaId,
        baixaId: 'bx_x',
      ),
    );
    await finBox.put(idDuplicado, dup);

    final r =
        await FinanceiroLancamentoExclusaoService
            .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: dup,
      lancamentosLoja: finBox.values,
    );
    expect(r.sucesso, isTrue);
    expect(r.contaReceberAtualizada, isFalse);

    final contaDepois = crBox.values.first;
    expect(contaDepois.pago, pagoAntes);
    expect(contaDepois.saldoRestante, saldoAntes);
    expect(contaDepois.valorPago, closeTo(valor, 0.02));
  });
}
