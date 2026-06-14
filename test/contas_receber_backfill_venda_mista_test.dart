// Venda mista Pix + fiado: backfill cria contas a receber.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_venda_backfill.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-backfill-mista';
  const vendaId = 'venda-mista-pix-fiado-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_mista_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  setUp(() {
    ContaReceberFirestoreService.debugFirestoreOverride =
        FakeFirebaseFirestore();
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final vendasName = HiveBoxNames.vendas(lojaId);
    if (Hive.isBoxOpen(vendasName)) {
      await Hive.box<Venda>(vendasName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(vendasName);
    } catch (_) {}
    final crName = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(crName)) {
      await Hive.box<ContaReceber>(crName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(crName);
    } catch (_) {}
  });

  test('venda mista sem texto Fiado em formasPagamento ainda gera backfill', () async {
    final firestore = ContaReceberFirestoreService.debugFirestoreOverride!;
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Junio',
        produtosDescricao: 'Prod',
        quantidade: 1,
        preco: 100,
        total: 100,
        formasPagamento: 'Pagamento Pix: R\$ 50,00',
        data: DateTime(2026, 6, 14),
        tamanho: '',
        vendedor: 'Loja',
        frete: 0,
        desconto: 0,
        observacao: '',
        pagamentoDinheiro: 0,
        pagamentoPix: 50,
        pagamentoCartao: 0,
        lojaId: lojaId,
        idFirebase: vendaId,
      ),
    );

    final r =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r.criadas, 1);

    final docId = 'cr_${vendaId}_p1';
    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()?['saldoAtual'], closeTo(50, 0.01));
  });

  test('metadados Firestore com 2 parcelas geram cr_p1 e cr_p2', () async {
    final firestore = ContaReceberFirestoreService.debugFirestoreOverride!;
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({
      'total': 100.0,
      'pagamentoPix': 50.0,
      'pagamentoDinheiro': 0.0,
      'pagamentoCartao': 0.0,
      'formasPagamento':
          'Pagamento Pix: R\$ 50,00\nFiado - R\$ 50,00. Vencimento: 15/07/2026 Parcelas fiado: 2. Intervalo: 30 dias.',
      'saldoFiado': 50.0,
      'quantidadeParcelasFiado': 2,
      'intervaloParcelasDias': 30,
      'dataVencimentoFiado': DateTime(2026, 7, 15).toIso8601String(),
    });

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Junio',
        produtosDescricao: 'Prod',
        quantidade: 1,
        preco: 100,
        total: 100,
        formasPagamento: 'Pagamento Pix: R\$ 50,00',
        data: DateTime(2026, 6, 14),
        tamanho: '',
        vendedor: 'Loja',
        frete: 0,
        desconto: 0,
        observacao: '',
        pagamentoDinheiro: 0,
        pagamentoPix: 50,
        pagamentoCartao: 0,
        lojaId: lojaId,
        idFirebase: vendaId,
      ),
    );

    final r =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r.criadas, 2);

    for (final p in [1, 2]) {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.contasReceberCol)
          .doc('cr_${vendaId}_p$p')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()?['valorOriginal'], closeTo(25, 0.01));
      expect(snap.data()?['parcelaNumero'], p);
      expect(snap.data()?['parcelaTotal'], 2);
    }
  });
}
