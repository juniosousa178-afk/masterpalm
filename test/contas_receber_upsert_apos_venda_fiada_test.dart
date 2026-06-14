// Republicação pós-syncVenda: conta local Hive → Firestore.

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

  const lojaId = 'loja-cr-upsert-pos-venda';
  const vendaId = 'venda-upsert-pos-sync-20260614';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_upsert_pos_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final crName = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(crName)) {
      await Hive.box<ContaReceber>(crName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(crName);
    } catch (_) {}
  });

  test('republicarContasVinculadasAVenda publica conta após vendaIdFirebase', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final venda = Venda(
      clienteNome: 'Maria PC',
      produtosDescricao: 'Anel',
      quantidade: 1,
      preco: 180,
      total: 180,
      formasPagamento: 'Fiado - R\$ 180,00. Vencimento: 15/07/2026',
      data: DateTime(2026, 6, 14),
      tamanho: '',
      vendedor: 'Loja',
      frete: 0,
      desconto: 0,
      observacao: 'Venda fiada',
      pagamentoDinheiro: 0,
      pagamentoPix: 0,
      pagamentoCartao: 0,
      lojaId: lojaId,
      idFirebase: vendaId,
    );

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Maria PC',
        valor: 180,
        valorOriginal: 180,
        dataVencimento: DateTime(2026, 7, 15),
        dataVenda: venda.data,
        vendaKey: -1,
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
        parcelaTotal: 1,
      ),
    );

    final docId = 'cr_${vendaId}_p1';
    final antes = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(antes.exists, isFalse);

    final qtd = await ContaReceberVendaBackfillService.republicarContasVinculadasAVenda(
      lojaId: lojaId,
      venda: venda,
    );
    expect(qtd, 1);

    final depois = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(depois.exists, isTrue);
    expect(depois.data()?['vendaIdFirebase'], vendaId);
    expect(depois.data()?['contaReceberId'], docId);
    expect(resolveContaReceberDocId(crBox.values.first), docId);

    await crBox.close();
  });

  test('republicar não sobrescreve remoto mais novo na segunda chamada backfill', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    const docId = 'cr_venda-upsert-pos-sync-20260614_p1';
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
      'valorOriginal': 180.0,
      'valorPago': 50.0,
      'saldoAtual': 130.0,
      'valor': 130.0,
      'status': ContaReceberStatus.parcial,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': DateTime(2026, 7, 15),
      'dataVenda': DateTime(2026, 6, 14),
      'historicoPagamentos': [
        {
          'baixaId': 'bx_remoto',
          'valor': 50.0,
          'data': DateTime(2026, 6, 15).toIso8601String(),
          'forma': 'Pix',
          'estornada': false,
        },
      ],
      'cancelada': false,
      'schemaVersion': 1,
      'updatedAt': DateTime(2026, 6, 15),
    });

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Maria PC',
        produtosDescricao: 'Anel',
        quantidade: 1,
        preco: 180,
        total: 180,
        formasPagamento: 'Fiado - R\$ 180,00. Vencimento: 15/07/2026',
        data: DateTime(2026, 6, 14),
        tamanho: '',
        vendedor: 'Loja',
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

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Maria PC',
        valor: 180,
        valorOriginal: 180,
        dataVencimento: DateTime(2026, 7, 15),
        dataVenda: DateTime(2026, 6, 14),
        vendaKey: -1,
        vendaIdFirebase: vendaId,
        parcelaNumero: 1,
      ),
    );

    final backfill =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(backfill.criadas, 0);
    expect(backfill.jaExistiam, 1);

    final snap = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId)
        .get();
    expect(snap.data()?['valorPago'], closeTo(50, 0.01));
    expect(snap.data()?['saldoAtual'], closeTo(130, 0.01));

    final pull = await ContaReceberService.sincronizarRemoto(lojaId);
    expect(pull.atualizados + pull.importados, greaterThanOrEqualTo(1));

    final local = crBox.values.firstWhere(
      (c) => c.vendaIdFirebase == vendaId,
    );
    expect(local.saldoRestante, closeTo(130, 0.01));

    await crBox.close();
    await vendasBox.close();
  });
}
