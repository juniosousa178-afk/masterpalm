// Backfill idempotente: venda fiada no Hive sem conta remota → contas_receber.

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

  const lojaId = 'loja-cr-backfill-vendas';
  const vendaId = 'venda-backfill-uuid-20260614';

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_cr_backfill_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDownAll(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
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

  Venda vendaFiadaHive({String? idFirebase}) {
    final venc = DateTime(2026, 8, 15);
    return Venda(
      clienteNome: 'Cliente Backfill',
      produtosDescricao: 'Prod X',
      quantidade: 1,
      preco: 250,
      total: 250,
      formasPagamento:
          'Fiado - R\$ 250,00. Vencimento: ${venc.day.toString().padLeft(2, '0')}/${venc.month.toString().padLeft(2, '0')}/${venc.year}',
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
      idFirebase: idFirebase ?? vendaId,
    );
  }

  test('venda fiada remota sem conta cria doc cr_{vendaId}_p1', () async {
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(vendaFiadaHive());

    final resultado =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(resultado.criadas, 1);
    expect(resultado.jaExistiam, 0);

    final docId = 'cr_${vendaId}_p1';
    final firestore = ContaReceberFirestoreService.debugFirestoreOverride!;
    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.exists, isTrue);
    expect(snap.data()?['vendaIdFirebase'], vendaId);
    expect(snap.data()?['saldoAtual'], closeTo(250, 0.01));
  });

  test('backfill idempotente não duplica se conta remota já existe', () async {
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(vendaFiadaHive());

    final docId = 'cr_${vendaId}_p1';
    final firestore = ContaReceberFirestoreService.debugFirestoreOverride!;
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Remoto',
      'valorOriginal': 250.0,
      'valorPago': 0.0,
      'saldoAtual': 250.0,
      'valor': 250.0,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': DateTime(2026, 8, 15),
      'dataVenda': DateTime(2026, 6, 14),
      'historicoPagamentos': [],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': DateTime(2026, 6, 14),
    });

    final r1 =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r1.criadas, 0);
    expect(r1.jaExistiam, 1);

    final r2 =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r2.criadas, 0);
    expect(r2.jaExistiam, 1);

    final docs = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .get();
    expect(docs.docs.length, 1);
  });

  test('sincronizarRemoto puxa conta backfill para Hive local', () async {
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(vendaFiadaHive());

    final pull = await ContaReceberService.sincronizarRemoto(lojaId);
    expect(pull.importados + pull.atualizados, greaterThanOrEqualTo(1));

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final list = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(list.length, 1);
    expect(list.first.vendaIdFirebase, vendaId);
    expect(resolveContaReceberDocId(list.first), 'cr_${vendaId}_p1');
    await crBox.close();
  });

  test('venda sem idFirebase estável é ignorada no backfill', () async {
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(vendaFiadaHive(idFirebase: ''));

    final resultado =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(resultado.criadas, 0);
    expect(resultado.ignoradas, greaterThanOrEqualTo(1));
  });
}
