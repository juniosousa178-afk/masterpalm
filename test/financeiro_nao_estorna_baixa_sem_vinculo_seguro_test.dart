// Bloqueio de estorno sem vínculo seguro com Conta a Receber.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-sem-vinculo';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_sem_vin_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('não estorna lançamento órfão sem referência reconhecível', () async {
    final lanc = LancamentoFinanceiro(
      id: 'mp_cr_orfao_teste',
      lojaId: lojaId,
      descricao: 'Órfão',
      valor: 50,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 8),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: 'cr_receb:orfao:123',
    );
    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBox!.put(lanc.id, lanc);

    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: lanc,
    );

    expect(r.sucesso, isFalse);
    expect(r.mensagemErro, contains('vínculo'));
    expect(finBox.get(lanc.id), isNotNull);
  });
}
