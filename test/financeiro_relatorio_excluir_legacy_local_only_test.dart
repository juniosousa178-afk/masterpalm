// Exclusão local-only (sem Firestore) marca apenasLocal e remove do Hive.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-rel-exc-local-only';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_rel_loc_only_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('legacy sem Firebase retorna apenasLocal e remove do Hive', () async {
    final agora = DateTime(2026, 6, 8);
    final l = LancamentoFinanceiro(
      id: 'uuid-local-only-rel',
      lojaId: lojaId,
      descricao: 'Despesa antiga',
      valor: 19,
      dataLancamento: agora,
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isTrue);
    expect(r.apenasLocal, isTrue);
    expect(box.get(l.id), isNull);
  });
}
