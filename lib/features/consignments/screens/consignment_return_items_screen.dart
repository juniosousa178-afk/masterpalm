import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../consignment_validation.dart';
import '../reports/consignment_report_data.dart';

/// Store takes pieces back from an ISSUED consignment before settlement.
/// The server is authoritative; this screen only collects exact line + quantity.
class ConsignmentReturnItemsScreen extends StatefulWidget {
  const ConsignmentReturnItemsScreen({
    super.key,
    required this.lojaId,
    required this.doc,
  });

  final String lojaId;
  final ConsignmentDoc doc;

  @override
  State<ConsignmentReturnItemsScreen> createState() => _ConsignmentReturnItemsScreenState();
}

class _ConsignmentReturnItemsScreenState extends State<ConsignmentReturnItemsScreen> {
  late ConsignmentDoc _doc = widget.doc;
  final Map<String, int> _qty = {};
  bool _busy = false;
  // Same selection retried after a network failure must replay, not apply twice.
  String? _operationId;
  String? _operationSignature;

  List<Map<String, dynamic>> get _outstandingLines =>
      _doc.lines.where((l) => consignmentLineOutstanding(l) > 0).toList();

  int get _selectedTotal => _qty.values.fold(0, (s, v) => s + v);

  String _lineId(Map<String, dynamic> l) => '${l['lineId'] ?? ''}';

  void _setQty(Map<String, dynamic> line, int value) {
    final max = consignmentLineOutstanding(line);
    setState(() {
      final v = value.clamp(0, max);
      if (v == 0) {
        _qty.remove(_lineId(line));
      } else {
        _qty[_lineId(line)] = v;
      }
    });
  }

  List<ConsignmentReturnLine> _selection() => [
        for (final line in _outstandingLines)
          if ((_qty[_lineId(line)] ?? 0) > 0)
            ConsignmentReturnLine(
              lineId: _lineId(line),
              productId: '${line['productId'] ?? ''}',
              variationKey: ConsignmentVariationKey.fromMap(line['variationKey']),
              qty: _qty[_lineId(line)]!,
            ),
      ];

  Future<void> _reload() async {
    final fresh = await ConsignmentService.getConsignment(widget.lojaId, _doc.id);
    if (!mounted || fresh == null) return;
    setState(() {
      _doc = fresh;
      _qty.clear();
      _operationId = null;
      _operationSignature = null;
    });
  }

  String _describe(Map<String, dynamic> line, int qty) {
    final name = '${line['productNameSnapshot'] ?? line['productId']}';
    final variation = consignmentReportVariationLabel(line);
    return '$qty × $name${variation.isEmpty ? '' : ' ($variation)'}';
  }

  Future<void> _confirm() async {
    if (_busy || ConsignmentService.returnItemsInFlight) return;
    final selection = _selection();
    if (selection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a quantidade a retirar.')),
      );
      return;
    }
    final byId = {for (final l in _doc.lines) _lineId(l): l};
    for (final s in selection) {
      final error = consignmentReturnQtyError(byId[s.lineId]!, s.qty);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }
    final total = selection.fold<int>(0, (s, l) => s + l.qty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(total == 1 ? 'Retirar peça' : 'Retirar peças'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(consignmentReturnConfirmMessage(
                resellerName: _doc.resellerName,
                totalPieces: total,
              )),
              const SizedBox(height: 12),
              for (final s in selection)
                Text(_describe(byId[s.lineId]!, s.qty), style: MpType.caption),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(
            key: const Key('consignment_return_dialog_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirar e devolver ao estoque'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final signature = [
      _doc.revision,
      for (final s in selection) '${s.lineId}=${s.qty}',
    ].join('|');
    if (_operationSignature != signature) {
      _operationSignature = signature;
      _operationId = ConsignmentService.newReturnOperationId(_doc.id);
    }
    setState(() => _busy = true);
    try {
      await ConsignmentService.returnItems(
        lojaId: widget.lojaId,
        consignmentId: _doc.id,
        expectedRevision: _doc.revision,
        lines: selection,
        operationId: _operationId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(consignmentReturnSuccessMessage(total))),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ConsignmentException
          ? e.message
          : ConsignmentException.userMessage('SERVER', e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (e is ConsignmentException &&
          const {
            'CONSIGNMENT_REVISION_CONFLICT',
            'aborted',
            'RETURN_EXCEEDS_OUTSTANDING',
            'CONSIGNMENT_ALREADY_SETTLED',
            'CONSIGNMENT_CANCELLED',
          }.contains(e.code)) {
        await _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _outstandingLines;
    final reseller = _doc.resellerName.trim().isEmpty ? 'revendedora' : _doc.resellerName.trim();
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Retirar peças')),
      body: !_doc.isIssued
          ? Center(child: Text(ConsignmentException.userMessage('FAILED_PRECONDITION')))
          : lines.isEmpty
              ? const Center(child: Text('Nenhuma peça com a revendedora.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'As peças retiradas voltam ao estoque da loja e não entram no acerto.',
                      style: MpType.caption,
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < lines.length; i++)
                      _ReturnLineCard(
                        key: Key('consignment_return_line_$i'),
                        index: i,
                        line: lines[i],
                        reseller: reseller,
                        qty: _qty[_lineId(lines[i])] ?? 0,
                        onChanged: _busy ? null : (v) => _setQty(lines[i], v),
                      ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('consignment_return_confirm'),
            onPressed: _busy || _selectedTotal == 0 ? null : _confirm,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_selectedTotal == 0
                    ? 'Retirar peças'
                    : 'Retirar $_selectedTotal ${_selectedTotal == 1 ? 'peça' : 'peças'}'),
          ),
        ),
      ),
    );
  }
}

class _ReturnLineCard extends StatelessWidget {
  const _ReturnLineCard({
    super.key,
    required this.index,
    required this.line,
    required this.reseller,
    required this.qty,
    required this.onChanged,
  });

  final int index;
  final Map<String, dynamic> line;
  final String reseller;
  final int qty;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final outstanding = consignmentLineOutstanding(line);
    final code = '${line['productCodeSnapshot'] ?? ''}'.trim();
    final variation = consignmentReportVariationLabel(line);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${line['productNameSnapshot'] ?? line['productId']}', style: MpType.body),
            if (code.isNotEmpty) Text('Código: $code', style: MpType.caption),
            if (variation.isNotEmpty) Text(variation, style: MpType.caption),
            Text(
              'Com $reseller: $outstanding · ${consignmentMoney.format(consignmentLineUnitPrice(line))}',
              style: MpType.caption,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Retirar'),
                IconButton(
                  key: Key('consignment_return_dec_$index'),
                  onPressed: onChanged == null || qty <= 0 ? null : () => onChanged!(qty - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$qty', key: Key('consignment_return_qty_$index')),
                IconButton(
                  key: Key('consignment_return_inc_$index'),
                  onPressed: onChanged == null || qty >= outstanding ? null : () => onChanged!(qty + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
