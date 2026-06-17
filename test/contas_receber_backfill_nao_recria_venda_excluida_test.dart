// Backfill não recria contas de venda excluída do Firestore.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/conta_receber_venda_backfill.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-cr-backfill-exc';
  const vendaId = 'venda-backfill-exc-uuid';

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_bf_exc_');
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

  test('backfill ignora venda ausente no Firestore (excluída)', () async {
    final firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        clienteNome: 'Orfã',
        produtosDescricao: 'Anel',
        quantidade: 1,
        preco: 60,
        total: 60,
        formasPagamento: 'Fiado - R\$ 60,00. Vencimento: 10/09/2026',
        data: DateTime(2026, 6, 10),
        tamanho: '',
        vendedor: 'L',
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

    // Venda não existe em estoque_vendas (foi excluída remotamente)
    final r = await ContaReceberVendaBackfillService.backfillFromVendasFiadas(
      lojaId,
    );
    expect(r.criadas, 0);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(crBox, isEmpty);

    final qs = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .get();
    expect(qs.docs, isEmpty);

    await crBox.close();
    await vendasBox.close();
  });
}
