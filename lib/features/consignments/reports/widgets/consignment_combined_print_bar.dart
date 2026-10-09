import 'package:flutter/material.dart';

import '../../consignment_models.dart';
import '../consignment_report_data.dart';
import '../screens/consignment_reports_hub_screen.dart';

/// Bottom bar of the "Selecionar" mode: prints the selected consignments in one PDF.
class ConsignmentCombinedPrintBar extends StatelessWidget {
  const ConsignmentCombinedPrintBar({
    super.key,
    required this.lojaId,
    required this.selected,
  });

  final String lojaId;
  final List<ConsignmentDoc> selected;

  @override
  Widget build(BuildContext context) {
    final count = selected.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                count == 0
                    ? 'Selecione 2 ou mais consignações da mesma cliente.'
                    : '$count selecionada${count == 1 ? '' : 's'}',
              ),
            ),
            FilledButton.icon(
              key: const Key('consignment_print_selected'),
              onPressed: count < 2
                  ? null
                  : () => openCombinedConsignmentReportPreview(
                        context: context,
                        lojaId: lojaId,
                        docs: selected,
                      ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir selecionadas'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leading checkbox for a consignment row in "Selecionar" mode.
class ConsignmentSelectCheckbox extends StatelessWidget {
  const ConsignmentSelectCheckbox({
    super.key,
    required this.doc,
    required this.selected,
    required this.onChanged,
  });

  final ConsignmentDoc doc;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = ConsignmentCombinedReportPlanner.canSelect(doc);
    return Checkbox(
      key: Key('consignment_select_${doc.id}'),
      value: enabled && selected,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
    );
  }
}
