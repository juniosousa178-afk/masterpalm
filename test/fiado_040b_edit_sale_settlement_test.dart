// 040B — edição da venda quitada deve encerrar ContaReceber remoto e não ressuscitar.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_dedup.dart';
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

  const lojaId = 'loja-fiado-040b';
  const vendaId = 'venda-040b-quitacao-uuid';
  const docId = 'cr_venda-040b-quitacao-uuid_p1';

  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fiado_040b_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(LancamentoFinanceiroAdapter());
    }
  });

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugForcarFalhaMarcarPagaEdicaoVenda = null;
    ContaReceberLembreteCobranca.resetPullSessaoParaTeste();
  });

  tearDown(() async {
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugForcarFalhaMarcarPagaEdicaoVenda = null;
    ContaReceberLembreteCobranca.resetPullSessaoParaTeste();
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
    await fecharBox(HiveBoxNames.vendas(lojaId));
    await fecharBox(HiveBoxNames.lancamentosFinanceiros(lojaId));
    for (final name in [
      HiveBoxNames.contasReceber(lojaId),
      HiveBoxNames.vendas(lojaId),
      HiveBoxNames.lancamentosFinanceiros(lojaId),
    ]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
  });

  Future<DocumentReference<Map<String, dynamic>>> crRef() async {
    return firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.contasReceberCol)
        .doc(docId);
  }

  Future<void> seedRemoteAberto({double saldo = 100}) async {
    await (await crRef()).set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Cliente 040B',
      'valorOriginal': saldo,
      'valorPago': 0.0,
      'saldoAtual': saldo,
      'valor': saldo,
      'status': ContaReceberStatus.pendente,
      'pago': false,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
    });
  }

  Future<Venda> seedVendaFiada() async {
    final box = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    final venda = Venda(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      produtosDescricao: 'Item',
      quantidade: 1,
      preco: 100,
      total: 100,
      formasPagamento: 'Fiado - R\$ 100.00. Vencimento: 01/08/2026',
      data: DateTime(2026, 6, 1),
      vendedor: 'Teste',
      observacao: '',
      pagamentoDinheiro: 0,
      pagamentoPix: 0,
      pagamentoCartao: 0,
      idFirebase: vendaId,
    );
    await box.add(venda);
    return venda;
  }

  Future<ContaReceber> seedLocalAberto({required Venda venda}) async {
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    final conta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      valor: 100,
      valorOriginal: 100,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      vendaKey: venda.key is int ? venda.key as int : 0,
      idFirebase: docId,
      parcelaNumero: 1,
      parcelaTotal: 1,
    );
    await crBox.add(conta);
    return conta;
  }

  List<ContaReceber> contasAbertas(Box<ContaReceber> box) =>
      ContaReceberService.listar(
        contas: box.values,
        lojaId: lojaId,
        filtro: 'pendentes',
      );

  test('editar venda como paga encerra CR remoto e local sem caixa', () async {
    await seedRemoteAberto();
    final venda = await seedVendaFiada();
    await seedLocalAberto(venda: venda);
    final fin = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    final caixaAntes = fin?.length ?? 0;

    venda.pagamentoPix = 100;
    venda.formasPagamento = 'Pagamento Pix: R\$ 100.00';
    await venda.save();

    await VendasService.debugAtualizarContasReceberAposEdicaoVenda(
      venda: venda,
      lojaId: lojaId,
      isFiado: false,
      saldoFiado: 0,
      clienteNome: venda.clienteNome,
      totalAnterior: 100,
    );

    final snap = await (await crRef()).get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['pago'], isTrue);
    expect(snap.data()!['status'], ContaReceberStatus.paga);
    expect((snap.data()!['saldoAtual'] as num).toDouble(), closeTo(0, 0.01));
    expect(snap.data()!['cancelada'], isNot(isTrue));
    expect(snap.data()!['deletedAt'], isNull);

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(contasAbertas(crBox), isEmpty);
    expect(crBox.values.any((c) => c.pago && c.vendaIdFirebase == vendaId), isTrue);

    final finDepois = await FinanceiroHiveStore.openLancamentosBox(lojaId);
    expect(finDepois?.length ?? 0, caixaAntes);
  });

  test('pull após quitação pela edição não ressuscita título aberto', () async {
    await seedRemoteAberto();
    final venda = await seedVendaFiada();
    await seedLocalAberto(venda: venda);
    await ContaReceberService.encerrarAbertasPorEdicaoVendaQuitada(
      lojaId: lojaId,
      vendaKey: venda.key is int ? venda.key as int : null,
      vendaIdFirebase: vendaId,
    );

    await ContaReceberFirestoreService.pullContasReceberRemotas(lojaId);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(contasAbertas(crBox), isEmpty);
  });

  test('reload local + pull mantém quitado', () async {
    await seedRemoteAberto();
    final venda = await seedVendaFiada();
    await seedLocalAberto(venda: venda);
    await ContaReceberService.encerrarAbertasPorEdicaoVendaQuitada(
      lojaId: lojaId,
      vendaKey: venda.key is int ? venda.key as int : null,
      vendaIdFirebase: vendaId,
    );

    final crName = HiveBoxNames.contasReceber(lojaId);
    if (Hive.isBoxOpen(crName)) {
      await Hive.box<ContaReceber>(crName).close();
    }
    await Hive.deleteBoxFromDisk(crName);

    await ContaReceberFirestoreService.pullContasReceberRemotas(lojaId);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(contasAbertas(crBox), isEmpty);
    expect(
      crBox.values.any((c) => c.pago || c.valor < 0.01),
      isTrue,
    );
  });

  test('Home não alerta título pago', () {
    final paga = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      valor: 0,
      valorOriginal: 100,
      valorPago: 100,
      pago: true,
      status: ContaReceberStatus.paga,
      dataVencimento: DateTime(2026, 1, 1),
      dataVenda: DateTime(2026, 1, 1),
      vendaIdFirebase: vendaId,
    );
    final r = ContaReceberLembreteCobranca.avaliar(
      contas: [paga],
      lojaId: lojaId,
      agora: DateTime(2026, 9, 3),
    );
    expect(r.deveAlertar, isFalse);
  });

  test('Hive stale aberto + remoto pago: pull de sessão impede alerta falso', () async {
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    await crBox.add(
      ContaReceber(
        lojaId: lojaId,
        clienteNome: 'Cliente 040B',
        valor: 100,
        valorOriginal: 100,
        dataVencimento: DateTime(2026, 1, 1),
        dataVenda: DateTime(2026, 1, 1),
        vendaIdFirebase: vendaId,
        idFirebase: docId,
      ),
    );
    await (await crRef()).set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Cliente 040B',
      'valorOriginal': 100.0,
      'valorPago': 100.0,
      'saldoAtual': 0.0,
      'valor': 0.0,
      'status': ContaReceberStatus.paga,
      'pago': true,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 9, 3)),
    });

    final r = await ContaReceberLembreteCobranca.avaliarComValidacaoRemota(
      contas: crBox.values,
      lojaId: lojaId,
      agora: DateTime(2026, 9, 3),
    );
    expect(r.deveAlertar, isFalse);
  });

  test('pagamento parcial permanece aberto', () {
    final c = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      valor: 100,
      valorOriginal: 100,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
    );
    ContaReceberService.aplicarBaixaNaConta(
      conta: c,
      valorRecebido: 40,
      formaPagamento: 'Pix',
      dataRecebimento: DateTime(2026, 6, 10),
    );
    expect(c.pago, isFalse);
    expect(c.valor, closeTo(60, 0.01));
    final abertas = ContaReceberService.listar(
      contas: [c],
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(abertas, hasLength(1));
    final lembrete = ContaReceberLembreteCobranca.avaliar(
      contas: [c],
      lojaId: lojaId,
      agora: DateTime(2026, 9, 3),
    );
    expect(lembrete.deveAlertar, isTrue);
  });

  test('última baixa fecha recebível e some do alerta', () {
    final c = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      valor: 60,
      valorOriginal: 100,
      valorPago: 40,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
    );
    ContaReceberService.aplicarBaixaNaConta(
      conta: c,
      valorRecebido: 60,
      formaPagamento: 'Pix',
      dataRecebimento: DateTime(2026, 6, 20),
    );
    expect(c.pago, isTrue);
    expect(c.valor, closeTo(0, 0.01));
    expect(
      ContaReceberService.listar(
        contas: [c],
        lojaId: lojaId,
        filtro: 'pendentes',
      ),
      isEmpty,
    );
    expect(
      ContaReceberLembreteCobranca.avaliar(
        contas: [c],
        lojaId: lojaId,
        agora: DateTime(2026, 9, 3),
      ).deveAlertar,
      isFalse,
    );
  });

  test('dedup não recria a partir de título encerrado', () {
    final paga = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      valor: 0,
      valorOriginal: 100,
      valorPago: 100,
      pago: true,
      status: ContaReceberStatus.paga,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
      idFirebase: docId,
    );
    final candidataAberta = ContaReceber(
      lojaId: lojaId,
      clienteNome: 'Cliente 040B',
      valor: 100,
      valorOriginal: 100,
      dataVencimento: DateTime(2026, 8, 1),
      dataVenda: DateTime(2026, 6, 1),
      vendaIdFirebase: vendaId,
    );
    expect(contaReceberBloqueiaRecriacao(paga), isTrue);
    expect(
      hiveJaTemContaSemantica(
        contas: [paga],
        lojaId: lojaId,
        candidata: candidataAberta,
      ),
      isTrue,
    );
    final visivel = ContaReceberService.listar(
      contas: [paga, candidataAberta],
      lojaId: lojaId,
      filtro: 'pendentes',
    );
    expect(visivel, isEmpty);
  });

  test('backfill não recria quando remoto já está pago', () async {
    await (await crRef()).set({
      'lojaId': lojaId,
      'contaReceberId': docId,
      'vendaIdFirebase': vendaId,
      'clienteNome': 'Cliente 040B',
      'valorOriginal': 100.0,
      'valorPago': 100.0,
      'saldoAtual': 0.0,
      'valor': 0.0,
      'status': ContaReceberStatus.paga,
      'pago': true,
      'parcelaNumero': 1,
      'parcelaTotal': 1,
      'dataVencimento': Timestamp.fromDate(DateTime(2026, 8, 1)),
      'dataVenda': Timestamp.fromDate(DateTime(2026, 6, 1)),
    });
    final vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await vendasBox.add(
      Venda(
        lojaId: lojaId,
        clienteNome: 'Cliente 040B',
        produtosDescricao: 'Item',
        quantidade: 1,
        preco: 100,
        total: 100,
        formasPagamento: 'Fiado - R\$ 100.00. Vencimento: 01/08/2026',
        data: DateTime(2026, 6, 1),
        vendedor: 'Teste',
        observacao: '',
        idFirebase: vendaId,
      ),
    );
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueVendasCol)
        .doc(vendaId)
        .set({'lojaId': lojaId, 'idFirebase': vendaId});

    final r =
        await ContaReceberVendaBackfillService.backfillFromVendasFiadas(lojaId);
    expect(r.criadas, 0);
    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(contasAbertas(crBox), isEmpty);
  });

  test('falha remota não apaga Hive nem marca pago local', () async {
    await seedRemoteAberto();
    final venda = await seedVendaFiada();
    await seedLocalAberto(venda: venda);
    ContaReceberFirestoreService.debugForcarFalhaMarcarPagaEdicaoVenda =
        () async {
      throw StateError('simulacao falha remota 040b');
    };

    await expectLater(
      ContaReceberService.encerrarAbertasPorEdicaoVendaQuitada(
        lojaId: lojaId,
        vendaKey: venda.key is int ? venda.key as int : null,
        vendaIdFirebase: vendaId,
      ),
      throwsA(isA<StateError>()),
    );

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(contasAbertas(crBox), hasLength(1));
    expect(crBox.values.single.pago, isFalse);
    final snap = await (await crRef()).get();
    expect(snap.data()!['pago'], isNot(isTrue));
  });

  test('edição que continua fiado não cria duplicata', () async {
    await seedRemoteAberto();
    final venda = await seedVendaFiada();
    await seedLocalAberto(venda: venda);
    final crAntes = (await ContaReceberService.openBoxLoja(lojaId)).length;

    await VendasService.debugAtualizarContasReceberAposEdicaoVenda(
      venda: venda,
      lojaId: lojaId,
      isFiado: true,
      saldoFiado: 100,
      dataVencimentoFiado: DateTime(2026, 8, 1),
      clienteNome: venda.clienteNome,
      itensEquivalentes: true,
      totalAnterior: 100,
    );

    final crBox = await ContaReceberService.openBoxLoja(lojaId);
    expect(crBox.length, crAntes);
    expect(contasAbertas(crBox), hasLength(1));
  });
}
