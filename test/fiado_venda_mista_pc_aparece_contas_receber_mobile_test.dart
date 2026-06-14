// PC venda mista Pix+fiado → mobile sincroniza Contas a Receber.

import 'dart:io';

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

  const lojaId = 'loja-mista-pc-mobile';
  const vendaId = 'mista-pc-mobile-uuid-20260614';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_mista_mob_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
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

  test('mobile com venda mista remota lista 2 parcelas após sincronizarRemoto', () async {
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
      'pagamentoDinheiro': 0.0,
      'pagamentoCartao': 0.0,
      'clienteNome': 'Junio',
      'formasPagamento':
          'Pagamento Pix: R\$ 50,00\nFiado - R\$ 50,00. Vencimento: 15/07/2026 Parcelas fiado: 2. Intervalo: 30 dias.',
      'saldoFiado': 50.0,
      'quantidadeParcelasFiado': 2,
      'intervaloParcelasDias': 30,
      'dataVencimentoFiado': DateTime(2026, 7, 15).toIso8601String(),
      'data': DateTime(2026, 6, 14).toIso8601String(),
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

    await ContaReceberService.sincronizarRemoto(lojaId);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 2);
    expect(
      pendentes.fold<double>(0, (s, c) => s + c.valor),
      closeTo(50, 0.01),
    );
    expect(pendentes.every((c) => c.vendaIdFirebase == vendaId), isTrue);
    await crBox.close();
    await vendasBox.close();
  });
}
