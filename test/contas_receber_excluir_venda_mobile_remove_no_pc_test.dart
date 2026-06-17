// Celular exclui venda fiada → PC puxa tombstone e parcelas somem.

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

  const lojaId = 'loja-cr-exc-mobile-pc';
  const vendaId = 'venda-exc-mobile-pc-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_exc_mob_pc_');
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

  test('celular exclui venda → PC sincroniza e parcelas somem', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({
      'id': vendaId,
      'lojaId': lojaId,
      'clienteNome': 'Cliente Exc',
      'total': 200.0,
      'saldoFiado': 200.0,
      'formasPagamento':
          'Fiado - R\$ 200,00. Vencimento: 15/07/2026 Parcelas fiado: 2.',
      'data': Timestamp.fromDate(DateTime(2026, 6, 15)),
    });

    for (var p = 1; p <= 2; p++) {
      final conta = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente Exc',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 7, 14 + p),
        dataVenda: DateTime(2026, 6, 15),
        vendaKey: 1,
        vendaIdFirebase: vendaId,
        parcelaNumero: p,
        parcelaTotal: 2,
      );
      normalizarContaReceberId(conta);
      expect(
        await ContaReceberFirestoreService.upsertContaReceber(
          conta,
          lastWriteOrigin: 'venda_fiada',
        ),
        isTrue,
      );
    }

    // Simula PC com Hive já sincronizado
    final crPc = await ContaReceberService.openBoxLoja(lojaId);
    for (var p = 1; p <= 2; p++) {
      final local = ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente Exc',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 7, 14 + p),
        dataVenda: DateTime(2026, 6, 15),
        vendaKey: 99,
        vendaIdFirebase: vendaId,
        parcelaNumero: p,
        parcelaTotal: 2,
        idFirebase: 'cr_${vendaId}_p$p',
      );
      await crPc.add(local);
    }
    expect(
      ContaReceberService.listar(
        contas: crPc.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      ).length,
      2,
    );
    await crPc.close();

    // Simula celular: cancela só no Firestore (Hive do celular é outro dispositivo)
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

    final p1 = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc('cr_${vendaId}_p1')
        .get();
    expect(p1.data()?['cancelada'], isTrue);

    // PC puxa remoto
    await ContaReceberService.sincronizarRemoto(lojaId);

    final crDepois = await ContaReceberService.openBoxLoja(lojaId);
    final pendentes = ContaReceberService.listar(
      contas: crDepois.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes, isEmpty);
    await crDepois.close();
  });
}
