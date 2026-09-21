import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../design_system/mp_tokens.dart';
import '../../consignment_models.dart';
import '../../consignment_service.dart';
import '../../consignment_ui.dart';
import '../consignment_report_actions.dart';
import '../consignment_report_data.dart';
import 'consignment_report_preview_screen.dart';

class ConsignmentReportsHubScreen extends StatelessWidget {
  const ConsignmentReportsHubScreen({super.key, required this.lojaId});
  final String lojaId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Relatórios de Consignados')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            context,
            title: 'Pedidos por revendedor',
            subtitle: 'Peças entregues, fotos, valores e assinaturas.',
            icon: Icons.receipt_long_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsignmentReportWizardScreen(
                  lojaId: lojaId,
                  kind: ConsignmentReportKind.order,
                ),
              ),
            ),
          ),
          _card(
            context,
            title: 'Acertos por revendedor',
            subtitle: 'Vendas, devoluções, comissão e valores líquidos.',
            icon: Icons.fact_check_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsignmentReportWizardScreen(
                  lojaId: lojaId,
                  kind: ConsignmentReportKind.settlement,
                ),
              ),
            ),
          ),
          _card(
            context,
            title: 'Relatório geral',
            subtitle: 'Visão gerencial consolidada por revendedor.',
            icon: Icons.analytics_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsignmentReportWizardScreen(
                  lojaId: lojaId,
                  kind: ConsignmentReportKind.general,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: MpColors.primary),
        title: Text(title, style: MpType.section),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class ConsignmentReportWizardScreen extends StatefulWidget {
  const ConsignmentReportWizardScreen({
    super.key,
    required this.lojaId,
    required this.kind,
    this.preselectedConsignmentId,
  });

  final String lojaId;
  final ConsignmentReportKind kind;
  final String? preselectedConsignmentId;

  @override
  State<ConsignmentReportWizardScreen> createState() => _ConsignmentReportWizardScreenState();
}

class _ConsignmentReportWizardScreenState extends State<ConsignmentReportWizardScreen> {
  ConsignmentReportPeriodPreset _preset = ConsignmentReportPeriodPreset.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _resellerId;
  String? _status;
  String? _consignmentId;
  List<ConsignmentReseller> _resellers = [];
  List<ConsignmentDoc> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _consignmentId = widget.preselectedConsignmentId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final range = ConsignmentReportDateRange.fromPreset(
      _preset,
      customStart: _customStart,
      customEnd: _customEnd,
    );
    final resellers = await ConsignmentService.watchResellers(widget.lojaId).first;
    final docs = await ConsignmentReportDataService.loadFilteredConsignments(
      lojaId: widget.lojaId,
      resellerId: _resellerId,
      status: widget.kind == ConsignmentReportKind.settlement ? (_status ?? 'SETTLED') : _status,
      range: widget.kind == ConsignmentReportKind.general || _consignmentId == null ? range : null,
    );
    if (!mounted) return;
    setState(() {
      _resellers = resellers;
      _docs = docs;
      _loading = false;
      if (_consignmentId != null && docs.every((d) => d.id != _consignmentId)) {
        // keep preselected even if outside period
      }
    });
  }

  String get _title {
    switch (widget.kind) {
      case ConsignmentReportKind.order:
        return 'Relatório de pedido';
      case ConsignmentReportKind.settlement:
        return 'Relatório de acerto';
      case ConsignmentReportKind.general:
        return 'Relatório geral';
      case ConsignmentReportKind.addition:
        return 'Comprovante de acréscimo';
    }
  }

  List<ConsignmentDoc> get _selectableDocs {
    var list = _docs;
    if (widget.kind == ConsignmentReportKind.order) {
      list = list.where((d) => !d.isCancelled).toList();
    } else if (widget.kind == ConsignmentReportKind.settlement) {
      list = list.where((d) => d.isSettled).toList();
    }
    if (_resellerId != null && _resellerId!.isNotEmpty) {
      list = list.where((d) => d.resellerId == _resellerId).toList();
    }
    return list;
  }

  Future<void> _openPreview() async {
    if (widget.kind == ConsignmentReportKind.general) {
      final range = ConsignmentReportDateRange.fromPreset(
        _preset,
        customStart: _customStart,
        customEnd: _customEnd,
      );
      final statusLabel = _status == null || _status!.isEmpty
          ? 'Todos'
          : consignmentStatusLabel(_status!);
      final bytes = ConsignmentReportActions.buildGeneralBytes(
        lojaId: widget.lojaId,
        range: range,
        resellerId: _resellerId,
        status: _status,
        statusFilterLabel: statusLabel,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsignmentReportPreviewScreen(
            title: 'Relatório geral',
            fileName: ConsignmentReportDataService.generalFileName(),
            bytesFuture: bytes,
          ),
        ),
      );
      return;
    }

    final id = _consignmentId;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma consignação.')),
      );
      return;
    }
    final doc = await ConsignmentService.getConsignment(widget.lojaId, id);
    if (!mounted) return;
    if (doc == null || (doc.storeId.isNotEmpty && doc.storeId != widget.lojaId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consignação não encontrada nesta loja.')),
      );
      return;
    }
    if (widget.kind == ConsignmentReportKind.settlement && !doc.isSettled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acerto disponível apenas para consignações acertadas.')),
      );
      return;
    }
    ConsignmentReseller? reseller;
    try {
      reseller = _resellers.where((r) => r.resellerId == doc.resellerId).firstOrNull;
    } catch (_) {}
    final fileName = widget.kind == ConsignmentReportKind.order
        ? ConsignmentReportDataService.orderFileName(doc)
        : ConsignmentReportDataService.settlementFileName(doc);
    final bytes = widget.kind == ConsignmentReportKind.order
        ? ConsignmentReportActions.buildOrderBytes(
            lojaId: widget.lojaId,
            doc: doc,
            reseller: reseller,
          )
        : ConsignmentReportActions.buildSettlementBytes(
            lojaId: widget.lojaId,
            doc: doc,
            reseller: reseller,
          );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsignmentReportPreviewScreen(
          title: _title,
          fileName: fileName,
          bytesFuture: bytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectable = _selectableDocs;
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<ConsignmentReportPeriodPreset>(
                  value: _preset,
                  decoration: const InputDecoration(labelText: 'Período'),
                  items: const [
                    DropdownMenuItem(value: ConsignmentReportPeriodPreset.today, child: Text('Hoje')),
                    DropdownMenuItem(value: ConsignmentReportPeriodPreset.yesterday, child: Text('Ontem')),
                    DropdownMenuItem(value: ConsignmentReportPeriodPreset.last7Days, child: Text('Últimos 7 dias')),
                    DropdownMenuItem(value: ConsignmentReportPeriodPreset.thisMonth, child: Text('Este mês')),
                    DropdownMenuItem(value: ConsignmentReportPeriodPreset.previousMonth, child: Text('Mês anterior')),
                    DropdownMenuItem(value: ConsignmentReportPeriodPreset.custom, child: Text('Personalizado')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    if (v == ConsignmentReportPeriodPreset.custom) {
                      final now = DateTime.now();
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 3),
                        lastDate: now,
                        initialDateRange: DateTimeRange(
                          start: _customStart ?? DateTime(now.year, now.month, 1),
                          end: _customEnd ?? now,
                        ),
                      );
                      if (range != null) {
                        _customStart = range.start;
                        _customEnd = range.end;
                      }
                    }
                    setState(() => _preset = v);
                    await _load();
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _resellerId,
                  decoration: const InputDecoration(labelText: 'Revendedor'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                    ..._resellers.map(
                      (r) => DropdownMenuItem<String?>(
                        value: r.resellerId,
                        child: Text(r.displayName),
                      ),
                    ),
                  ],
                  onChanged: (v) async {
                    setState(() => _resellerId = v);
                    await _load();
                  },
                ),
                const SizedBox(height: 12),
                if (widget.kind != ConsignmentReportKind.settlement)
                  DropdownButtonFormField<String?>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todos')),
                      DropdownMenuItem(value: 'DRAFT', child: Text('Rascunho')),
                      DropdownMenuItem(value: 'ISSUED', child: Text('Em consignação')),
                      DropdownMenuItem(value: 'SETTLED', child: Text('Acertado')),
                      DropdownMenuItem(value: 'CANCELLED', child: Text('Cancelado')),
                    ],
                    onChanged: (v) async {
                      setState(() => _status = v);
                      await _load();
                    },
                  ),
                if (widget.kind != ConsignmentReportKind.general) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectable.any((d) => d.id == _consignmentId) ? _consignmentId : null,
                    decoration: const InputDecoration(labelText: 'Consignação'),
                    items: [
                      for (final d in selectable)
                        DropdownMenuItem(
                          value: d.id,
                          child: Text(
                            '${d.resellerName} · ${DateFormat('dd/MM/yy').format((d.issuedAt ?? d.createdAt ?? DateTime.now()).toLocal())} · ${consignmentStatusLabel(d.status)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _consignmentId = v),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _openPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Visualizar'),
                ),
              ],
            ),
    );
  }
}

/// Opens order/settlement/addition preview for a known consignment.
Future<void> openConsignmentReportPreview({
  required BuildContext context,
  required String lojaId,
  required ConsignmentDoc doc,
  required ConsignmentReportKind kind,
  String? additionId,
}) async {
  if (kind == ConsignmentReportKind.settlement && !doc.isSettled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Acerto disponível apenas após finalizar o acerto.')),
    );
    return;
  }
  if (kind == ConsignmentReportKind.addition) {
    var id = (additionId ?? '').trim();
    if (id.isEmpty) {
      for (var i = doc.additions.length - 1; i >= 0; i--) {
        final a = doc.additions[i];
        final kindLabel = '${a['kind'] ?? ''}';
        if (kindLabel == 'INITIAL') continue;
        id = '${a['additionId'] ?? ''}'.trim();
        if (id.isNotEmpty) break;
      }
    }
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum acréscimo encontrado para imprimir.')),
      );
      return;
    }
    additionId = id;
  }
  ConsignmentReseller? reseller;
  try {
    final list = await ConsignmentService.watchResellers(lojaId).first;
    reseller = list.where((r) => r.resellerId == doc.resellerId).firstOrNull;
  } catch (_) {}
  late final String fileName;
  late final Future<Uint8List> bytes;
  late final String title;
  switch (kind) {
    case ConsignmentReportKind.order:
      fileName = ConsignmentReportDataService.orderFileName(doc);
      bytes = ConsignmentReportActions.buildOrderBytes(lojaId: lojaId, doc: doc, reseller: reseller);
      title = 'Relatório do pedido';
      break;
    case ConsignmentReportKind.settlement:
      fileName = ConsignmentReportDataService.settlementFileName(doc);
      bytes = ConsignmentReportActions.buildSettlementBytes(lojaId: lojaId, doc: doc, reseller: reseller);
      title = 'Relatório de acerto';
      break;
    case ConsignmentReportKind.addition:
      fileName = ConsignmentReportDataService.additionFileName(doc, additionId!);
      bytes = ConsignmentReportActions.buildAdditionBytes(
        lojaId: lojaId,
        doc: doc,
        additionId: additionId,
        reseller: reseller,
      );
      title = 'Comprovante de acréscimo';
      break;
    case ConsignmentReportKind.general:
      return;
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ConsignmentReportPreviewScreen(
        title: title,
        fileName: fileName,
        bytesFuture: bytes,
      ),
    ),
  );
}
