// Estorno legado sem vínculo seguro retorna bloqueado com mensagem clara.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/financeiro_lancamento_legacy_resolver.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-rel-estorno-bloq';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_rel_est_bloq_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('baixa CR legada sem vínculo retorna bloqueado', () async {
    final l = LancamentoFinanceiro(
      id: 'cr-legado-sem-vinc',
      lojaId: lojaId,
      descricao: 'Recebimento — Cliente Inexistente',
      valor: 99,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      categoria: 'recebimentos_fiado',
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 3),
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      observacao: 'Conta a receber',
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r =
        await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isFalse);
    expect(r.bloqueado, isTrue);
    expect(
      r.mensagemErro,
      FinanceiroLancamentoLegacyResolver.msgEstornoLegadoSemVinculo,
    );
    expect(box.get(l.id), isNotNull);
  });
}
