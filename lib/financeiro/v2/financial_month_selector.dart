import 'package:flutter/material.dart';

import 'financial_month.dart';

class FinancialMonthSelector extends StatelessWidget {
  const FinancialMonthSelector({
    super.key,
    required this.selected,
    required this.range,
    required this.onChanged,
    this.dark = false,
    this.enabled = true,
    this.labelOverride,
  });

  final FinancialMonth selected;
  final FinancialMonthRange? range;
  final ValueChanged<FinancialMonth> onChanged;
  final bool dark;
  final bool enabled;
  final String? labelOverride;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : const Color(0xFF0F172A);
    final muted = dark ? Colors.white70 : const Color(0xFF64748B);
    final previous = enabled && range != null
        ? selected.previousWithin(range!)
        : null;
    final next =
        enabled && range != null ? selected.nextWithin(range!) : null;
    return Row(
      children: [
        IconButton(
          key: const Key('financial-month-previous'),
          tooltip: 'Mês anterior',
          onPressed: previous == null ? null : () => onChanged(previous),
          icon: Icon(Icons.chevron_left, color: previous == null ? muted : color),
        ),
        Expanded(
          child: TextButton(
            key: const Key('financial-month-label'),
            onPressed: enabled && range != null ? () => _abrir(context) : null,
            child: Text(
              range == null
                  ? 'Período indisponível'
                  : (labelOverride ?? selected.labelPt),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('financial-month-next'),
          tooltip: 'Próximo mês',
          onPressed: next == null ? null : () => onChanged(next),
          icon: Icon(Icons.chevron_right, color: next == null ? muted : color),
        ),
      ],
    );
  }

  Future<void> _abrir(BuildContext context) async {
    final months = range?.months ?? const <FinancialMonth>[];
    final chosen = await showDialog<FinancialMonth>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escolha o mês'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: ListView(
            children: [
              for (final month in months)
                ListTile(
                  key: Key('financial-month-${month.year}-${month.month}'),
                  title: Text(month.labelPt),
                  selected: month == selected,
                  onTap: () => Navigator.pop(ctx, month),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) onChanged(chosen);
  }
}
