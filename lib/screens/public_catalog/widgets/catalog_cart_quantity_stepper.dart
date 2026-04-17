// Stepper +/- do carrinho do catálogo público (mesmo comportamento visual do sheet).
// Extraído para teste de widget sem acoplar CarrinhoSheetWeb / Firebase.

import 'package:flutter/material.dart';

class CatalogCartQuantityStepper extends StatelessWidget {
  const CatalogCartQuantityStepper({
    super.key,
    required this.quantity,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
    required this.primaryTextColor,
    required this.mutedTextColor,
    required this.inputBorderColor,
    required this.inputBackground,
  });

  final int quantity;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  final Color primaryTextColor;
  final Color mutedTextColor;
  final Color inputBorderColor;
  final Color inputBackground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Color.alphaBlend(
            inputBorderColor.withOpacity(0.5),
            inputBackground,
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        color: inputBackground,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onDecrement,
            icon: Icon(
              Icons.remove_rounded,
              size: 18,
              color: primaryTextColor,
            ),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 30,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: 'Diminuir',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$quantity',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: primaryTextColor,
              ),
            ),
          ),
          IconButton(
            onPressed: canIncrement ? onIncrement : null,
            icon: Icon(
              Icons.add_rounded,
              size: 18,
              color: canIncrement ? primaryTextColor : mutedTextColor,
            ),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(
              minWidth: 30,
              minHeight: 30,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: 'Aumentar',
          ),
        ],
      ),
    );
  }
}
