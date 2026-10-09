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
    final status = Text(
      count == 0
          ? 'Selecione 2 ou mais consignações da mesma cliente.'
          : '$count selecionada${count == 1 ? '' : 's'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final button = FilledButton.icon(
      key: const Key('consignment_print_selected'),
      onPressed: count < 2
          ? null
          : () => openCombinedConsignmentReportPreview(
                context: context,
                lojaId: lojaId,
                docs: selected,
              ),
      icon: const Icon(Icons.print_outlined),
      label: const Text('Imprimir selecionadas', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 480
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [status, const SizedBox(height: 8), button],
                )
              : Row(
                  children: [Expanded(child: status), const SizedBox(width: 12), button],
                ),
        ),
      ),
    );
  }
}

/// AppBar action that toggles the "Selecionar" mode.
class ConsignmentSelectModeButton extends StatelessWidget {
  const ConsignmentSelectModeButton({
    super.key,
    required this.selecting,
    required this.onPressed,
  });

  final bool selecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selecting) {
      return IconButton(
        key: const Key('consignment_select_mode'),
        tooltip: 'Cancelar seleção',
        icon: const Icon(Icons.close),
        onPressed: onPressed,
      );
    }
    // TextButton defaults to colorScheme.primary, which equals the AppBar
    // background in the app theme (black on black); follow the AppBar
    // foreground like the sibling icon actions do.
    return TextButton.icon(
      key: const Key('consignment_select_mode'),
      style: TextButton.styleFrom(foregroundColor: IconTheme.of(context).color),
      onPressed: onPressed,
      icon: const Icon(Icons.checklist),
      label: const Text('Selecionar'),
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
