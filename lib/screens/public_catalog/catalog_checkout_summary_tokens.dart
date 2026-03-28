// lib/screens/public_catalog/catalog_checkout_summary_tokens.dart
// Cores resolvidas do bloco de resumo financeiro do carrinho — derivadas de [CatalogThemeData].

import 'package:flutter/material.dart';

import 'catalog_theme.dart';

/// Tokens usados pelo [CarrinhoSheetWeb] no painel direito (resumo + total).
/// Origem: [CatalogThemeData.fromConfig] → [CatalogCheckoutSummaryTokens.fromThemeData].
class CatalogCheckoutSummaryTokens {
  final Color cardBackground;
  final Color panelGradientStart;
  final Color panelGradientEnd;
  final Color rowLabelColor;
  final Color rowValueColor;
  final Color pixDiscountValueColor;
  final Color deductionValueColor;
  final Color totalRowLabelColor;
  final Color totalRowValueColor;
  final Color totalBannerBackground;
  final Color totalBannerTextColor;
  final Color cardShadowColor;

  const CatalogCheckoutSummaryTokens({
    required this.cardBackground,
    required this.panelGradientStart,
    required this.panelGradientEnd,
    required this.rowLabelColor,
    required this.rowValueColor,
    required this.pixDiscountValueColor,
    required this.deductionValueColor,
    required this.totalRowLabelColor,
    required this.totalRowValueColor,
    required this.totalBannerBackground,
    required this.totalBannerTextColor,
    required this.cardShadowColor,
  });

  factory CatalogCheckoutSummaryTokens.fromThemeData(CatalogThemeData t) {
    return CatalogCheckoutSummaryTokens(
      cardBackground: t.checkoutCardColor,
      panelGradientStart: t.checkoutSummaryPanelTop,
      panelGradientEnd: t.checkoutSummaryPanelBottom,
      rowLabelColor: t.checkoutSummaryRowLabelColor,
      rowValueColor: t.checkoutSummaryRowValueColor,
      pixDiscountValueColor: t.checkoutSummaryPixDiscountColor,
      deductionValueColor: t.checkoutSummaryDeductionColor,
      totalRowLabelColor: t.checkoutSummaryTotalLabelColor,
      totalRowValueColor: t.checkoutTotalColor,
      totalBannerBackground: t.checkoutSummaryTotalBannerBg,
      totalBannerTextColor: t.checkoutSummaryTotalBannerText,
      cardShadowColor: t.checkoutCardShadowColor,
    );
  }

  /// Quando o pai não envia tokens (compatibilidade): espelha os fallbacks antigos do widget.
  factory CatalogCheckoutSummaryTokens.fallbackFromCheckoutColors({
    required Color? checkoutCardColor,
    required Color? checkoutFieldTextColor,
    required Color? checkoutLabelColor,
    required Color? checkoutTotalColor,
  }) {
    final card = checkoutCardColor ?? const Color(0xFF020617);
    final fieldText = checkoutFieldTextColor ?? Colors.white;
    final label = checkoutLabelColor ?? Colors.white;
    final total = checkoutTotalColor ?? const Color(0xFF22C55E);
    return CatalogCheckoutSummaryTokens(
      cardBackground: card,
      panelGradientStart: const Color(0xFF0F172A),
      panelGradientEnd: card.withValues(alpha: 0.95),
      rowLabelColor: label.withValues(alpha: 0.72),
      rowValueColor: fieldText.withValues(alpha: 0.88),
      pixDiscountValueColor: const Color(0xFF69F0AE),
      deductionValueColor: Colors.redAccent,
      totalRowLabelColor: fieldText,
      totalRowValueColor: total,
      totalBannerBackground: total,
      totalBannerTextColor: Colors.white,
      cardShadowColor: const Color(0xFF090909).withValues(alpha: 0.55),
    );
  }
}
