// Seção qty + teto de estoque + stepper na linha do carrinho do catálogo público.
// Extrai a costura imediata acima do [CatalogCartQuantityStepper] (CarrinhoSheetWeb).

import 'package:flutter/material.dart';

import '../catalog_estoque_helper.dart';
import 'catalog_cart_quantity_stepper.dart';

class CatalogCartLineQuantitySection extends StatelessWidget {
  const CatalogCartLineQuantitySection({
    super.key,
    required this.items,
    required this.catalogProducts,
    required this.lineIndex,
    required this.onQuantityDelta,
    required this.primaryTextColor,
    required this.mutedTextColor,
    required this.inputBorderColor,
    required this.inputBackground,
  });

  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> catalogProducts;
  final int lineIndex;
  final Future<void> Function(int index, int delta) onQuantityDelta;

  final Color primaryTextColor;
  final Color mutedTextColor;
  final Color inputBorderColor;
  final Color inputBackground;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty ||
        lineIndex < 0 ||
        lineIndex >= items.length) {
      return const SizedBox.shrink();
    }
    final qty = CatalogEstoqueHelper.parseCartItemQuantidade(
      items[lineIndex]['quantidade'],
    );
    final maxQ = CatalogEstoqueHelper.maxOrderableForCartLine(
      items: items,
      catalogProducts: catalogProducts,
      index: lineIndex,
    );
    final canInc = qty < maxQ;

    return CatalogCartQuantityStepper(
      quantity: qty,
      canIncrement: canInc,
      onDecrement: () {
        onQuantityDelta(lineIndex, -1);
      },
      onIncrement: () {
        onQuantityDelta(lineIndex, 1);
      },
      primaryTextColor: primaryTextColor,
      mutedTextColor: mutedTextColor,
      inputBorderColor: inputBorderColor,
      inputBackground: inputBackground,
    );
  }
}
