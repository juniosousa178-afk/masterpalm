import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/financeiro_lancamento_duplicidade_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  const lojaId = 'loja-dup-filtro';
  const valor = 40.0;
  final dataMaio = DateTime(2026, 5, 10);
  final dataJunho = DateTime(2026, 6, 10);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_filtro')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('busca candidato fora da lista filtrada da tela', () async {
    const stable = 'venda-filtro_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: dataMaio,
    );
    const idDuplicado = 'mp_cr2_venda-filtro__bx_fora_filtro';

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Cliente Filtro',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: dataMaio,
        dataPagamento: dataMaio,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberStable(
          contaReceberStableId: stable,
          parcelaNumero: 1,
          valor: valor,
          dataRecebimento: dataMaio,
        ),
      ),
    );
    await finBox.put(
      idDuplicado,
      LancamentoFinanceiro(
        id: idDuplicado,
        lojaId: lojaId,
        descricao: 'Recebimento — Cliente Filtro',
        valor: valor,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: dataMaio,
        dataPagamento: dataMaio,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        referenciaExterna: referenciaExternaContaReceberFirestore(
          contaReceberDocId: 'venda-filtro',
          baixaId: 'bx_fora_filtro',
        ),
      ),
    );
    await finBox.put(
      'manual-junho',
      LancamentoFinanceiro(
        id: 'manual-junho',
        lojaId: lojaId,
        descricao: 'Outro lançamento',
        valor: 10,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: dataJunho,
        dataPagamento: dataJunho,
        origem: FinanceiroOrigemLancamento.manual,
      ),
    );

    final listaFiltradaMes = finBox.values.where((l) {
      final d = l.dataPagamento ?? l.dataLancamento;
      return d.month == 6;
    }).toList();
    expect(listaFiltradaMes.length, 1);

    final duplicado = finBox.get(idDuplicado)!;
    final diagFiltrado = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: duplicado,
      lancamentos: listaFiltradaMes,
      lojaId: lojaId,
    );
    expect(diagFiltrado.candidatos, isEmpty);

    final diagHive = FinanceiroLancamentoDuplicidadeResolver.diagnosticar(
      alvo: duplicado,
      lancamentos: finBox.values,
      lojaId: lojaId,
    );
    expect(diagHive.podeExcluirDuplicado, isTrue);
    expect(diagHive.candidatos.length, 1);
  });
}
