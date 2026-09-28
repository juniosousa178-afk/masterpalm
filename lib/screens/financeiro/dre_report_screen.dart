// Tela somente leitura da DRE. Não grava e não edita lançamentos.

import 'package:flutter/material.dart';

import '../../financeiro/v2/financial_dashboard_pilot.dart';
import '../../financeiro/v2/financial_dre.dart';
import '../../financeiro/v2/financial_dre_pdf.dart';
import '../../financeiro/v2/financial_historical_firestore_source.dart';
import '../../financeiro/v2/financial_month.dart';
import '../../financeiro/v2/financial_month_selector.dart';
import '../../models/fechamento_mensal.dart';
import '../../services/loja_id_service.dart';

class DreReportScreen extends StatefulWidget {
  const DreReportScreen({
    super.key,
    this.storeId,
    this.storeName = '',
    this.previewStatement,
    this.now,
    this.debugPilot,
  });

  final String? storeId;
  final String storeName;
  final DreStatement? previewStatement;
  final DateTime? now;
  final FinancialDashboardPilot? debugPilot;

  @override
  State<DreReportScreen> createState() => _DreReportScreenState();
}

class _DreReportScreenState extends State<DreReportScreen> {
  DrePeriodMode _mode = DrePeriodMode.month;
  late FinancialMonth _month;
  late FinancialMonth _latestMonth;
  late int _year;
  DateTime? _customStart;
  DateTime? _customEnd;
  DreStatement? _statement;
  String? _error;
  bool _loading = false;
  String _storeId = '';
  String _storeName = '';

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _month = FinancialMonth.fromClock(now);
    _latestMonth = _month;
    _year = now.year;
    _statement = widget.previewStatement;
    _storeId = (widget.storeId ?? widget.previewStatement?.storeId ?? '').trim();
    _storeName = widget.storeName.trim().isEmpty
        ? (widget.previewStatement?.storeName ?? '')
        : widget.storeName.trim();
    if (_statement == null) {
      _load();
    }
  }

  DrePeriod _period(DateTime now) {
    switch (_mode) {
      case DrePeriodMode.month:
        return DrePeriod.month(_month);
      case DrePeriodMode.year:
        return DrePeriod.year(_year, now: now);
      case DrePeriodMode.custom:
        final start = _customStart ?? DateTime(now.year, now.month, 1);
        final end = _customEnd ?? now;
        return DrePeriod.custom(start: start, end: end);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var store = _storeId;
      if (store.isEmpty) {
        store = (await LojaIdService.getWithTimeoutThenSessionFallback(
          timeout: const Duration(seconds: 8),
        ))
                ?.trim() ??
            '';
      }
      if (!mounted) return;
      final pilot = widget.debugPilot ??
          await FirestoreFinancialDashboardPilotSource().read(store);
      if (!mounted) return;
      if (!FinancialDrePolicy.showEntry(tenantDreEnabled: pilot.showDre)) {
        setState(() {
          _storeId = store;
          _loading = false;
          _statement = null;
          _error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/relatorios_financeiros');
        });
        return;
      }
      final now = widget.now ?? DateTime.now();
      final period = _period(now);
      final source = FinancialHistoricalSources.current;
      final sales = await source.loadSales(
        storeId: store,
        startUtcInclusive: period.months.first.startUtcInclusive,
        endExclusiveUtc: period.months.last.endExclusiveUtc,
      );
      final launches = await source.loadLaunchesInUtcRange(
        storeId: store,
        startUtcInclusive: period.months.first.startUtcInclusive,
        endExclusiveUtc: period.months.last.endExclusiveUtc,
      );
      final historical = <DreHistoricalComponent>[];
      for (final month in period.months) {
        final hasSale = sales.any((sale) => month.containsInstant(sale.data));
        if (hasSale) continue;
        if (!periodIsCompletePastMonth(
          start: month.start,
          end: DateTime(month.year, month.month + 1, 0),
          now: now,
        )) {
          continue;
        }
        final closure = await source.loadClosure(storeId: store, month: month);
        if (closure == null) continue;
        historical.add(_componentFromClosure(closure));
      }
      final statement = FinancialDreRead.calculate(
        DreReadInput(
          storeId: store,
          storeName: _storeName.isEmpty ? store : _storeName,
          period: period,
          now: now,
          generatedAt: DateTime.now(),
          sales: sales,
          entries: launches,
          historicalComponents: historical,
          salesLoaded: true,
          expensesLoaded: true,
        ),
      );
      if (!mounted) return;
      setState(() {
        _storeId = store;
        _statement = statement;
        _loading = false;
      });
    } on FinancialHistoricalUnavailable {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statement = null;
        _error = 'Histórico remoto indisponível.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statement = null;
        _error = 'Não foi possível montar a DRE.';
      });
    }
  }

  DreHistoricalComponent _componentFromClosure(FechamentoMensal closure) {
    return DreHistoricalComponent(
      year: closure.ano,
      month: closure.mes,
      grossRevenue: closure.vendaTotal,
      cogs: null,
    );
  }

  Future<void> _pickCustom(bool start) async {
    final now = widget.now ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? (_customStart ?? now) : (_customEnd ?? now),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _customStart = picked;
      } else {
        _customEnd = picked;
      }
    });
    if (_customStart != null && _customEnd != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DRE'),
        actions: [
          if (statement != null) ...[
            IconButton(
              key: const Key('dre-print'),
              tooltip: 'Imprimir',
              onPressed: () => printDreStatement(statement),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              key: const Key('dre-pdf'),
              tooltip: 'Gerar PDF',
              onPressed: () => shareDrePdf(statement),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<DrePeriodMode>(
            segments: const [
              ButtonSegment(value: DrePeriodMode.month, label: Text('Mês')),
              ButtonSegment(value: DrePeriodMode.year, label: Text('Ano')),
              ButtonSegment(
                value: DrePeriodMode.custom,
                label: Text('Período personalizado'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) {
              setState(() => _mode = value.first);
              if (widget.previewStatement == null) _load();
            },
          ),
          const SizedBox(height: 12),
          if (_mode == DrePeriodMode.month)
            FinancialMonthSelector(
              selected: _month,
              range: FinancialMonthRange(
                const FinancialMonth(2026, 1),
                _latestMonth,
              ),
              onChanged: (month) {
                setState(() => _month = month);
                if (widget.previewStatement == null) _load();
              },
            ),
          if (_mode == DrePeriodMode.year)
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() => _year -= 1);
                    if (widget.previewStatement == null) _load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_year'),
                IconButton(
                  onPressed: _year >= (widget.now ?? DateTime.now()).year
                      ? null
                      : () {
                          setState(() => _year += 1);
                          if (widget.previewStatement == null) _load();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          if (_mode == DrePeriodMode.custom)
            Row(
              children: [
                TextButton(
                  onPressed: () => _pickCustom(true),
                  child: Text(
                    _customStart == null
                        ? 'Início'
                        : formatDreDate(_customStart!),
                  ),
                ),
                TextButton(
                  onPressed: () => _pickCustom(false),
                  child: Text(
                    _customEnd == null ? 'Fim' : formatDreDate(_customEnd!),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('dre-error')),
          if (statement != null) DreStatementView(statement: statement),
        ],
      ),
    );
  }
}

class DreStatementView extends StatelessWidget {
  const DreStatementView({super.key, required this.statement});

  final DreStatement statement;

  @override
  Widget build(BuildContext context) {
    final rows = DrePresentation.rows(statement);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          statement.storeName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text('DRE — Demonstrativo de Resultado'),
        Text('Período: ${statement.period.label}'),
        Text('Gerado em ${formatDreDateTime(statement.generatedAt)}'),
        const SizedBox(height: 12),
        for (final row in rows)
          InkWell(
            onTap: () => _openDrilldown(context, row.label),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontWeight:
                            row.emphasis ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(row.amount),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Qualidade da DRE',
          key: Key('dre-quality-panel'),
        ),
        for (final note in statement.qualityNotes) Text('• $note'),
        const SizedBox(height: 8),
        const Text('Lucro líquido não é apresentado nesta fase.'),
      ],
    );
  }

  void _openDrilldown(BuildContext context, String label) {
    final items = _itemsFor(label);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 420,
          child: items.isEmpty
              ? const Text('Sem documentos nesta linha.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      ListTile(
                        title: Text(item.description),
                        subtitle: Text(formatDreDate(item.date)),
                        trailing: Text(formatDreMoney(item.amount)),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  List<DreDrillItem> _itemsFor(String label) {
    if (label.startsWith('RECEITA BRUTA')) return statement.sales;
    for (final line in statement.operatingExpenseLines) {
      if (line.label == label) return line.items;
    }
    if (label == 'Pró-labore') return statement.proLabore?.items ?? const [];
    if (label == 'Retiradas') {
      return statement.ownerWithdrawals?.items ?? const [];
    }
    if (label == 'Investimentos') return statement.investments?.items ?? const [];
    return const [];
  }
}
