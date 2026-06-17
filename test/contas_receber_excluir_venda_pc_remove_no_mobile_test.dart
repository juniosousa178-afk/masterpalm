// PC exclui venda fiada → celular puxa tombstone e parcelas somem.

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

  const lojaId = 'loja-cr-exc-pc-mobile';
  const vendaId = 'venda-exc-pc-mobile-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_exc_pc_mob_');
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

  test('PC exclui venda → celular sincroniza e parcelas somem', () async {
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
      'clienteNome': 'Cliente PC Exc',
      'total': 120.0,
      'saldoFiado': 120.0,
      'formasPagamento': 'Fiado - R\$ 120,00. Vencimento: 20/08/2026',
      'data': Timestamp.fromDate(DateTime(2026, 6, 16)),
    });

    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente PC Exc',
      valor: 120,
      valorOriginal: 120,
      dataVencimento: DateTime(2026, 8, 20),
      dataVenda: DateTime(2026, 6, 16),
      vendaKey: 5,
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(conta);
    expect(
      await ContaReceberFirestoreService.upsertContaReceber(
        conta,
        lastWriteOrigin: 'venda_fiada',
      ),
      isTrue,
    );

    // Simula celular com conta no Hive
    final crMob = await ContaReceberService.openBoxLoja(lojaId);
    await crMob.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente PC Exc',
        valor: 120,
        valorOriginal: 120,
        dataVencimento: DateTime(2026, 8, 20),
        dataVenda: DateTime(2026, 6, 16),
        vendaKey: 7,
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        parcelaTotal: 1,
        idFirebase: 'cr_${vendaId}_p1',
      ),
    );
    expect(
      ContaReceberService.listar(
        contas: crMob.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      ).length,
      1,
    );
    await crMob.close();

    // Simula PC: cancela só no Firestore
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
    await crDepois.close();
  });
}
