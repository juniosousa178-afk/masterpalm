// Firestore é fonte remota: pull inicial popula Hive antes do backfill.

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

  const lojaId = 'loja-cr-fonte-remota';
  const vendaId = 'venda-fonte-remota-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_fonte_rem_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final vendasName = HiveBoxNames.vendas(lojaId);
    final crName = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(vendasName)) {
      await Hive.box<Venda>(vendasName).close();
    }
    if (Hive.isBoxOpen(crName)) {
      await Hive.box<ContaReceber>(crName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(vendasName);
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk(crName);
    } catch (_) {}
  });

  test('pull inicial traz remoto mesmo sem venda local (só Firestore)', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final docId = 'cr_${vendaId}_p1';
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Remoto Only',
      'valorOriginal': 99.0,
      'valorPago': 0.0,
      'saldoAtual': 99.0,
      'valor': 99.0,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 15)),
      'cancelada': false,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 15, 10)),
    });

    final crAntes = await ContaReceberService.openBoxLoja(lojaId);
    expect(crAntes, isEmpty);
    await crAntes.close();

    final pull = await ContaReceberFirestoreService.pullContasReceberRemotas(
      lojaId,
    );
    expect(pull.importados, 1);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 1);
    expect(pendentes.first.clienteNome, 'Remoto Only');
    await crBox.close();
  });

  test('backfill importa remoto existente para Hive sem recriar doc', () async {
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
      'clienteNome': 'Backfill Import',
      'total': 60.0,
      'pagamentoDinheiro': 0.0,
      'pagamentoPix': 0.0,
      'pagamentoCartao': 0.0,
      'saldoFiado': 60.0,
      'formasPagamento': 'Fiado - R\$ 60,00. Vencimento: 05/07/2026',
      'data': Timestamp.fromDate(DateTime(2026, 6, 15)),
    });

    final docId = 'cr_${vendaId}_p1';
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Backfill Import',
      'valorOriginal': 60.0,
      'valorPago': 0.0,
      'saldoAtual': 60.0,
      'valor': 60.0,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 7, 5)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 15)),
      'cancelada': false,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 15, 11)),
    });

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Backfill Import',
        produtosDescricao: 'Item',
        quantidade: 1,
        preco: 60,
        total: 60,
        formasPagamento: 'Fiado - R\$ 60,00. Vencimento: 05/07/2026',
        data: DateTime(2026, 6, 15),
        tamanho: '',
        vendedor: 'V',
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

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(crBox.length, 1);
    final docs = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .get();
    expect(docs.docs.length, 1);
    await crBox.close();
  });
}
