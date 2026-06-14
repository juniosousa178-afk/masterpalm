// PC grava venda fiada remota; mobile só tem venda no Hive → Contas a Receber.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-fiado-pc-mobile-20260614';
  const vendaId = 'pc-venda-fiada-uuid-mobile';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_pc_mobile_cr_');
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

  test('mobile com venda fiada remota passa a listar conta após sincronizarRemoto', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    // Simula estoque_vendas já sincronizado (PC → nuvem → mobile pull vendas).
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({
      'id': vendaId,
      'clienteNome': 'Cliente PC',
      'total': 320.0,
      'formasPagamento': 'Fiado - R\$ 320,00. Vencimento: 20/08/2026',
      'data': Timestamp.fromDate(DateTime(2026, 6, 14)),
      'pagamentoDinheiro': 0.0,
      'pagamentoPix': 0.0,
      'pagamentoCartao': 0.0,
      'lojaId': lojaId,
    });

    // Mobile: venda no Hive, sem conta local (cenário relatado).
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Cliente PC',
        produtosDescricao: 'Colar',
        quantidade: 1,
        preco: 320,
        total: 320,
        formasPagamento: 'Fiado - R\$ 320,00. Vencimento: 20/08/2026',
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

    final docId = 'cr_${vendaId}_p1';
    final remoto = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(remoto.exists, isTrue);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 1);
    expect(pendentes.first.vendaIdFirebase, vendaId);
    expect(pendentes.first.valor, closeTo(320, 0.01));
    expect(pendentes.first.clienteNome, 'Cliente PC');
    await crBox.close();
    await vendasBox.close();
  });

  test('segunda sincronização não duplica conta no Hive', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Cliente PC',
        produtosDescricao: 'Colar',
        quantidade: 1,
        preco: 320,
        total: 320,
        formasPagamento: 'Fiado - R\$ 320,00. Vencimento: 20/08/2026',
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

    await ContaReceberService.sincronizarRemoto(lojaId);
    await ContaReceberService.sincronizarRemoto(lojaId);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(crBox.length, 1);
    await crBox.close();
    await vendasBox.close();
  });
}
