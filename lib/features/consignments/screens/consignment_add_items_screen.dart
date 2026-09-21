import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_errors.dart';
import '../consignment_models.dart';
import '../consignment_product_picker.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import '../consignment_validation.dart';
import '../reports/consignment_report_actions.dart';
import '../reports/screens/consignment_reports_hub_screen.dart';

class ConsignmentAddItemsScreen extends StatefulWidget {
  const ConsignmentAddItemsScreen({
    super.key,
    required this.lojaId,
    required this.doc,
  });

  final String lojaId;
  final ConsignmentDoc doc;

  @override
  State<ConsignmentAddItemsScreen> createState() => _ConsignmentAddItemsScreenState();
}

class _ConsignmentAddItemsScreenState extends State<ConsignmentAddItemsScreen> {
  final List<ConsignmentDraftLine> _lines = [];
  bool _busy = false;

  Future<void> _addProduct() async {
    final line = await pickConsignmentProductLine(
      context: context,
      lojaId: widget.lojaId,
    );
    if (line == null || !mounted) return;
    setState(() => _lines.add(line));
  }

  Future<void> _submit() async {
    if (_busy || ConsignmentService.addItemsInFlight) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um produto.')),
      );
      return;
    }
    final total = consignmentDraftTotalQty(_lines);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar acréscimo'),
        content: Text(
          'Adicionar $total peça${total == 1 ? '' : 's'} à consignação de ${widget.doc.resellerName}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final result = await ConsignmentService.addItems(
        lojaId: widget.lojaId,
        consignmentId: widget.doc.id,
        expectedRevision: widget.doc.revision,
        lines: _lines,
      );
      if (!mounted) return;
      final additionId = (result['additionId'] ?? '').toString();
      final updated = await ConsignmentService.getConsignment(widget.lojaId, widget.doc.id);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Peças adicionadas à consignação com sucesso.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'view'), child: const Text('VER CONSIGNAÇÃO')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'print'), child: const Text('IMPRIMIR ACRÉSCIMO')),
          ],
        ),
      );
      if (action == 'print' && updated != null && mounted) {
        await openConsignmentReportPreview(
          context: context,
          lojaId: widget.lojaId,
          doc: updated,
          kind: ConsignmentReportKind.addition,
          additionId: additionId.isEmpty ? null : additionId,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ConsignmentException
          ? e.message
          : ConsignmentException.userMessage('SERVER', e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Adicionar peças')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Consignação ${widget.doc.id}', style: MpType.caption),
          Text(widget.doc.resellerName, style: MpType.title),
          const SizedBox(height: 12),
          for (var i = 0; i < _lines.length; i++)
            Card(
              child: ListTile(
                title: Text(_lines[i].productName),
                subtitle: Text(
                  '${_lines[i].variationKey.isEmpty ? 'Simples' : '${_lines[i].variationKey.size} / ${_lines[i].variationKey.color}'}'
                  ' · ${consignmentMoney.format(_lines[i].unitSalePrice)}',
                ),
                trailing: SizedBox(
                  width: 110,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: '${_lines[i].qtySent}',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Qtd'),
                          onChanged: (v) {
                            final n = int.tryParse(v.trim()) ?? 1;
                            setState(() => _lines[i].qtySent = n < 1 ? 1 : n);
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _lines.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _addProduct,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar produto'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar acréscimo'),
          ),
        ],
      ),
    );
  }
}
