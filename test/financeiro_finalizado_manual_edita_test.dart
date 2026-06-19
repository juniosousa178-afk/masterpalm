import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_edicao_service.dart';

void main() {
  const lojaId = 'loja-fin-finalizado-edit';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_fin_fin_edit')).path);
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  setUp(() {
    FinanceiroFirestoreService.debugFirestoreOverride = FakeFirebaseFirestore();
  });

  tearDown(() {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
  });

  test('manual finalizado pode ser editado', () async {
    final l = LancamentoFinanceiro(
      id: 'fin-edit-1',
      lojaId: lojaId,
      descricao: 'Antiga',
      valor: 10,
      status: FinanceiroStatusLancamento.finalizado,
      dataLancamento: DateTime(2026, 6, 5),
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);

    expect(FinanceiroLancamentoEdicaoService.podeEditar(l), isTrue);

    final r = await FinanceiroLancamentoEdicaoService.editarLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
      campos: FinanceiroLancamentoEdicaoCampos(
        descricao: 'Atualizada',
        valor: 15,
        dataLancamento: DateTime(2026, 6, 6),
        dataPagamento: DateTime(2026, 6, 6),
      ),
    );
    expect(r.sucesso, isTrue);
    expect(box.get(l.id)!.descricao, 'Atualizada');
    expect(box.get(l.id)!.valor, 15);
  });
}
