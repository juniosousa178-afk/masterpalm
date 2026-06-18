// Exclusão manual de lançamento financeiro (soft delete).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-excl-manual';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_exc_');
    Hive.init(dir.path);
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

  test('excluirLancamentoManual remove do Hive e marca deletedAt no Firestore', () async {
    final box = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final l = LancamentoFinanceiro(
      id: 'lf-manual-1',
      lojaId: lojaId,
      descricao: 'Ajuste caixa',
      valor: 25,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: DateTime(2026, 6, 10),
      origem: FinanceiroOrigemLancamento.manual,
    );
    await box!.put(l.id, l);

    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
      motivoExclusao: 'teste',
    );

    expect(r.sucesso, isTrue);
    expect(box.get(l.id), isNull);

    final snap = await FinanceiroFirestoreService.debugFirestoreOverride!
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(l.id)
        .get();
    expect(snap.data()?['deletedAt'], isNotNull);
    expect(snap.data()?['motivoExclusao'], 'teste');
  });

  test('exclusão manual é idempotente', () async {
    final l = LancamentoFinanceiro(
      id: 'lf-manual-idem',
      lojaId: lojaId,
      descricao: 'X',
      valor: 10,
      dataLancamento: DateTime(2026, 6, 11),
    );
    final r = await FinanceiroLancamentoExclusaoService.excluirLancamentoManual(
      lojaId: lojaId,
      lancamento: l,
    );
    expect(r.sucesso, isTrue);
    expect(r.idempotente, isTrue);
  });
}
