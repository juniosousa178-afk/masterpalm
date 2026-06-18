// Manual antigo sem doc Firestore: remove local mesmo se remoto falhar.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-sem-fs';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_sem_fs_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  test('exclusão local ok sem Firebase configurado', () async {
    final l = LancamentoFinanceiro(
      id: 'local-only-old-1',
      lojaId: lojaId,
      descricao: 'Despesa velha',
      valor: 12,
      dataLancamento: DateTime(2023, 8, 1),
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );

    expect(r.sucesso, isTrue);
    expect(box.length, 0);
  });
}
