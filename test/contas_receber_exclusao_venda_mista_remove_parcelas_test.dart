// Exclusão de venda mista Pix+fiado remove somente parcelas do fiado.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-exc-mista';
  const vendaId = 'venda-exc-mista-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_exc_mista_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    for (final name in [
      HiveBoxNames.vendas(lojaId),
      HiveBoxNames.contasReceber(lojaId),
    ]) {
      if (Hive.isBoxOpen(name)) {
      try {
        await Hive.box<ContaReceber>(name).close();
      } catch (_) {
        try {
          await Hive.box<Venda>(name).close();
        } catch (_) {
          await Hive.box(name).close();
        }
      }
    }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('excluir venda mista cancela p1/p2 do fiado no outro dispositivo', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({
      'total': 100.0,
      'pagamentoPix': 50.0,
      'saldoFiado': 50.0,
      'quantidadeParcelasFiado': 2,
      'clienteNome': 'Mista',
      'formasPagamento':
          'Pagamento Pix: R\$ 50,00\nFiado - R\$ 50,00. Vencimento: 15/07/2026 Parcelas fiado: 2.',
      'data': Timestamp.fromDate(DateTime(2026, 6, 14)),
    });

    for (var p = 1; p <= 2; p++) {
      final conta = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Mista',
        valor: 25,
        valorOriginal: 25,
        dataVencimento: DateTime(2026, 7, 14 + p),
        dataVenda: DateTime(2026, 6, 14),
        vendaIdFirebase: vendaId,
        parcelaNumero: p,
        parcelaTotal: 2,
      );
      normalizarContaReceberId(conta);
      await ContaReceberFirestoreService.upsertContaReceber(
        conta,
        lastWriteOrigin: 'venda_fiada',
      );
    }

    final crOutro = await ContaReceberService.openBoxLoja(lojaId);
    for (var p = 1; p <= 2; p++) {
      await crOutro.add(
        ContaReceber(
          lojaId: lojaId,
          clienteNome: 'Mista',
          valor: 25,
          valorOriginal: 25,
          dataVencimento: DateTime(2026, 7, 14 + p),
          dataVenda: DateTime(2026, 6, 14),
          vendaIdFirebase: vendaId,
          idFirebase: 'cr_${vendaId}_p$p',
          parcelaNumero: p,
          parcelaTotal: 2,
        ),
      );
    }
    await crOutro.close();

    await ContaReceberFirestoreService.cancelarContasReceberDaVenda(
      lojaId: lojaId,
      vendaIdFirebase: vendaId,
    );
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .delete();

    await ContaReceberService.sincronizarRemoto(lojaId);

    final crDepois = await ContaReceberService.openBoxLoja(lojaId);
    expect(
      ContaReceberService.listar(
        contas: crDepois.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      ),
      isEmpty,
    );

    for (var p = 1; p <= 2; p++) {
      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.contasReceberCol)
          .doc('cr_${vendaId}_p$p')
          .get();
      expect(snap.data()?['cancelada'], isTrue);
    }
    await crDepois.close();
  });
}
