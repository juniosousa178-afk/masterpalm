import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_recebimento_caixa_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';

void main() {
  const lojaId = 'loja-anti-dup-cr';
  const vendaId = 'venda-anti-dup';
  const valor = 25.0;
  final data = DateTime(2026, 6, 18);

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_anti_dup')).path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('registrarRecebimento não cria segundo lançamento equivalente', () async {
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.clear();
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Paula',
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
    final hiveKey = conta.key!;

    final id1 = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valor,
      formaPagamento: 'Pix',
      clienteNome: conta.clienteNome,
      conta: conta,
      contaHiveKey: hiveKey,
      dataRecebimento: data,
    );
    expect(id1, isNotNull);

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    expect(finBox!.values.length, 1);

    final id2 = await ContaReceberRecebimentoCaixaService.registrarRecebimento(
      lojaId: lojaId,
      valor: valor,
      formaPagamento: 'Pix',
      clienteNome: conta.clienteNome,
      conta: conta,
      contaHiveKey: hiveKey,
      dataRecebimento: data,
      contaReceberDocId: vendaId,
      baixaId: 'bx_anti_dup',
    );

    expect(id2, id1);
    expect(finBox.values.length, 1);
    expect(
      finBox.values.where((l) => (l.valor - valor).abs() < 0.02).length,
      1,
    );
  });
}
