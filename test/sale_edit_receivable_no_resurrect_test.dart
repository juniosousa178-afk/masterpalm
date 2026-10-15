// Conta a receber cancelada pelo saleEdit (fiado → Pix) não volta como dívida
// a partir de um aparelho com cópia local antiga (venda fiada + conta pendente no Hive).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
import 'package:master_palm/core/conta_receber_remote_authority.dart';
import 'package:master_palm/core/conta_receber_venda_vinculo.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/conta_receber_venda_backfill.dart';
import 'package:master_palm/services/firestore_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-sale-edit-cr-resurrect';
  const vendaId = 'venda-fiado-virou-pix';
  const crId = 'cr_${vendaId}_p1';
  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cr_no_resurrect_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(29)) Hive.registerAdapter(ContaReceberAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    final cr = HiveBoxNames.contasReceber(lojaId), vendas = HiveBoxNames.vendas(lojaId);
    if (Hive.isBoxOpen(cr)) await Hive.box<ContaReceber>(cr).close();
    if (Hive.isBoxOpen(vendas)) await Hive.box<Venda>(vendas).close();
    for (final name in [cr, vendas]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  CollectionReference<Map<String, dynamic>> loja(String col) =>
      firestore.collection('lojas').doc(lojaId).collection(col);

  ContaReceber contaLocalPendente() {
    final c = ContaReceber(
      lojaId: lojaId, clienteNome: 'Cliente', valor: 8179, valorOriginal: 8179,
      dataVencimento: DateTime(2026, 10, 10), dataVenda: DateTime(2026, 9, 9),
      vendaKey: 40, vendaIdFirebase: vendaId, parcelaNumero: 1, parcelaTotal: 1,
    );
    normalizarContaReceberId(c);
    return c;
  }

  /// Estado remoto depois do saleEdit autoritativo + aparelho desatualizado.
  Future<Box<ContaReceber>> cenario({bool contaRemota = true, bool contaLocal = true}) async {
    firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    await loja(FSPaths.estoqueVendasCol).doc(vendaId).set({
      'lojaId': lojaId, 'total': 312, 'pagamentoPix': 312, 'saleEditRevision': 6,
      'formasPagamento': 'Pagamento Pix: R\$ 312.00',
    });
    if (contaRemota) {
      await loja(FSPaths.contasReceberCol).doc(crId).set({
        ...ContaReceberFirestoreService.mapContaReceber(contaLocalPendente(), docId: crId),
        'cancelada': true, 'deletedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 15)),
        'status': 'cancelada', 'saldoAtual': 0, 'valor': 0, 'pago': false,
        'motivoCancelamento': 'SALE_EDIT_REMOVED_FIADO', 'lastWriteOrigin': 'sale_edit_server',
      });
    }
    final vendas = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendas.add(Venda(
      lojaId: lojaId, clienteNome: 'Cliente', produtosDescricao: 'antiga', quantidade: 1,
      preco: 8179, total: 8179, formasPagamento: 'Fiado - R\$ 8179.00. Vencimento: 10/10/2026',
      data: DateTime(2026, 9, 9), vendedor: 'App', observacao: '', idFirebase: vendaId,
    ));
    final box = await ContaReceberService.openBoxLoja(lojaId);
    if (contaLocal) await box.add(contaLocalPendente());
    return box;
  }

  Future<Map<String, dynamic>?> remota() async => (await loja(FSPaths.contasReceberCol).doc(crId).get()).data();
  Future<int> docsRemotos() async => (await loja(FSPaths.contasReceberCol).get()).size;

  void expectTombstone(Map<String, dynamic>? d) {
    expect(d, isNotNull);
    expect(d!['cancelada'], isTrue);
    expect(d['status'], 'cancelada');
    expect(d['saldoAtual'], 0);
    expect(d['motivoCancelamento'], 'SALE_EDIT_REMOVED_FIADO');
  }

  test('upsert genérico da conta pendente local não reabre o tombstone e converge o Hive', () async {
    final box = await cenario();
    final r = await ContaReceberFirestoreService.upsertContaReceberDetalhado(box.values.single);
    expect(r.decision, ContaReceberUpsertDecision.skippedRemoteStronger);
    expectTombstone(await remota());
    expect(box.values, isEmpty);
  });

  test('republicação pós-venda não reabre o tombstone', () async {
    final box = await cenario();
    final vendas = Hive.box<Venda>(HiveBoxNames.vendas(lojaId));
    await ContaReceberVendaBackfillService.republicarContasVinculadasAVenda(
      lojaId: lojaId, venda: vendas.values.single);
    expectTombstone(await remota());
    expect(box.values, isEmpty);
  });

  test('pull aplica o tombstone na conta pendente local', () async {
    final box = await cenario();
    await ContaReceberFirestoreService.pullLojaFirestoreParaHive(lojaId, forcarMesmoSemTimestamp: true);
    expect(box.values, isEmpty);
    expectTombstone(await remota());
  });

  test('backfill da venda fiada antiga não recria a conta', () async {
    await cenario(contaLocal: false);
    final r = await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r.criadas, 0);
    expectTombstone(await remota());
    expect(await docsRemotos(), 1);
  });

  test('backfill não cria dívida nova quando a venda remota já não tem saldo (sem doc remoto da conta)', () async {
    await cenario(contaRemota: false, contaLocal: false);
    final r = await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r.criadas, 0);
    expect(await docsRemotos(), 0);
  });

  test('saldoAReceberVendaRemota: saldoFiado, total − pagamentos, ou indefinido', () {
    expect(saldoAReceberVendaRemota({'total': 312, 'pagamentoPix': 312}), 0);
    expect(saldoAReceberVendaRemota({'total': 100, 'pagamentoPix': 40}), 60);
    expect(saldoAReceberVendaRemota({'total': 100, 'saldoFiado': 70}), 70);
    expect(saldoAReceberVendaRemota({'total': 100}), 100);
    expect(saldoAReceberVendaRemota({'lojaId': 'x'}), isNull);
  });
}
