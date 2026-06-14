// Baixa fiado: reconciliação cross-device via lançamentos financeiros remotos.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/conta_receber_lancamento_vinculo.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/financeiro/financeiro_constants.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/services/conta_receber_financeiro_sync_service.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/financeiro_firestore_service.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-fiado-sync-desktop-mobile';
  const vendaId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  late Directory hiveDir;
  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_fiado_sync_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  tearDownAll(() async {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    FinanceiroFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
  });

  tearDown(() async {
    FinanceiroFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    for (final name in [
      HiveBoxNames.contasReceber(lojaId),
      HiveBoxNames.contasReceber('${lojaId}-bloqueio'),
      HiveBoxNames.lancamentosFinanceiros(lojaId),
      HiveBoxNames.lancamentosFinanceiros('${lojaId}-bloqueio'),
    ]) {
      if (!Hive.isBoxOpen(name)) continue;
      try {
        await Hive.box<ContaReceber>(name).close();
      } catch (_) {
        try {
          await Hive.box<LancamentoFinanceiro>(name).close();
        } catch (_) {
          try {
            await Hive.box(name).close();
          } catch (_) {}
        }
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  ContaReceber contaFiada({
    required String loja,
    required double valor,
  }) {
    return ContaReceber(
      lojaId: loja,
      clienteNome: 'Cliente Sync',
      valor: valor,
      valorOriginal: valor,
      dataVencimento: DateTime(2026, 6, 20),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
    );
  }

  test('baixa no desktop (Firestore) aparece na conta local do mobile após pull', () async {
    const valorBaixa = 100.0;
    final data = DateTime(2026, 6, 10);
    final stable = '${vendaId}_p1';
    final ref = referenciaExternaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valorBaixa,
      dataRecebimento: data,
    );
    final docId = lancamentoFinanceiroDocIdParaContaReceberStable(
      contaReceberStableId: stable,
      parcelaNumero: 1,
      valor: valorBaixa,
      dataRecebimento: data,
    );

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('lancamentos_financeiros')
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'descricao': 'Recebimento — Cliente Sync',
      'valor': valorBaixa,
      'tipo': FinanceiroTipoLancamento.entradaExtra,
      'categoria': 'recebimentos_fiado',
      'subcategoria': '',
      'status': FinanceiroStatusLancamento.pago,
      'formaPagamento': 'Pix',
      'fornecedor': '',
      'observacao': 'Conta a receber',
      'dataLancamento': data,
      'dataPagamento': data,
      'competenciaMes': data.month,
      'competenciaAno': data.year,
      'recorrente': false,
      'origem': FinanceiroOrigemLancamento.contaReceberFiado,
      'usuarioId': '',
      'usuarioNome': '',
      'centroCusto': '',
      'anexoComprovante': '',
      'referenciaExterna': ref,
      'solicitarAtualizacaoEstoque': false,
    });

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(contaFiada(loja: lojaId, valor: 200));
    final conta = crBox.values.first;
    expect(conta.saldoRestante, closeTo(200, 0.01));

    final resultado = await ContaReceberFinanceiroSyncService.reconciliarBaixasRemotas(
      lojaId: lojaId,
      puxarFirestore: true,
    );

    expect(resultado.baixasAplicadas, 1);
    expect(conta.saldoRestante, closeTo(100, 0.01));
    expect(conta.valorPago, closeTo(100, 0.01));
    expect(conta.status, ContaReceberStatus.parcial);
  });

  test('registrarBaixa bloqueia quando remoto já quitou saldo', () async {
    const lojaBloqueio = '${lojaId}-bloqueio';
    const valorTotal = 80.0;
    final data = DateTime(2026, 6, 12);
    final contaBase = contaFiada(loja: lojaBloqueio, valor: valorTotal);
    final docId = resolveContaReceberDocId(contaBase);

    await firestore
        .collection('lojas')
        .doc(lojaBloqueio)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaBloqueio,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Cliente Sync',
      'valorOriginal': valorTotal,
      'valorPago': valorTotal,
      'saldoAtual': 0.0,
      'valor': 0.0,
      'status': ContaReceberStatus.paga,
      'pago': true,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 6, 20)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
      'historicoPagamentos': [
        {
          'baixaId': baixaIdDeterministico(
            contaReceberId: docId,
            valor: valorTotal,
            dataRecebimento: data,
            formaPagamento: 'Dinheiro',
          ),
          'valor': valorTotal,
          'data': data.toIso8601String(),
          'forma': 'Dinheiro',
          'estornada': false,
        },
      ],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': Timestamp.fromDate(data),
    });

    final crBox = await ContaReceberService.openBoxLoja(lojaBloqueio);
    contaBase.idFirebase = docId;
    await crBox.add(contaBase);
    final conta = crBox.values.first;
    final key = conta.key as int;

    final r = await ContaReceberService.registrarBaixa(
      conta: conta,
      valorRecebido: valorTotal,
      formaPagamento: 'Pix',
      lojaId: lojaBloqueio,
      contaHiveKey: key,
    );

    expect(r.sucesso, isFalse);
    expect(r.mensagemErro, contains('sincronizado'));

    final finBox = await FinanceiroHiveStore.openLancamentosBox(lojaBloqueio);
    final pagos = finBox!.values.where(
      (l) =>
          l.origem == FinanceiroOrigemLancamento.contaReceberFiado &&
          l.status == FinanceiroStatusLancamento.pago,
    );
    expect(pagos, isEmpty);
  });
}
