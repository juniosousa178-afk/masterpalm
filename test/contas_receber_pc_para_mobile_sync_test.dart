// PC publica conta fiada → mobile puxa Firestore e exibe.

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

  const lojaId = 'loja-cr-pc-para-mobile';
  const vendaId = 'venda-pc-para-mobile-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_pc_mob_');
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

  test('PC cria conta no Firestore → mobile sincroniza e lista pendente', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    // Simula PC: venda + upsert parcela no Firestore
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({
      'id': vendaId,
      'lojaId': lojaId,
      'clienteNome': 'Cliente PC',
      'total': 150.0,
      'pagamentoDinheiro': 0.0,
      'pagamentoPix': 0.0,
      'pagamentoCartao': 0.0,
      'saldoFiado': 150.0,
      'formasPagamento': 'Fiado - R\$ 150,00. Vencimento: 20/07/2026',
      'data': Timestamp.fromDate(DateTime(2026, 6, 15)),
    });

    final contaPc = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente PC',
      valor: 150,
      valorOriginal: 150,
      dataVencimento: DateTime(2026, 7, 20),
      dataVenda: DateTime(2026, 6, 15),
      vendaKey: 1,
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(contaPc);
    expect(
      await ContaReceberFirestoreService.upsertContaReceber(
        contaPc,
        lastWriteOrigin: 'venda_fiada',
      ),
      isTrue,
    );

    // Simula mobile: venda no Hive, CR vazio
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Cliente PC',
        produtosDescricao: 'Anel',
        quantidade: 1,
        preco: 150,
        total: 150,
        formasPagamento: 'Fiado - R\$ 150,00. Vencimento: 20/07/2026',
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

    final crAntes = await ContaReceberService.openBoxLoja(lojaId);
    expect(crAntes, isEmpty);
    await crAntes.close();

    await ContaReceberService.sincronizarRemoto(lojaId);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final pendentes = ContaReceberService.listar(
      contas: crBox.values,
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(pendentes.length, 1);
    expect(pendentes.first.vendaIdFirebase, vendaId);
    expect(pendentes.first.valor, closeTo(150, 0.01));
    await crBox.close();
  });
}
