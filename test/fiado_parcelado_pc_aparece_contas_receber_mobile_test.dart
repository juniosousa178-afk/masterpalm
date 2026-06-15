// PC venda 100% fiado em 2 parcelas → mobile sincroniza Contas a Receber.

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

  const lojaId = 'loja-fiado-parcelado-pc-mobile';
  const vendaId = 'pc-fiado-parcelado-2x-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_parc_mob_');
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
        await Hive.box(name).close();
      }
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  test('mobile com venda fiada parcelada remota lista 2 parcelas após sincronizarRemoto', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({
      'id': vendaId,
      'clienteNome': 'Cliente Parcelado',
      'total': 200.0,
      'formasPagamento':
          'Fiado - R\$ 200,00. Vencimento: 20/08/2026 Parcelas fiado: 2. Intervalo: 30 dias.',
      'data': Timestamp.fromDate(DateTime(2026, 6, 14)),
      'pagamentoDinheiro': 0.0,
      'pagamentoPix': 0.0,
      'pagamentoCartao': 0.0,
      'saldoFiado': 200.0,
      'quantidadeParcelasFiado': 2,
      'intervaloParcelasDias': 30,
      'dataVencimentoFiado': DateTime(2026, 8, 20).toIso8601String(),
      'lojaId': lojaId,
    });

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Cliente Parcelado',
        produtosDescricao: 'Colar',
        quantidade: 1,
        preco: 200,
        total: 200,
        formasPagamento:
            'Fiado - R\$ 200,00. Vencimento: 20/08/2026 Parcelas fiado: 2. Intervalo: 30 dias.',
        data: DateTime(2026, 6, 14),
        tamanho: '',
        vendedor: 'Vendedor',
        frete: 0,
        desconto: 0,
        observacao: '',
        pagamentoDinheiro: 0,
        pagamentoPix: 0,
        pagamentoCartao: 0,
        lojaId: lojaId,
        idFirebase: vendaId,
      ),
    );

    final crAntes = await ContaReceberService.openBoxLoja(lojaId);
    expect(crAntes, isEmpty);
    await crAntes.close();

    await ContaReceberService.sincronizarRemoto(lojaId);

    for (final n in [1, 2]) {
      final docId = 'cr_${vendaId}_p$n';
      final remoto = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.contasReceberCol)
          .doc(docId)
          .get();
      expect(remoto.exists, isTrue, reason: 'doc $docId ausente no Firestore');
    }

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 2);
    expect(
      pendentes.fold<double>(0, (s, c) => s + c.valor),
      closeTo(200, 0.01),
    );
    expect(
      pendentes.map((c) => resolveContaReceberDocId(c)).toSet(),
      {'cr_${vendaId}_p1', 'cr_${vendaId}_p2'},
    );
    await crBox.close();
    await vendasBox.close();
  });
}
