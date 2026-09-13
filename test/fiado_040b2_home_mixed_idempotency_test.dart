// 040B2 — Home cross-device, mixed-version upsert, settlement idempotente.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_lembrete.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/conta_receber_venda_backfill.dart';
import 'package:master_palm/services/financeiro_hive_store.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/vendas_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-fiado-040b2';
  const lojaB = 'loja-fiado-040b2-b';
  const vendaId = 'venda-040b2-uuid';
  const docId = 'cr_venda-040b2-uuid_p1';

  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_040b2_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugForcarFalhaMarcarPagaEdicaoVenda = null;
    ContaReceberLembreteCobranca.debugForcarFalhaValidacaoRemota = null;
    ContaReceberLembreteCobranca.debugAtrasoValidacaoRemota = null;
    ContaReceberLembreteCobranca.invalidarSessao();
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugForcarFalhaMarcarPagaEdicaoVenda = null;
    ContaReceberLembreteCobranca.debugForcarFalhaValidacaoRemota = null;
    ContaReceberLembreteCobranca.debugAtrasoValidacaoRemota = null;
    ContaReceberLembreteCobranca.invalidarSessao();
    Future<void> fecharBox(String name) async {
      if (!Hive.isBoxOpen(name)) return;
      try {
        await Hive.box<ContaReceber>(name).close();
      } catch (_) {
        try {
          await Hive.box<Venda>(name).close();
        } catch (_) {
          try {
            await Hive.box<LancamentoFinanceiro>(name).close();
          } catch (_) {}
        }
      }
    }

    await fecharBox(HiveBoxNames.contasReceber(lojaId));
    await fecharBox(HiveBoxNames.contasReceber(lojaB));
    await fecharBox(HiveBoxNames.vendas(lojaId));
    await fecharBox(HiveBoxNames.lancamentosFinanceiros(lojaId));
    for (final name in [
      HiveBoxNames.contasReceber(lojaId),
      HiveBoxNames.contasReceber(lojaB),
      HiveBoxNames.vendas(lojaId),
      HiveBoxNames.lancamentosFinanceiros(lojaId),
    ]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  Future<DocumentReference<Map<String, dynamic>>> crRef([
    String loja = lojaId,
    String id = docId,
  ]) async {
    return firestore
        .collection('lojas')
        .doc(loja)
        .collection(FSPaths.contasReceberCol)
        .doc(id);
  }

  Map<String, dynamic> remotePago() => {
        'lojaId': lojaId,
        'contaReceberId': docId,
        'vendaIdFirebase': vendaId,
        'clienteNome': 'Cliente 040B2',
        'valorOriginal': 100.0,
        'valorPago': 100.0,
        'saldoAtual': 0.0,
        'valor': 0.0,
        'status': ContaReceberStatus.paga,
        'pago': true,
        'parcelaNumero': 1,
        'parcelaTotal': 1,
        'dataVencimento': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
      };

  Map<String, dynamic> remoteAberto() => {
        'lojaId': lojaId,
        'contaReceberId': docId,
        'vendaIdFirebase': vendaId,
        'clienteNome': 'Cliente 040B2',
        'valorOriginal': 100.0,
        'valorPago': 0.0,
        'saldoAtual': 100.0,
        'valor': 100.0,
        'status': ContaReceberStatus.pendente,
        'pago': false,
        'parcelaNumero': 1,
        'parcelaTotal': 1,
        'dataVencimento': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
      };

  Future<ContaReceber> seedHiveAberto({
    String loja = lojaId,
    bool pago = false,
    double valor = 100,
  }) async {
    final box = await ContaReceberService.openBoxLoja(loja);
    final c = ContaReceber(
      lojaId: loja,
      clienteNome: 'Cliente 040B2',
      valor: valor,
      valorOriginal: 100,
      valorPago: pago ? 100 : 0,
      pago: pago,
      status: pago ? ContaReceberStatus.paga : ContaReceberStatus.pendente,
      dataVencimento: DateTime(2026, 1, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      idFirebase: docId,
    );
    await box.add(c);
    return c;
  }

  Future<Venda> seedVenda() async {
    final box = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    final v = Venda(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B2',
      produtosDescricao: 'Item',
      quantidade: 1,
      preco: 100,
      total: 100,
      formasPagamento: 'Fiado - R\$ 100.00. Vencimento: 01/01/2026',
      data: DateTime(2026, 6, 1),
      vendedor: 'Teste',
      observacao: '',
      pagamentoDinheiro: 0,
      pagamentoPix: 0,
      pagamentoCartao: 0,
      idFirebase: vendaId,
    );
    await box.add(v);
    return v;
  }

  test('A Hive open + remote open overdue → alerta', () async {
    await (await crRef()).set(remoteAberto());
    await seedHiveAberto();
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final r = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(r.deveAlertar, isTrue);
  });

  test('B Hive open + remote paid → sem alerta', () async {
    await (await crRef()).set(remotePago());
    await seedHiveAberto();
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final r = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(r.deveAlertar, isFalse);
  });

  test('C Hive paid + remote paid → sem alerta', () async {
    await (await crRef()).set(remotePago());
    await seedHiveAberto(pago: true, valor: 0);
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final r = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(r.deveAlertar, isFalse);
  });

  test('D same-device settlement → Home sem alerta', () async {
    await (await crRef()).set(remoteAberto());
    final venda = await seedVenda();
    await seedHiveAberto();
    await VendasService.debugAtualizarContasReceberAposEdicaoVenda(
      venda: venda,
      lojaId: lojaId,
      isFiado: false,
      saldoFiado: 0,
      clienteNome: venda.clienteNome,
      totalAnterior: 100,
    );
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final r = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(r.deveAlertar, isFalse);
  });

  test('E cross-device same session: Hive stale open + remoto pago → sem alerta',
      () async {
    await (await crRef()).set(remotePago());
    await seedHiveAberto();
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final primeira = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(primeira.deveAlertar, isFalse);
    final segunda = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(segunda.deveAlertar, isFalse);
  });

  test('F logout/login invalida estado de sessão', () async {
    await (await crRef()).set(remoteAberto());
    await seedHiveAberto();
    ContaReceberLembreteCobranca.debugAtrasoValidacaoRemota =
        const Duration(milliseconds: 80);
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final emVoo = ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(ContaReceberLembreteCobranca.temAvaliacaoEmVoo(lojaId), isTrue);
    ContaReceberLembreteCobranca.invalidarSessao();
    expect(ContaReceberLembreteCobranca.temAvaliacaoEmVoo(lojaId), isFalse);
    expect(ContaReceberLembreteCobranca.temAvaliacaoEmVoo(lojaB), isFalse);
    await emVoo;
  });

  test('avaliações concorrentes da mesma loja compartilham o in-flight', () async {
    await (await crRef()).set(remoteAberto());
    await seedHiveAberto();
    ContaReceberLembreteCobranca.debugAtrasoValidacaoRemota =
        const Duration(milliseconds: 50);
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final a = ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    final b = ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(identical(a, b), isTrue);
    expect((await a).deveAlertar, isTrue);
    expect((await b).deveAlertar, isTrue);
  });

  test('G troca de loja isola freshness', () async {
    await (await crRef(lojaId)).set(remotePago());
    await (await crRef(lojaB, 'cr_venda-040b2-uuid_p1')).set({
      ...remoteAberto(),
      'lojaId': lojaB,
    });
    await seedHiveAberto();
    await seedHiveAberto(loja: lojaB);
    final a = await ContaReceberService.openBoxLoja(lojaId);
    final b = await ContaReceberService.openBoxLoja(lojaB);
    final ra = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: a.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    final rb = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: b.values,
      lojaId: lojaB,
      agora: DateTime(2026, 9, 5),
    );
    expect(ra.deveAlertar, isFalse);
    expect(rb.deveAlertar, isTrue);
  });

  test('H falha remota não alerta com Hive stale', () async {
    await seedHiveAberto();
    ContaReceberLembreteCobranca.debugForcarFalhaValidacaoRemota = () async {
      throw StateError('rede 040b2');
    };
    final box = await ContaReceberService.openBoxLoja(lojaId);
    final r = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: box.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 5),
    );
    expect(r.deveAlertar, isFalse);
  });

  test('upsert novo não reabre remoto pago', () async {
    await (await crRef()).set(remotePago());
    final local = await seedHiveAberto();
    final ok = await ContaReceberFirestoreService.upsertContaReceber(
      local,
      lastWriteOrigin: 'venda_fiada',
    );
    expect(ok, isTrue);
    final snap = await (await crRef()).get();
    expect(snap.data()!['pago'], isTrue);
    expect((snap.data()!['saldoAtual'] as num).toDouble(), closeTo(0, 0.01));
  });

  test('republicar com Hive stale não reabre título pago', () async {
    await (await crRef()).set(remotePago());
    final venda = await seedVenda();
    await seedHiveAberto();
    final n = await ContaReceberVendaBackfillService
        .republicarContasVinculadasAVenda(lojaId: lojaId, venda: venda);
    expect(n, greaterThanOrEqualTo(1));
    final snap = await (await crRef()).get();
    expect(snap.data()!['pago'], isTrue);
  });

  test('segunda edição paga é NOOP sem caixa nem erro', () async {
    await (await crRef()).set(remoteAberto());
    final venda = await seedVenda();
    await seedHiveAberto();
    final fin = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final caixaAntes = fin?.length ?? 0;

    Future<void> editarPaga() =>
        VendasService.debugAtualizarContasReceberAposEdicaoVenda(
          venda: venda,
          lojaId: lojaId,
          isFiado: false,
          saldoFiado: 0,
          clienteNome: venda.clienteNome,
          totalAnterior: 100,
        );

    await editarPaga();
    await editarPaga();

    final snap = await (await crRef()).get();
    expect(snap.data()!['pago'], isTrue);
    final box = await ContaReceberService.openBoxLoja(lojaId);
    expect(box.values.every((c) => c.pago), isTrue);
    final finDepois = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    expect(finDepois?.length ?? 0, caixaAntes);
  });

  test('Device A stale tenta settlement já pago remotamente → NOOP', () async {
    await (await crRef()).set(remotePago());
    final venda = await seedVenda();
    await seedHiveAberto();
    await ContaReceberService.encerrarAbertasPorEdicaoVendaQuitada(
      lojaId: lojaId,
      vendaKey: venda.key is int ? venda.key as int : null,
      vendaIdFirebase: vendaId,
    );
    final snap = await (await crRef()).get();
    expect(snap.data()!['pago'], isTrue);
    expect(snap.data()!['status'], ContaReceberStatus.paga);
  });

  test('settlement concorrente termina pago único sem caixa extra', () async {
    await (await crRef()).set(remoteAberto());
    final venda = await seedVenda();
    await seedHiveAberto();
    final fin = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final caixaAntes = fin?.length ?? 0;
    await Future.wait([
      ContaReceberService.encerrarAbertasPorEdicaoVendaQuitada(
        lojaId: lojaId,
        vendaIdFirebase: vendaId,
      ),
      ContaReceberService.encerrarAbertasPorEdicaoVendaQuitada(
        lojaId: lojaId,
        vendaKey: venda.key is int ? venda.key as int : null,
        vendaIdFirebase: vendaId,
      ),
    ]);
    final snap = await (await crRef()).get();
    expect(snap.data()!['pago'], isTrue);
    final finDepois = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    expect(finDepois?.length ?? 0, caixaAntes);
  });
}
