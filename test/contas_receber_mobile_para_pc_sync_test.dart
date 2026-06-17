// Mobile publica conta fiada → PC puxa Firestore e exibe.

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

  const lojaId = 'loja-cr-mobile-para-pc';
  const vendaId = 'venda-mobile-para-pc-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_mob_pc_');
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

  test('mobile cria conta no Firestore → PC sincroniza e lista pendente', () async {
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
      'clienteNome': 'Cliente Mobile',
      'total': 80.0,
      'pagamentoDinheiro': 0.0,
      'pagamentoPix': 0.0,
      'pagamentoCartao': 0.0,
      'saldoFiado': 80.0,
      'formasPagamento': 'Fiado - R\$ 80,00. Vencimento: 10/08/2026',
      'data': Timestamp.fromDate(DateTime(2026, 6, 15)),
    });

    final contaMobile = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente Mobile',
      valor: 80,
      valorOriginal: 80,
      dataVencimento: DateTime(2026, 8, 10),
      dataVenda: DateTime(2026, 6, 15),
      vendaKey: 2,
      vendaIdFirebase: vendaId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    normalizarContaReceberId(contaMobile);
    expect(
      await ContaReceberFirestoreService.upsertContaReceber(
        contaMobile,
        lastWriteOrigin: 'venda_fiada',
      ),
      isTrue,
    );

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Cliente Mobile',
        produtosDescricao: 'Pulseira',
        quantidade: 1,
        preco: 80,
        total: 80,
        formasPagamento: 'Fiado - R\$ 80,00. Vencimento: 10/08/2026',
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
    expect(resolveContaReceberDocId(pendentes.first), 'cr_${vendaId}_p1');
    await crBox.close();
  });
}
