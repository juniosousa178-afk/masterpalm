import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../design_system/mp_tokens.dart';
import '../../../services/loja_id_service.dart';
import '../../../widgets/app_help_icon_button.dart';
import '../consignment_errors.dart';
import '../consignment_feature_flag.dart';
import '../consignment_hide_action.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import 'consignment_form_screen.dart';
import 'consignment_details_screen.dart';
import 'consignment_reseller_history_screen.dart';
import '../reports/consignment_report_data.dart';
import '../reports/screens/consignment_reports_hub_screen.dart';
import '../reports/widgets/consignment_combined_print_bar.dart';

class ConsignmentListScreen extends StatefulWidget {
  const ConsignmentListScreen({super.key});

  @visibleForTesting
  static Future<String?> Function()? debugLojaId;

  @override
  State<ConsignmentListScreen> createState() => _ConsignmentListScreenState();
}

class _ConsignmentListScreenState extends State<ConsignmentListScreen> {
  String? _lojaId;
  bool _loading = true;
  bool _enabled = false;
  String? _error;
  Stream<List<ConsignmentDoc>>? _stream;
  bool _selecting = false;
  final Set<String> _selected = {};
  List<ConsignmentDoc> _latest = const [];

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selected.clear();
    });
  }

  void _toggle(ConsignmentDoc c) {
    if (!ConsignmentCombinedReportPlanner.canSelect(c)) return;
    setState(() {
      if (!_selected.remove(c.id)) _selected.add(c.id);
    });
  }

  void _syncLatest(List<ConsignmentDoc> items) {
    if (identical(items, _latest)) return;
    _latest = items;
    if (!_selecting || _selected.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selected.removeWhere(
            (id) => !items.any((c) => c.id == id && ConsignmentCombinedReportPlanner.canSelect(c)),
          ));
    });
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final lojaId = await (ConsignmentListScreen.debugLojaId ?? LojaIdService.get)();
      final enabled =
          lojaId != null && lojaId.trim().isNotEmpty && await ConsignmentFeatureFlag.isEnabled(lojaId);
      if (!mounted) return;
      setState(() {
        _lojaId = lojaId;
        _enabled = enabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openDetails(ConsignmentDoc c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsignmentDetailsScreen(lojaId: _lojaId!, consignmentId: c.id),
      ),
    );
  }

  Widget _list(List<ConsignmentDoc> items, {required bool history}) {
    if (items.isEmpty) {
      return Center(
        child: Text(history ? 'Nenhuma consignação no histórico.' : 'Nenhuma consignação em aberto.'),
      );
    }
    return ListView.separated(
      key: PageStorageKey(history ? 'consignment_history_list' : 'consignment_open_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = items[i];
        return Card(
          key: Key('consignment_tile_${c.id}'),
          child: ListTile(
            leading: _selecting
                ? ConsignmentSelectCheckbox(
                    doc: c,
                    selected: _selected.contains(c.id),
                    onChanged: (_) => _toggle(c),
                  )
                : null,
            title: Text(c.resellerName),
            subtitle: Text(history ? _historySubtitle(c) : _openSubtitle(c)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConsignmentStatusChip(c.status),
                if (history && !_selecting && c.canHideFromList)
                  PopupMenuButton<String>(
                    key: Key('consignment_menu_${c.id}'),
                    tooltip: 'Mais opções',
                    onSelected: (_) => confirmAndHideTotalReturn(context, lojaId: _lojaId!, doc: c),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(consignmentHideTotalReturnLabel),
                      ),
                    ],
                  ),
              ],
            ),
            onTap: _selecting ? () => _toggle(c) : () => _openDetails(c),
          ),
        );
      },
    );
  }

  static final _dateFmt = DateFormat('dd/MM/yyyy');

  String _openSubtitle(ConsignmentDoc c) => c.isIssued && c.hasWithdrawals
      ? '${c.totalItemsOutstanding} pç com a revendedora · '
          '${consignmentMoney.format(c.outstandingGrossAmount)}'
      : '${c.totalItemsSent} pç · ${consignmentMoney.format(c.potentialGrossAmount)}';

  String _historySubtitle(ConsignmentDoc c) {
    final amount = c.isSettled
        ? 'Vendido ${consignmentMoney.format(c.grossSoldAmount)}'
        : consignmentMoney.format(c.potentialGrossAmount);
    final when = c.closedAt;
    return '${c.totalItemsSent} pç · $amount${when == null ? '' : ' · ${_dateFmt.format(when.toLocal())}'}';
  }

  @override
  Widget build(BuildContext context) =>
      DefaultTabController(length: 2, child: _buildScaffold(context));

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: Text(_selecting ? 'Selecionar consignações' : 'Consignados'),
        bottom: _enabled && _lojaId != null
            ? const TabBar(
                tabs: [
                  Tab(key: Key('consignment_tab_open'), text: 'Em aberto'),
                  Tab(key: Key('consignment_tab_history'), text: 'Histórico'),
                ],
              )
            : null,
        actions: [
          if (_enabled && _lojaId != null)
            ConsignmentSelectModeButton(
              selecting: _selecting,
              onPressed: _toggleSelecting,
            ),
          if (_enabled && _lojaId != null && !_selecting)
            IconButton(
              tooltip: 'Relatórios',
              icon: const Icon(Icons.summarize_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConsignmentReportsHubScreen(lojaId: _lojaId!),
                ),
              ),
            ),
          if (_enabled && _lojaId != null && !_selecting)
            IconButton(
              tooltip: 'Histórico por revendedor',
              icon: const Icon(Icons.people_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConsignmentResellerHistoryScreen(lojaId: _lojaId!),
                ),
              ),
            ),
          const AppHelpIconButton(),
        ],
      ),
      bottomNavigationBar: _selecting && _lojaId != null
          ? ConsignmentCombinedPrintBar(
              lojaId: _lojaId!,
              selected: _latest.where((c) => _selected.contains(c.id)).toList(),
            )
          : null,
      floatingActionButton: _enabled && _lojaId != null && !_selecting
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConsignmentFormScreen(lojaId: _lojaId!),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nova consignação'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_enabled
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'O módulo de consignados não está habilitado nesta loja.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _error != null
                  ? Center(child: Text(_error!))
                  : StreamBuilder<List<ConsignmentDoc>>(
                      stream: _stream ??= ConsignmentService.watchConsignments(_lojaId!),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Text(ConsignmentException.userMessage(
                                'SERVER', snap.error.toString())),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data!;
                        _syncLatest(items);
                        final split = splitConsignmentLists(items);
                        return TabBarView(
                          children: [
                            _list(split.open, history: false),
                            _list(split.history, history: true),
                          ],
                        );
                      },
                    ),
    );
  }
}
