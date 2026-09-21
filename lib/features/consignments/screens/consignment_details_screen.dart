import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../reports/consignment_report_actions.dart';
import '../reports/screens/consignment_reports_hub_screen.dart';
import 'consignment_add_items_screen.dart';
import 'consignment_settle_screen.dart';

class ConsignmentDetailsScreen extends StatefulWidget {
  const ConsignmentDetailsScreen({
    super.key,
    required this.lojaId,
    required this.consignmentId,
  });

  final String lojaId;
  final String consignmentId;

  @override
  State<ConsignmentDetailsScreen> createState() => _ConsignmentDetailsScreenState();
}

class _ConsignmentDetailsScreenState extends State<ConsignmentDetailsScreen> {
  ConsignmentDoc? _doc;
  bool _loading = true;
  String? _error;
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await ConsignmentService.getConsignment(widget.lojaId, widget.consignmentId);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
        if (doc == null) _error = 'Consignação não encontrada.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ConsignmentException ? e.message : e.toString();
      });
    }
  }

  String _lineTitle(Map<String, dynamic> line) {
    final name = '${line['productNameSnapshot'] ?? line['productId']}';
    final vk = ConsignmentVariationKey.fromMap(line['variationKey']);
    if (vk.isEmpty) return name;
    return '$name · ${vk.size}/${vk.color}';
  }

  String _additionLabel(Map<String, dynamic> a) {
    final kind = '${a['kind'] ?? 'ADDITION'}';
    if (kind == 'INITIAL') return 'Envio inicial';
    if (kind == 'DRAFT_ADD') return 'Acréscimo (rascunho)';
    return 'Acréscimo';
  }

  String _additionDate(Map<String, dynamic> a) {
    final raw = a['createdAt'];
    DateTime? when;
    if (raw is DateTime) {
      when = raw;
    } else if (raw != null) {
      try {
        final seconds = raw.seconds;
        if (seconds is int) {
          when = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        }
      } catch (_) {
        when = DateTime.tryParse('$raw');
      }
    }
    if (when == null) return '—';
    return _dateFmt.format(when.toLocal());
  }

  Future<void> _openAddItems(ConsignmentDoc c) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ConsignmentAddItemsScreen(lojaId: widget.lojaId, doc: c),
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _cancel(ConsignmentDoc c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar consignação?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ConsignmentService.cancelDraft(lojaId: widget.lojaId, consignmentId: c.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ConsignmentException
          ? e.message
          : ConsignmentException.userMessage('SERVER', e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _doc;
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: Text(c == null ? 'Consignação' : 'Consignação #${c.id}'),
        actions: [
          if (_doc != null && !_doc!.isCancelled)
            PopupMenuButton<String>(
              onSelected: (v) async {
                final c = _doc!;
                if (v == 'order') {
                  await openConsignmentReportPreview(
                    context: context,
                    lojaId: widget.lojaId,
                    doc: c,
                    kind: ConsignmentReportKind.order,
                  );
                } else if (v == 'settle') {
                  await openConsignmentReportPreview(
                    context: context,
                    lojaId: widget.lojaId,
                    doc: c,
                    kind: ConsignmentReportKind.settlement,
                  );
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'order', child: Text('Relatório do pedido')),
                if (_doc!.isSettled)
                  const PopupMenuItem(value: 'settle', child: Text('Relatório de acerto')),
              ],
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : c == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(c.resellerName, style: MpType.title)),
                            ConsignmentStatusChip(c.status),
                          ],
                        ),
                        Text('Revendedor: ${c.resellerName}', style: MpType.caption),
                        if (c.issuedAt != null)
                          Text('Saída: ${c.issuedAt!.toLocal()}', style: MpType.caption),
                        const SizedBox(height: 16),
                        Text('Produtos consignados', style: MpType.section),
                        const SizedBox(height: 8),
                        for (final line in c.consolidatedLines)
                          Card(
                            child: ListTile(
                              title: Text(_lineTitle(line)),
                              subtitle: Text(
                                'Enviado ${line['qtySent']} · '
                                '${consignmentMoney.format((line['unitSalePriceSnapshot'] as num?)?.toDouble() ?? 0)}',
                              ),
                            ),
                          ),
                        if (c.additions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('Histórico de retiradas', style: MpType.section),
                          const SizedBox(height: 8),
                          for (final raw in c.additions)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_additionDate(raw)} — ${_additionLabel(raw)}',
                                      style: MpType.body.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    for (final l in ((raw['lines'] is List)
                                        ? (raw['lines'] as List).whereType<Map>()
                                        : const <Map>[]))
                                      Text(
                                        '${l['productNameSnapshot'] ?? l['productId']} '
                                        '${_additionLabel(raw) == 'Envio inicial' ? '' : '+'}'
                                        '${l['qtyAdded'] ?? l['qtySent'] ?? 0}',
                                        style: MpType.caption,
                                      ),
                                    if ('${raw['kind']}' != 'INITIAL' &&
                                        '${raw['additionId'] ?? ''}'.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () => openConsignmentReportPreview(
                                          context: context,
                                          lojaId: widget.lojaId,
                                          doc: c,
                                          kind: ConsignmentReportKind.addition,
                                          additionId: '${raw['additionId']}',
                                        ),
                                        icon: const Icon(Icons.print_outlined, size: 18),
                                        label: const Text('Imprimir acréscimo'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        Text('Total de peças enviadas: ${c.totalItemsSent}'),
                        Text('Valor total consignado: ${consignmentMoney.format(c.potentialGrossAmount)}'),
                        if (c.isSettled) ...[
                          Text('Vendido: ${c.totalItemsSold}'),
                          Text('Devolvido: ${c.totalItemsReturned}'),
                          Text('Bruto: ${consignmentMoney.format(c.grossSoldAmount)}'),
                          Text('Comissão: ${consignmentMoney.format(c.commissionAmount)}'),
                          Text('Líquido: ${consignmentMoney.format(c.netAmount)}'),
                        ],
                        const SizedBox(height: 24),
                        if (c.canAddItems) ...[
                          FilledButton.icon(
                            onPressed: () => _openAddItems(c),
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar peças'),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (!c.isCancelled)
                          OutlinedButton.icon(
                            onPressed: () => openConsignmentReportPreview(
                              context: context,
                              lojaId: widget.lojaId,
                              doc: c,
                              kind: ConsignmentReportKind.order,
                            ),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Relatório'),
                          ),
                        if (c.isSettled) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => openConsignmentReportPreview(
                              context: context,
                              lojaId: widget.lojaId,
                              doc: c,
                              kind: ConsignmentReportKind.settlement,
                            ),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Relatório de acerto'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (c.isDraft)
                          FilledButton(
                            onPressed: () async {
                              final total = c.totalItemsSent;
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Confirmar saída'),
                                  content: Text('Confirmar saída de $total peças em consignação?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar em consignação')),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              try {
                                await ConsignmentService.issue(
                                  lojaId: widget.lojaId,
                                  consignmentId: c.id,
                                );
                                await _load();
                              } catch (e) {
                                if (!mounted) return;
                                final msg = e is ConsignmentException
                                    ? e.message
                                    : ConsignmentException.userMessage('SERVER', e.toString());
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                              }
                            },
                            child: const Text('Enviar em consignação'),
                          ),
                        if (c.isIssued)
                          FilledButton(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ConsignmentSettleScreen(
                                    lojaId: widget.lojaId,
                                    consignmentId: c.id,
                                  ),
                                ),
                              );
                              _load();
                            },
                            child: const Text('Fazer acerto'),
                          ),
                        if (c.isDraft) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => _cancel(c),
                            child: const Text('Cancelar'),
                          ),
                        ],
                      ],
                    ),
    );
  }
}
