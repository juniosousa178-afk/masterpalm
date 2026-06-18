// Estorno no PC remove LF remoto; mobile aplica tombstone no pull.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/financeiro_lancamento_exclusao_service.dart';

void main() {
  const lojaId = 'loja-fin-sync-estorno';
  const vendaId = 'venda-sync-estorno-uuid';

  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fin_sync_est_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    FinanceiroFirestoreService.debugFirestoreOverride = firestore;
  });

  tearDown(() async {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
    final finName = HiveBoxNames.lancamentosFinanceiros(lojaId);
    if (Hive.isBoxOpen(finName)) {
      await Hive.box<LancamentoFinanceiro>(finName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(finName);
    } catch (_) {}
  });

  test('estorno no dispositivo A remove LF no dispositivo B via tombstone', () async {
    const valorBaixa = 55.0;
    final data = DateTime(2026, 6, 9);
    final stable = '${vendaId}_p1';

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Sync',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 7, 1),
        dataVenda: DateTime(2026, 6, 1),
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );
    final conta = crBox.values.first;
    ContaReceberService.aplicarBaixaNaConta(
      conta: conta,
      valorRecebido: valorBaixa,
      formaPagamento: 'Pix',
      dataRecebimento: data,
    );
    await conta.save();

    final lanc = LancamentoFinanceiro(
      id: lancamentoFinanceiroDocIdParaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valorBaixa,
        dataRecebimento: data,
      ),
      lojaId: lojaId,
      descricao: 'R',
      valor: valorBaixa,
      tipo: FinanceiroTipoLancamento.entradaExtra,
      status: FinanceiroStatusLancamento.pago,
      dataLancamento: data,
      origem: FinanceiroOrigemLancamento.contaReceberFiado,
      referenciaExterna: referenciaExternaContaReceberStable(
        contaReceberStableId: stable,
        parcelaNumero: 1,
        valor: valorBaixa,
        dataRecebimento: data,
      ),
    );

    final finBoxB = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    await finBoxB!.put(lanc.id, lanc);
    await FinanceiroFirestoreService.upsertLancamento(lanc);

    // Dispositivo A: estorna (remove local + marca tombstone remoto)
    final r = await FinanceiroLancamentoExclusaoService.estornarBaixaContaReceber(
      lojaId: lojaId,
      lancamento: lanc,
    );
    expect(r.sucesso, isTrue);

    // Dispositivo B: cache Hive desatualizado (simula não ter recebido o estorno ainda)
    await finBoxB.put(lanc.id, lanc);
    expect(finBoxB.get(lanc.id), isNotNull);

    final removidos =
        await FinanceiroFirestoreService.sincronizarTombstonesLancamentos(lojaId);
    expect(removidos, 1);
    expect(finBoxB.get(lanc.id), isNull);

    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(lanc.id)
        .get();
    expect(snap.data()?['estornado'], isTrue);
    expect(snap.data()?['deletedAt'], isNotNull);
  });
}
