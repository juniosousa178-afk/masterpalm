import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-dup-venda-est';
  const vendaId = 'venda-intacta';
  const valor = 20.0;
  final data = DateTime(2026, 6, 15);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_dup_venda')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VendaAdapter());
    }
  });

  test('excluir duplicado não altera venda nem estoque', () async {
    final vendasName = HiveBoxNames.vendas(lojaId);
    final vendasBox = await Hive.openBox<Venda>(vendasName);
    await vendasBox.clear();
    await vendasBox.put(
      vendaId,
      Venda(
        preco: 100,
        produtosDescricao: 'Prod',
        quantidade: 1,
        clienteNome: 'Cliente',
        total: 100,
        formasPagamento: 'Pix',
        data: DateTime(2026, 6, 1),
        tamanho: '',
        desconto: 0,
        frete: 0,
        vendedor: '',
        observacao: '',
        lojaId: lojaId,
      ),
    );
    final vendaAntes = vendasBox.get(vendaId)!;

    final stable = '${vendaId}_p1';
    final idCorreto = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valor,
      dataRecebimento: data,
    );
    const idDuplicado = 'mp_cr2_venda-intacta__bx_y';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.clear();
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente',
        valor: 80,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
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
    final valorOriginalConta = conta.valorOriginal;

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.clear();
    await finBox.put(
      idCorreto,
      LancamentoFinanceiro(
        id: idCorreto,
        lojaId: lojaId,
        descricao: 'Recebimento — Cliente',
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
      descricao: 'Recebimento — Cliente',
      valor: valor,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberFirestore(
        contaReceberDocId: vendaId,
        baixaId: 'bx_y',
      ),
    );
    await finBox.put(idDuplicado, dup);

    await FinanceiroLancamentoExclusaoService
        .excluirLancamentoFinanceiroDuplicadoDeBaixa(
      lojaId: lojaId,
      lancamento: dup,
      lancamentosLoja: finBox.values,
    );

    final vendaDepois = vendasBox.get(vendaId)!;
    expect(vendaDepois.total, vendaAntes.total);
    expect(crBox.values.first.valorOriginal, valorOriginalConta);
  });
}
