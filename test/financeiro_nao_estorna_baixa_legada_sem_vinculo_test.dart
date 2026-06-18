// Baixa legada sem vínculo seguro: bloqueia estorno.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-estorno-legado-bloq';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_est_leg_blk_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('bloqueia estorno legado sem parcela correspondente', () async {
    final lanc = LancamentoFinanceiro(
      id: 'uuid-antigo-orfao',
      lojaId: lojaId,
      descricao: 'Recebimento — Cliente Inexistente',
      valor: 99,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2024, 1, 15),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: '',
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
