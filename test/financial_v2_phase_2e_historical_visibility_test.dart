import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/financeiro/v2/financial_historical_firestore_source.dart';
import 'package:master_palm/financeiro/v2/financial_historical_visibility.dart';
import 'package:master_palm/financeiro/v2/financial_month.dart';
import 'package:master_palm/financeiro/v2/financial_month_selector.dart';
import 'package:master_palm/models/fechamento_mensal.dart';
import 'package:master_palm/models/lancamento_financeiro.dart';

const _nathy = 'nathy-pratas-e-folheados';
const _mir = 'mirjoias';
final _now = DateTime(2026, 9, 28, 12);

void main() {
  test('intervalo histórico sai das fontes, sem ano inventado', () {
    final range = FinancialMonthRange.resolve(
      evidence: [
        FinancialMonth.fromInstant(DateTime(2026, 9, 13)),
        const FinancialMonth(2026, 1),
        FinancialMonth.fromInstant(DateTime(2026, 2, 1, 21)),
      ],
      now: _now,
    );
    expect(range.earliest, const FinancialMonth(2026, 1));
    expect(range.latest, const FinancialMonth(2026, 9));
    expect(range.months.map((m) => m.labelPt).toList(), [
      'Janeiro 2026',
      'Fevereiro 2026',
      'Março 2026',
      'Abril 2026',
      'Maio 2026',
      'Junho 2026',
      'Julho 2026',
      'Agosto 2026',
      'Setembro 2026',
    ]);
    expect(range.months.any((m) => m.year == 2025), isFalse);
    expect(range.months, orderedEquals([...range.months]..sort()));
  });

  test('atalhos de período e mês passado completo não somam fechamento cruzado', () {
    expect(
      periodIsCompletePastMonth(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 31, 23, 59, 59),
        now: _now,
      ),
      isTrue,
    );
    expect(
      periodIsCompletePastMonth(
        start: DateTime(2026, 2, 1),
        end: DateTime(2026, 3, 31, 23, 59, 59),
        now: _now,
      ),
      isFalse,
    );
    expect(
      periodIsCompletePastMonth(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30, 23, 59, 59),
        now: _now,
      ),
      isFalse,
    );
  });

  test('hive vazio mostra os lançamentos remotos da Nathy e agosto vazio', () {
    final remote = _nathyRemoteLaunches();
    final counts = <int, int>{};
    for (var month = 4; month <= 9; month++) {
      final merged = mergeLaunchesForDisplay(
        storeId: _nathy,
        month: FinancialMonth(2026, month),
        local: const [],
        remote: remote,
      );
      counts[month] = merged.visible.length;
      expect(merged.remainingDuplicateCount, 0);
      expect(merged.crossTenantDropped, 0);
    }
    expect(counts[4], 2);
    expect(counts[5], 2);
    expect(counts[6], 4);
    expect(counts[7], 1);
    expect(counts[8], 0);
    expect(counts[9], 3);
    expect(
      const FinancialMonth(2026, 8).emptyManualLaunchMessage,
      'Nenhum lançamento manual em agosto de 2026.',
    );
  });

  test('mesmo id local e remoto aparece uma vez e conflito não é sobrescrito', () {
    final remote = _launch(
      id: 'mesmo',
      month: 4,
      day: 5,
      valor: 49.9,
      tipo: 'gasto_fixo',
      status: 'pago',
    );
    final localIgual = _launch(
      id: 'mesmo',
      month: 4,
      day: 5,
      valor: 49.9,
      tipo: 'gasto_fixo',
      status: 'pago',
    );
    final igual = mergeLaunchesForDisplay(
      storeId: _nathy,
      month: const FinancialMonth(2026, 4),
      local: [localIgual],
      remote: [remote],
    );
    expect(igual.visible, hasLength(1));
    expect(igual.remainingDuplicateCount, 0);
    expect(igual.conflictIds, isEmpty);
    expect(igual.silentOverwrite, isFalse);

    final localDiferente = _launch(
      id: 'mesmo',
      month: 4,
      day: 5,
      valor: 10,
      tipo: 'gasto_fixo',
      status: 'pago',
    );
    final conflito = mergeLaunchesForDisplay(
      storeId: _nathy,
      month: const FinancialMonth(2026, 4),
      local: [localDiferente],
      remote: [remote],
    );
    expect(conflito.visible, hasLength(1));
    expect(conflito.visible.single.valor, 10);
    expect(conflito.conflictIds, ['mesmo']);
    expect(conflito.silentOverwrite, isFalse);
    expect(conflito.remainingDuplicateCount, 0);
  });

  test('lançamento só local permanece visível e outro tenant é descartado', () {
    final local = _launch(
      id: 'so-local',
      month: 8,
      day: 2,
      valor: 15,
      tipo: 'despesa_operacional',
      status: 'pago',
    );
    final mir = _launch(
      id: 'mir',
      month: 8,
      day: 2,
      valor: 99,
      tipo: 'despesa_operacional',
      status: 'pago',
      storeId: _mir,
    );
    final merged = mergeLaunchesForDisplay(
      storeId: _nathy,
      month: const FinancialMonth(2026, 8),
      local: [local],
      remote: [mir],
    );
    expect(merged.visible.map((e) => e.id), ['so-local']);
    expect(merged.localOnlyCount, 1);
    expect(merged.crossTenantDropped, 1);
  });

  test('leitura remota preserva status estornado', () {
    final parsed = lancamentoFromRemoteRead(
      docId: 'antigo',
      storeId: _nathy,
      data: {
        'lojaId': _nathy,
        'valor': 18.95,
        'tipo': 'entrada_extra',
        'categoria': 'recebimentos_fiado',
        'status': 'estornado',
        'dataLancamento': DateTime.utc(2026, 6, 18, 3),
        'dataPagamento': DateTime.utc(2026, 6, 18, 3),
        'competenciaMes': 6,
        'competenciaAno': 2026,
      },
    );
    expect(parsed, isNotNull);
    expect(parsed!.status, 'estornado');
    expect(parsed.categoria, 'recebimentos_fiado');
  });

  test('janeiro usa o fechamento e setembro ao vivo não usa o snapshot', () {
    final janeiro = resolveMonthReport(
      month: const FinancialMonth(2026, 1),
      now: _now,
      storeId: _nathy,
      remoteFailed: false,
      closure: _closure(2026, 1, 221.98),
      rawVendaTotal: 0,
    );
    expect(janeiro.available, isTrue);
    expect(janeiro.vendaTotal, 221.98);
    expect(janeiro.source, FinancialHistoricalSource.monthlyClosure);
    expect(janeiro.doubleCounted, isFalse);

    final setembro = resolveMonthReport(
      month: const FinancialMonth(2026, 9),
      now: _now,
      storeId: _nathy,
      remoteFailed: false,
      closure: _closure(2026, 9, 4725.82),
      rawVendaTotal: 100,
    );
    expect(setembro.currentMonthUsesLive, isTrue);
    expect(setembro.vendaTotal, 100);
    expect(setembro.source, FinancialHistoricalSource.liveRemote);
    expect(setembro.doubleCounted, isFalse);
  });

  test('fevereiro a agosto ficam disponíveis e 2025 não é fabricado', () {
    for (final month in [2, 3, 4, 5, 6, 7, 8]) {
      final report = resolveMonthReport(
        month: FinancialMonth(2026, month),
        now: _now,
        storeId: _nathy,
        remoteFailed: false,
        closure: _closure(2026, month, 10),
        rawVendaTotal: 0,
      );
      expect(report.available, isTrue, reason: 'mês $month');
      expect(report.vendaTotal, 10);
      expect(report.doubleCounted, isFalse);
    }
    final ano2025 = resolveMonthReport(
      month: const FinancialMonth(2025, 12),
      now: _now,
      storeId: _nathy,
      remoteFailed: false,
      closure: null,
      rawVendaTotal: 0,
    );
    expect(ano2025.available, isTrue);
    expect(ano2025.knownZero, isTrue);
    expect(ano2025.vendaTotal, 0);
  });

  test('falha remota não vira zero conhecido', () {
    final failed = resolveMonthReport(
      month: const FinancialMonth(2026, 8),
      now: _now,
      storeId: _nathy,
      remoteFailed: true,
      closure: _closure(2026, 8, 5029.96),
      rawVendaTotal: 0,
    );
    expect(failed.available, isFalse);
    expect(failed.vendaTotal, isNull);
    expect(failed.source, FinancialHistoricalSource.unavailable);
    expect(failed.knownZero, isFalse);
  });

  test('ano 2026 inclui janeiro e não soma o fechamento de setembro', () {
    final closures = [
      for (var month = 1; month <= 8; month++)
        _closure(2026, month, month == 1 ? 221.98 : 10),
      _closure(2026, 9, 999),
    ];
    final year = resolveYearVisibility(
      year: 2026,
      now: _now,
      earliest: const FinancialMonth(2026, 1),
      closures: closures,
      storeId: _nathy,
      currentMonthLive: const FinancialClosureTotals(
        vendaTotal: 50,
        taxasTotal: 1,
        custoTotal: 2,
        lucroTotal: 3,
        totalDinheiro: 4,
        totalPix: 5,
        totalCartao: 6,
      ),
      remoteFailed: false,
    );
    expect(year.available, isTrue);
    expect(year.historyVisible, isTrue);
    expect(year.currentMonthUsesLiveData, isTrue);
    expect(year.doubleCounted, isFalse);
    expect(year.needsSingleRawFallback, isFalse);
    expect(year.vendaTotal, closeTo(221.98 + 70 + 50, 0.001));
    expect(year.vendaTotal, isNot(closeTo(221.98 + 70 + 999, 0.001)));
  });

  test('fechamento de outra loja não entra no relatório da Nathy', () {
    final report = resolveMonthReport(
      month: const FinancialMonth(2026, 1),
      now: _now,
      storeId: _nathy,
      remoteFailed: false,
      closure: _closure(2026, 1, 221.98, storeId: _mir),
      rawVendaTotal: 0,
    );
    expect(report.source, FinancialHistoricalSource.remoteRaw);
    expect(report.vendaTotal, 0);
  });

  test('plano de leitura é limitado e não grava Hive', () {
    expect(FinancialHistoricalQueryPlan.historicalMonthMetadataQueryCount, 6);
    expect(FinancialHistoricalQueryPlan.selectedMonthRemoteQueryCount, 2);
    expect(FinancialHistoricalQueryPlan.selectedMonthClosureReadCount, 1);
    expect(FinancialHistoricalQueryPlan.nPlusOneDetected, isFalse);
    expect(FinancialHistoricalQueryPlan.remoteLaunchToHiveAutoWrite, isFalse);
    expect(FinancialHistoricalQueryPlan.remoteClosureToHiveAutoWrite, isFalse);
    expect(FinancialHistoricalQueryPlan.localHiveWritesFromRead, 0);
    expect(FirestoreFinancialHistoricalSource.hiveWritesFromRead, 0);
  });

  testWidgets('seletor abre janeiro de 2026', (tester) async {
    final range = FinancialMonthRange.resolve(
      evidence: const [FinancialMonth(2026, 1), FinancialMonth(2026, 9)],
      now: _now,
    );
    FinancialMonth? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinancialMonthSelector(
            selected: const FinancialMonth(2026, 9),
            range: range,
            onChanged: (month) => chosen = month,
          ),
        ),
      ),
    );
    expect(find.text('Setembro 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('financial-month-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Janeiro 2026'));
    await tester.pumpAndSettle();
    expect(chosen, const FinancialMonth(2026, 1));
  });
}

LancamentoFinanceiro _launch({
  required String id,
  required int month,
  required int day,
  required double valor,
  required String tipo,
  required String status,
  String storeId = _nathy,
}) {
  final data = DateTime(2026, month, day, 12);
  return LancamentoFinanceiro(
    id: id,
    lojaId: storeId,
    descricao: id,
    valor: valor,
    tipo: tipo,
    categoria: 'internet',
    status: status,
    dataLancamento: data,
    dataPagamento: status == 'pendente' ? null : data,
    competenciaMes: month,
    competenciaAno: 2026,
  );
}

List<LancamentoFinanceiro> _nathyRemoteLaunches() {
  return [
    _launch(id: 'abr-1', month: 4, day: 5, valor: 49.9, tipo: 'gasto_fixo', status: 'pago'),
    _launch(id: 'abr-2', month: 4, day: 10, valor: 79.9, tipo: 'gasto_fixo', status: 'pago'),
    _launch(id: 'mai-1', month: 5, day: 5, valor: 49.9, tipo: 'gasto_fixo', status: 'pendente'),
    _launch(id: 'mai-2', month: 5, day: 10, valor: 79.9, tipo: 'gasto_fixo', status: 'pendente'),
    _launch(id: 'jun-1', month: 6, day: 5, valor: 49.9, tipo: 'gasto_fixo', status: 'pendente'),
    _launch(id: 'jun-2', month: 6, day: 10, valor: 79.9, tipo: 'gasto_fixo', status: 'pendente'),
    _launch(id: 'jun-3', month: 6, day: 17, valor: 18.95, tipo: 'entrada_extra', status: 'estornado'),
    _launch(id: 'jun-4', month: 6, day: 2, valor: 8, tipo: 'entrada_extra', status: 'excluido'),
    _launch(id: 'jul-1', month: 7, day: 27, valor: 74.96, tipo: 'entrada_extra', status: 'pago'),
    _launch(id: 'set-1', month: 9, day: 13, valor: 164.7, tipo: 'entrada_extra', status: 'pago'),
    _launch(id: 'set-2', month: 9, day: 13, valor: 176.8, tipo: 'entrada_extra', status: 'pago'),
    _launch(id: 'set-3', month: 9, day: 13, valor: 105.8, tipo: 'entrada_extra', status: 'pago'),
  ];
}

FechamentoMensal _closure(
  int year,
  int month,
  double venda, {
  String storeId = _nathy,
}) {
  return FechamentoMensal(
    ano: year,
    mes: month,
    totalDinheiro: 0,
    totalPix: venda,
    totalCartao: 0,
    vendaTotal: venda,
    custoTotal: 0,
    taxasTotal: 0,
    lucroTotal: 0,
    fechadoEm: DateTime(year, month, 28),
    lojaId: storeId,
  );
}
