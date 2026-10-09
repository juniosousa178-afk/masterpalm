import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../reports/consignment_report_data.dart';
import '../reports/widgets/consignment_combined_print_bar.dart';
import 'consignment_details_screen.dart';

class ConsignmentResellerHistoryScreen extends StatefulWidget {
  const ConsignmentResellerHistoryScreen({super.key, required this.lojaId});
  final String lojaId;

  @override
  State<ConsignmentResellerHistoryScreen> createState() => _ConsignmentResellerHistoryScreenState();
}

class _ConsignmentResellerHistoryScreenState extends State<ConsignmentResellerHistoryScreen> {
  late final Stream<List<ConsignmentDoc>> _stream = ConsignmentService.watchConsignments(widget.lojaId);
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
  Widget build(BuildContext context) {
    final lojaId = widget.lojaId;
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: Text(_selecting ? 'Selecionar consignações' : 'Histórico por revendedor'),
        actions: [
          ConsignmentSelectModeButton(
            selecting: _selecting,
            onPressed: _toggleSelecting,
          ),
        ],
      ),
      bottomNavigationBar: _selecting
          ? ConsignmentCombinedPrintBar(
              lojaId: lojaId,
              selected: _latest.where((c) => _selected.contains(c.id)).toList(),
            )
          : null,
      body: StreamBuilder<List<ConsignmentDoc>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          _syncLatest(snap.data!);
          final byReseller = <String, List<ConsignmentDoc>>{};
          for (final c in snap.data!) {
            byReseller.putIfAbsent(c.resellerId, () => []).add(c);
          }
          if (byReseller.isEmpty) {
            return const Center(child: Text('Nenhum revendedor com consignação.'));
          }
          final ids = byReseller.keys.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ids.length,
            itemBuilder: (context, i) {
              final list = byReseller[ids[i]]!;
              final name = list.first.resellerName;
              final open = list.where((c) => c.isIssued).toList();
              final closed = list.where((c) => c.isSettled).toList();
              final sent = list.fold<int>(0, (s, c) => s + c.totalItemsSent);
              final sold = list.fold<int>(0, (s, c) => s + c.totalItemsSold);
              final returned = list.fold<int>(0, (s, c) => s + c.totalItemsReturned);
              final commission = list.fold<double>(0, (s, c) => s + c.commissionAmount);
              return Card(
                child: ExpansionTile(
                  title: Text(name),
                  subtitle: Text(
                    'Aberto ${open.length} · Encerrado ${closed.length}\n'
                    'Enviado $sent · Vendido $sold · Devolvido $returned · '
                    'Comissão ${consignmentMoney.format(commission)}',
                  ),
                  children: [
                    for (final c in list)
                      ListTile(
                        leading: _selecting
                            ? ConsignmentSelectCheckbox(
                                doc: c,
                                selected: _selected.contains(c.id),
                                onChanged: (_) => _toggle(c),
                              )
                            : null,
                        title: ConsignmentStatusChip(c.status),
                        subtitle: Text('${c.totalItemsSent} pç'),
                        onTap: _selecting
                            ? () => _toggle(c)
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ConsignmentDetailsScreen(
                                      lojaId: lojaId,
                                      consignmentId: c.id,
                                    ),
                                  ),
                                ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
