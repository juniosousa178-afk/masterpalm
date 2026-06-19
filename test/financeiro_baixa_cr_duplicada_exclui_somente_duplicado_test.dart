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
  const lojaId = 'loja-dup-exc';
  const vendaId = 'venda-dup-exc';
  const valor = 55.0;
  final data = DateTime(2026, 6, 12);
  late String idCorreto;
  late String idDuplicado;

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_exc')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  setUp(() async {
    final stable = '${vendaId}_p1';
    idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    );
    idDuplicado = 'mp_cr2_${vendaId}__bx_dup_teste';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.clear();
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Maria Duplicada',
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
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    await conta.save();

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Maria Duplicada',
        valor: valor,
        tipo: FinanceiroTipoLancamento.entradaExtra,
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
        descricao: 'Recebimento — Maria Duplicada',
        valor: valor,
        tipo: FinanceiroTipoLancamento.entradaExtra,
        status: FinanceiroStatusLancamento.pago,
        dataLancamento: data,
        dataPagamento: data,
        origem: FinanceiroOrigemLancamento.contaReceberFiado,
        formaPagamento: 'Pix',
        referenciaExterna: referenciaExternaContaReceberFirestore(
          contaReceberDocId: vendaId,
          baixaId: 'bx_dup_teste',
        ),
      ),
    );
  });

  test('exclui somente o lançamento duplicado', () async {
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final duplicado = finBox!.get(idDuplicado)!;

    final r =
        await FinanceiroLancamentoExclusaoService
            .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: duplicado,
      lancamentosLoja: finBox.values,
    );

    expect(r.sucesso, isTrue);
    expect(finBox.get(idDuplicado), isNull);
    expect(finBox.get(idCorreto), isNotNull);
  });
}
