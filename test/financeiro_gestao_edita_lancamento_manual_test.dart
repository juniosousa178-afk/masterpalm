import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_edicao_service.dart';

void main() {
  const lojaId = 'loja-gestao-edit-man';

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('hive_gest_edit')).path);
    if (!Hive.isAdapterRegistered(30)) Hive.registerAdapter(LancamentoFinanceiroAdapter());
  });

  setUp(() => FinanceiroFirestoreService.debugFirestoreOverride = FakeFirebaseFirestore());
  tearDown(() => FinanceiroFirestoreService.debugFirestoreOverride = null);

  test('edita manual na gestão', () async {
    final l = LancamentoFinanceiro(
      id: 'edit-man',
      lojaId: lojaId,
      descricao: 'Antes',
      valor: 5,
      dataLancamento: DateTime(2026, 6, 1),
    );
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await box!.put(l.id, l);
    final r = await FinanceiroLancamentoEdicaoService.editarLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
      campos: FinanceiroLancamentoEdicaoCampos(
        descricao: 'Depois',
        valor: 7,
        dataLancamento: DateTime(2026, 6, 2),
      ),
    );
    expect(r.sucesso, isTrue);
    expect(box.get(l.id)!.descricao, 'Depois');
  });
}
