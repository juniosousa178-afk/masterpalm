import 'package:flutter/material.dart';

/// Barra fixa inferior com resumo do carrinho (só apresentação; totais vêm do chamador).
class CatalogStickyCartBar extends StatelessWidget {
  const CatalogStickyCartBar({
    super.key,
    required this.itemCount,
    required this.subtotalLabel,
    required this.primaryColor,
    required this.buttonForegroundColor,
    required this.surfaceColor,
    required this.onOpenCart,
  });

  final int itemCount;
  final String subtotalLabel;
  final Color primaryColor;
  final Color buttonForegroundColor;
  final Color surfaceColor;
  final VoidCallback onOpenCart;

  String get _itensLabel {
    if (itemCount <= 0) return '0 itens';
    if (itemCount == 1) return '1 item';
    return '$itemCount itens';
  }

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).dividerColor.withOpacity(0.2);
    return Material(
      elevation: 8,
      color: surfaceColor,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$_itensLabel | $subtotalLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onOpenCart,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: buttonForegroundColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Ver carrinho'),
            ),
          ],
        ),
      ),
    );
  }
}
