import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/financeiro_lancamento_acao.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-gestao-dup-ui';
  const vendaId = 'venda-rafaela';
  const valor = 99.90;
  final data = DateTime(2026, 5, 15);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gestao_dup_ui')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  setUp(() async {
    const stable = '${vendaId}_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    );
    const idDuplicado = 'mp_cr2_${vendaId}__bx_rafaela';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.clear();
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Rafaela Abelha',
        valor: valor,
        valorOriginal: valor,
        dataVencimento: DateTime(2026, 6, 1),
        dataVenda: DateTime(2026, 5, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        idFirebase: vendaId,
        pago: true,
        valorPago: valor,
      ),
    );

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Rafaela Abelha',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        dataPagamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        formaPagamento: 'Pix',
        referenciaExterna: referenciaExternaContaReceberStable(
          contaReceberStableId: stable,
          parcelaNumero: 1,
          valor: valor,
          dataRecebimento: data,
        ),
      ),
    );
    await finBox.put(
      idDuplicado,
      LancamentoFinanceiro(
        id: idDuplicado,
        lojaId: lojaId,
        descricao: 'Recebimento — Rafaela Abelha',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        dataPagamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        formaPagamento: 'Dinheiro',
        observacao: 'sync firestore',
        referenciaExterna: referenciaExternaContaReceberFirestore(
          contaReceberDocId: vendaId,
          baixaId: 'bx_rafaela',
        ),
      ),
    );
  });

  test('Gestão Financeira exibe ação excluir duplicado no lançamento redundante', () async {
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final duplicado = finBox!.values.firstWhere(
      (l) => l.referenciaExterna.contains('__bx_'),
    );

    final acao = FinanceiroLancamentoExclusaoService.acaoParaUi(
      duplicado,
      contas: crBox.values,
      lojaId: lojaId,
      lancamentosLoja: finBox.values,
    );

    expect(acao.mostrarExcluirDuplicado, isTrue);
    expect(acao.mostrarEstornar, isFalse);
    expect(acao.podeExcluirDuplicadoBaixaCr, isTrue);
  });

  test('lançamento correto mantém estorno e não exibe excluir duplicado', () async {
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final correto = finBox!.values.firstWhere(
      (l) => l.referenciaExterna.startsWith('cr_receb2:'),
    );

    final acao = FinanceiroLancamentoAcaoResolver.resolver(
      correto,
      contas: crBox.values,
      lojaId: lojaId,
      lancamentosLoja: finBox.values,
    );

    expect(acao.mostrarExcluirDuplicado, isFalse);
    expect(acao.mostrarEstornar, isTrue);
  });
}
