import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';
import 'package:master_palm/services/financeiro_service.dart';

void main() {
  const lojaId = 'loja-junho-lista';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_junho_lista')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('Recebimento — Junho some da listagem após excluir somente financeiro', () async {
    final l = LancamentoFinanceiro(
      id: 'junho-lista',
      lojaId: lojaId,
      descricao: 'Recebimento — Junho',
      valor: 8,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 15),
      dataPagamento: DateTime(2026, 6, 15),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
      categoria: 'recebimentos_fiado',
      tipo: FinanceiroTipoLancamento.entradaExtra,
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final antes = FinanceiroLancamentoExclusaoService.lancamentosRelatorioMesAtual(
      box: box,
      lojaId: lojaId,
      referencia: DateTime(2026, 6, 1),
    );
    expect(antes.any((x) => x.id == l.id), isTrue);

    final r =
        await FinanceiroLancamentoExclusaoService.excluirSomenteLancamentoFinanceiroLegado(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(r.sucesso, isTrue);

    final depois = FinanceiroService.lancamentosPagosNoPeriodo(
      box,
      lojaId,
      DateTime(2026, 6, 1),
      DateTime(2026, 6, 30, 23, 59, 59, 999),
    );
    expect(depois.any((x) => x.id == l.id), isFalse);
  });
}
