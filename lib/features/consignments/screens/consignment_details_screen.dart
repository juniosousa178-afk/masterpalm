import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = _doc;
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: const Text('Consignação'),
        actions: [
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
                        if (c.issuedAt != null)
                          Text('Saída: ${c.issuedAt!.toLocal()}', style: MpType.caption),
                        const SizedBox(height: 12),
                        for (final line in c.lines)
                          Card(
                            child: ListTile(
                              title: Text('${line['productNameSnapshot'] ?? line['productId']}'),
                              subtitle: Text(
                                'Enviado ${line['qtySent']} · '
                                '${consignmentMoney.format((line['unitSalePriceSnapshot'] as num?)?.toDouble() ?? 0)}',
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text('Total potencial: ${consignmentMoney.format(c.potentialGrossAmount)}'),
                        if (c.isSettled) ...[
                          Text('Vendido: ${c.totalItemsSold}'),
                          Text('Devolvido: ${c.totalItemsReturned}'),
                          Text('Bruto: ${consignmentMoney.format(c.grossSoldAmount)}'),
                          Text('Comissão: ${consignmentMoney.format(c.commissionAmount)}'),
                          Text('Líquido: ${consignmentMoney.format(c.netAmount)}'),
                        ],
                        const SizedBox(height: 24),
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
                      ],
                    ),
    );
  }
}
