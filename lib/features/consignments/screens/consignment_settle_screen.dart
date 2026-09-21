import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../consignment_validation.dart';
import '../reports/consignment_report_actions.dart';
import '../reports/screens/consignment_reports_hub_screen.dart';

class ConsignmentSettleScreen extends StatefulWidget {
  const ConsignmentSettleScreen({
    super.key,
    required this.lojaId,
    required this.consignmentId,
  });

  final String lojaId;
  final String consignmentId;

  @override
  State<ConsignmentSettleScreen> createState() => _ConsignmentSettleScreenState();
}

class _ConsignmentSettleScreenState extends State<ConsignmentSettleScreen> {
  ConsignmentDoc? _doc;
  List<ConsignmentSettlementLineInput> _lines = [];
  bool _loading = true;
  bool _busy = false;
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
      if (doc == null) {
        setState(() {
          _loading = false;
          _error = 'Consignação não encontrada.';
        });
        return;
      }
      if (doc.isSettled) {
        setState(() {
          _doc = doc;
          _loading = false;
          _error = ConsignmentException.userMessage('CONSIGNMENT_ALREADY_SETTLED');
        });
        return;
      }
      setState(() {
        _doc = doc;
        _lines = [
          for (final line in doc.lines)
            ConsignmentSettlementLineInput(line: line, qtySold: 0),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _confirm() async {
    if (_busy || ConsignmentService.settleInFlight) return;
    if (!consignmentSettlementIsValid(_lines)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ConsignmentException.userMessage('INVALID_SETTLEMENT_TOTAL'))),
      );
      return;
    }
    var sold = 0, returned = 0, gross = 0.0, commission = 0.0;
    for (final l in _lines) {
      sold += l.qtySold;
      returned += l.qtyReturned;
      final price = (l.line['unitSalePriceSnapshot'] as num?)?.toDouble() ?? 0;
      final type = (l.line['commissionType'] ?? 'SEM_COMISSAO').toString();
      final value = (l.line['commissionValueSnapshot'] as num?)?.toDouble() ?? 0;
      final amounts = consignmentLineAmounts(
        qty: l.qtySold,
        unitPrice: price,
        commissionType: type,
        commissionValue: value,
      );
      gross += amounts.gross;
      commission += amounts.commission;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar acerto?'),
        content: Text(
          '$sold peças vendidas\n'
          '$returned peças devolvidas\n'
          'Total vendido ${consignmentMoney.format(gross)}\n'
          'Comissão ${consignmentMoney.format(commission)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar acerto')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ConsignmentService.settle(
        lojaId: widget.lojaId,
        consignmentId: widget.consignmentId,
        lines: [
          for (final l in _lines)
            {
              'lineId': l.line['lineId'],
              'productId': l.line['productId'],
              'variationKey': l.line['variationKey'] ?? {'size': '', 'color': '', 'extra': ''},
              'qtySold': l.qtySold,
              'qtyReturned': l.qtyReturned,
            },
        ],
      );
      if (!mounted) return;
      final settled = await ConsignmentService.getConsignment(widget.lojaId, widget.consignmentId);
      if (!mounted) return;
      if (settled != null && settled.isSettled) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Acerto concluído'),
            content: const Text('Deseja imprimir ou gerar o PDF do acerto?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: const Text('Agora não')),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'print'), child: const Text('Imprimir / PDF')),
            ],
          ),
        );
        if (action == 'print' && mounted) {
          await openConsignmentReportPreview(
            context: context,
            lojaId: widget.lojaId,
            doc: settled,
            kind: ConsignmentReportKind.settlement,
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ConsignmentException
          ? e.message
          : ConsignmentException.userMessage('SERVER', e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (e is ConsignmentException && e.code == 'CONSIGNMENT_ALREADY_SETTLED') {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Acerto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final line in _lines)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${line.line['productNameSnapshot'] ?? line.line['productId']}',
                                  style: MpType.body),
                              Text('Enviado: ${line.qtySent}'),
                              Row(
                                children: [
                                  const Text('Vendido'),
                                  Expanded(
                                    child: Slider(
                                      min: 0,
                                      max: line.qtySent.toDouble(),
                                      divisions: line.qtySent == 0 ? 1 : line.qtySent,
                                      value: line.qtySold.clamp(0, line.qtySent).toDouble(),
                                      label: '${line.qtySold}',
                                      onChanged: (v) => setState(() => line.qtySold = v.round()),
                                    ),
                                  ),
                                  Text('${line.qtySold}'),
                                ],
                              ),
                              Text('Devolvido: ${line.qtyReturned}'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _confirm,
                      child: _busy
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Confirmar acerto'),
                    ),
                  ],
                ),
    );
  }
}
