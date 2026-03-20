// lib/screens/public_catalog/catalog_theme_extension.dart
// Cores específicas do catálogo (produtos, botões) – separadas da cor primária geral.

import 'package:flutter/material.dart';

/// Cores do catálogo injetadas via Theme.extension.
/// Permite configurar nome do produto, preço e botões independentemente da cor primária.
class CatalogThemeExtension extends ThemeExtension<CatalogThemeExtension> {
  final Color productNameColor;
  final Color productPriceColor;
  final Color buttonComprarBg;
  final Color buttonComprarText;
  final Color buttonVerBg;
  final Color buttonVerText;
  final Color chipFilterSelectedBg;
  final Color chipFilterSelectedText;

  const CatalogThemeExtension({
    required this.productNameColor,
    required this.productPriceColor,
    required this.buttonComprarBg,
    required this.buttonComprarText,
    required this.buttonVerBg,
    required this.buttonVerText,
    required this.chipFilterSelectedBg,
    required this.chipFilterSelectedText,
  });

  @override
  CatalogThemeExtension copyWith({
    Color? productNameColor,
    Color? productPriceColor,
    Color? buttonComprarBg,
    Color? buttonComprarText,
    Color? buttonVerBg,
    Color? buttonVerText,
    Color? chipFilterSelectedBg,
    Color? chipFilterSelectedText,
  }) {
    return CatalogThemeExtension(
      productNameColor: productNameColor ?? this.productNameColor,
      productPriceColor: productPriceColor ?? this.productPriceColor,
      buttonComprarBg: buttonComprarBg ?? this.buttonComprarBg,
      buttonComprarText: buttonComprarText ?? this.buttonComprarText,
      buttonVerBg: buttonVerBg ?? this.buttonVerBg,
      buttonVerText: buttonVerText ?? this.buttonVerText,
      chipFilterSelectedBg: chipFilterSelectedBg ?? this.chipFilterSelectedBg,
      chipFilterSelectedText: chipFilterSelectedText ?? this.chipFilterSelectedText,
    );
  }

  @override
  CatalogThemeExtension lerp(
      ThemeExtension<CatalogThemeExtension>? other, double t) {
    if (other is! CatalogThemeExtension) return this;
    return CatalogThemeExtension(
      productNameColor: Color.lerp(productNameColor, other.productNameColor, t)!,
      productPriceColor: Color.lerp(productPriceColor, other.productPriceColor, t)!,
      buttonComprarBg: Color.lerp(buttonComprarBg, other.buttonComprarBg, t)!,
      buttonComprarText: Color.lerp(buttonComprarText, other.buttonComprarText, t)!,
      buttonVerBg: Color.lerp(buttonVerBg, other.buttonVerBg, t)!,
      buttonVerText: Color.lerp(buttonVerText, other.buttonVerText, t)!,
      chipFilterSelectedBg: Color.lerp(chipFilterSelectedBg, other.chipFilterSelectedBg, t)!,
      chipFilterSelectedText: Color.lerp(chipFilterSelectedText, other.chipFilterSelectedText, t)!,
    );
  }
}
