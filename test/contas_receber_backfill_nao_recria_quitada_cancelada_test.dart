// Backfill não recria conta quando venda já tem parcela quitada localmente.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/conta_receber_venda_backfill.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-backfill-nao-recria-quitada';
  const vendaId = 'venda-backfill-quitada-maio';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_bf_quit_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VendaAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final crName = HiveBoxNames.contasReceber(lojaId);
    final vendasName = HiveBoxNames.vendas(lojaId);
    if (Hive.isBoxOpen(crName)) {
      await Hive.box<ContaReceber>(crName).close();
    }
    if (Hive.isBoxOpen(vendasName)) {
      await Hive.box<Venda>(vendasName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(crName);
      await Hive.deleteBoxFromDisk(vendasName);
    } catch (_) {}
  });

  test('backfill ignora venda com parcela canônica já quitada no Hive', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    final venda = Venda(
      lojaId: lojaId,
      clienteNome: 'Cliente',
      produtosDescricao: 'Produto teste',
      quantidade: 1,
      preco: 100,
      total: 100,
      formasPagamento: 'Fiado — Vencimento: 15/05/2026',
      data: DateTime(2026, 5, 5),
      vendedor: 'Teste',
      observacao: '',
      pagamentoDinheiro: 0,
      pagamentoPix: 0,
      pagamentoCartao: 0,
      idFirebase: vendaId,
    );
    await vendasBox.add(venda);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final quitada = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente',
      valor: 0,
      valorOriginal: 100,
      valorPago: 100,
      pago: true,
      status: ContaReceberStatus.paga,
      dataVencimento: DateTime(2026, 5, 15),
      dataVenda: DateTime(2026, 5, 5),
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(quitada);
    await crBox.add(quitada);

    final r = await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r.criadas, 0);

    final docId = 'cr_${vendaId}_p1';
    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isFalse);
    expect(crBox.length, 1);
  });
}
