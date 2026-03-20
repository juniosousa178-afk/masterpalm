// lib/screens/public_catalog/catalog_theme.dart
// Parsing de cores e tema do config Firestore – extraído do build() para reduzir rebuilds.

import 'package:flutter/material.dart';

import 'catalog_helpers.dart';

/// Dados de tema parseados do config – evita recalcular em todo rebuild.
class CatalogThemeData {
  final Color primaryColor;
  final Color bgColor;
  final Color cardColor;
  final Color textColor;
  final Color btnTextColor;
  final Color textSecondaryColor;
  final Color cardTextPrimary;
  final Color cardTextSecondary;
  final Color priceHighlightColor;
  final Color dangerColor;
  final Color dividerColor;
  final Color iconColor;
  final Color shadowColor;
  final Color buttonSecondaryBg;
  final Color buttonSecondaryText;
  final Color buttonSecondaryBorder;
  final Color badgeBackground;
  final Color badgeText;
  final Color headerColor;
  final Color headerTextColor;
  final Color headerIconColor;
  final Color headerSearchBg;
  final Color headerSearchText;
  final Color headerSearchHint;
  final Color footerBgColor;
  final Color footerTextColor;
  final Color footerTextSecondary;
  final Color footerIconColor;
  final Color footerLinkColor;
  final Color footerDividerColor;
  final Color checkoutCardColor;
  final Color checkoutFieldBg;
  final Color checkoutFieldBorder;
  final Color checkoutFieldTextColor;
  final Color checkoutLabelColor;
  final Color checkoutTotalColor;
  final Color checkoutFieldHint;
  final Color productNameColor;
  final Color productPriceColor;

  const CatalogThemeData({
    required this.primaryColor,
    required this.bgColor,
    required this.cardColor,
    required this.textColor,
    required this.btnTextColor,
    required this.textSecondaryColor,
    required this.cardTextPrimary,
    required this.cardTextSecondary,
    required this.priceHighlightColor,
    required this.dangerColor,
    required this.dividerColor,
    required this.iconColor,
    required this.shadowColor,
    required this.buttonSecondaryBg,
    required this.buttonSecondaryText,
    required this.buttonSecondaryBorder,
    required this.badgeBackground,
    required this.badgeText,
    required this.headerColor,
    required this.headerTextColor,
    required this.headerIconColor,
    required this.headerSearchBg,
    required this.headerSearchText,
    required this.headerSearchHint,
    required this.footerBgColor,
    required this.footerTextColor,
    required this.footerTextSecondary,
    required this.footerIconColor,
    required this.footerLinkColor,
    required this.footerDividerColor,
    required this.checkoutCardColor,
    required this.checkoutFieldBg,
    required this.checkoutFieldBorder,
    required this.checkoutFieldTextColor,
    required this.checkoutLabelColor,
    required this.checkoutTotalColor,
    required this.checkoutFieldHint,
    required this.productNameColor,
    required this.productPriceColor,
  });

  /// Parseia tema completo a partir do config Firestore.
  static CatalogThemeData fromConfig(Map<String, dynamic> cfg) {
    final themeRaw = cfg['theme'];
    final themeMap = (themeRaw is Map
        ? themeRaw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{});

    final checkoutThemeRaw = cfg['checkoutTheme'];
    final checkoutThemeMap = (checkoutThemeRaw is Map
        ? checkoutThemeRaw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{});

    final uiColorsRaw = cfg['uiColors'];
    final uiColorsMap = (uiColorsRaw is Map
        ? uiColorsRaw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{});

    final headerColorsRaw = cfg['catalogHeaderColors'];
    final headerColorsMap = (headerColorsRaw is Map
        ? headerColorsRaw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{});

    final footerColorsRaw = cfg['catalogFooterColors'];
    final footerColorsMap = (footerColorsRaw is Map
        ? footerColorsRaw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{});

    Color colorFromTheme(String key, Color fallback) {
      final raw = themeMap[key];
      return readColorFromCfg(raw) ?? fallback;
    }

    Color colorFromCheckoutTheme(String key, Color fallback) {
      final raw = checkoutThemeMap[key];
      return readColorFromCfg(raw) ?? fallback;
    }

    Color colorFromUiColors(String key, Color fallback) {
      final raw = uiColorsMap[key];
      return readColorFromCfg(raw) ?? fallback;
    }

    Color colorFromHeaderColors(String key, Color fallback) {
      final raw = headerColorsMap[key];
      return readColorFromCfg(raw) ?? fallback;
    }

    Color colorFromFooterColors(String key, Color fallback) {
      final raw = footerColorsMap[key];
      return readColorFromCfg(raw) ?? fallback;
    }

    final primaryColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('buttonPrimaryBg', colorFromTheme('primaria', const Color(0xFF22C55E)))
        : colorFromTheme('primaria', const Color(0xFF22C55E));
    final bgColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('background', colorFromTheme('fundo', const Color(0xFF020617)))
        : colorFromTheme('fundo', const Color(0xFF020617));
    final cardColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('cardBackground', colorFromTheme('card', const Color(0xFF020617)))
        : colorFromTheme('card', const Color(0xFF020617));
    final textColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('textPrimary', colorFromTheme('texto', Colors.white.withValues(alpha:0.95)))
        : colorFromTheme('texto', Colors.white.withValues(alpha:0.95));
    final btnTextColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('buttonPrimaryText', colorFromTheme('botaoTexto', Colors.white))
        : colorFromTheme('botaoTexto', Colors.white);

    final textSecondaryColor = colorFromUiColors('textSecondary', const Color(0xFFB0B0B0));
    final cardTextPrimary = colorFromUiColors('cardTextPrimary', Colors.white);
    final cardTextSecondary = colorFromUiColors('cardTextSecondary', const Color(0xFFB0B0B0));
    final priceHighlightColor = colorFromUiColors('priceHighlight', const Color(0xFF4ADE80));
    final dangerColor = colorFromUiColors('danger', const Color(0xFFEF4444));
    final dividerColor = colorFromUiColors('dividerColor', const Color(0xFF374151));
    final iconColor = colorFromUiColors('iconColor', Colors.white);
    final shadowColor = colorFromUiColors('shadowColor', Colors.black45);
    final buttonSecondaryBg = colorFromUiColors('buttonSecondaryBg', Colors.transparent);
    final buttonSecondaryText = colorFromUiColors('buttonSecondaryText', primaryColor);
    final buttonSecondaryBorder = colorFromUiColors('buttonSecondaryBorder', primaryColor);
    final badgeBackground = colorFromUiColors('badgeBackground', primaryColor.withValues(alpha:0.15));
    final badgeText = colorFromUiColors('badgeText', primaryColor);

    final headerColor = headerColorsMap.isNotEmpty
        ? colorFromHeaderColors('background', colorFromTheme('cabecalho', bgColor))
        : colorFromTheme('cabecalho', bgColor);
    final headerTextColor = colorFromHeaderColors('text', Colors.white);
    final headerIconColor = colorFromHeaderColors('icon', Colors.white);
    final headerSearchBg = colorFromHeaderColors('searchBackground', Colors.white10);
    final headerSearchText = colorFromHeaderColors('searchText', Colors.white);
    final headerSearchHint = colorFromHeaderColors('searchHint', Colors.white70);

    final footerBgColor = colorFromFooterColors('background', bgColor);
    final footerTextColor = colorFromFooterColors('text', Colors.white);
    final footerTextSecondary = colorFromFooterColors('textSecondary', Colors.white70);
    final footerIconColor = colorFromFooterColors('icon', Colors.white70);
    final footerLinkColor = colorFromFooterColors('link', primaryColor);
    final footerDividerColor = colorFromFooterColors('divider', Colors.white24);

    final checkoutCardColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('cardBackground', colorFromCheckoutTheme('card', cardColor))
        : colorFromCheckoutTheme('card', cardColor);
    final checkoutFieldBg = uiColorsMap.isNotEmpty
        ? colorFromUiColors('fieldBackground', colorFromCheckoutTheme('campo', const Color(0xFF0F172A)))
        : colorFromCheckoutTheme('campo', const Color(0xFF0F172A));
    final checkoutFieldTextColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('fieldText', colorFromCheckoutTheme('texto', textColor))
        : colorFromCheckoutTheme('texto', textColor);
    final checkoutLabelColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('labelText', colorFromCheckoutTheme('label', textColor))
        : colorFromCheckoutTheme('label', textColor);
    final checkoutTotalColor = uiColorsMap.isNotEmpty
        ? colorFromUiColors('priceHighlight', colorFromCheckoutTheme('total', const Color(0xFF22C55E)))
        : colorFromCheckoutTheme('total', const Color(0xFF22C55E));
    final checkoutFieldHint = colorFromUiColors('fieldHint', const Color(0xFF6B7280));
    final checkoutFieldBorder = uiColorsMap.isNotEmpty
        ? colorFromUiColors('fieldBorder', Colors.white.withValues(alpha:0.25))
        : Colors.white.withValues(alpha:0.25);

    final productNameColor = cardTextPrimary;
    final productPriceColor = priceHighlightColor;

    return CatalogThemeData(
      primaryColor: primaryColor,
      bgColor: bgColor,
      cardColor: cardColor,
      textColor: textColor,
      btnTextColor: btnTextColor,
      textSecondaryColor: textSecondaryColor,
      cardTextPrimary: cardTextPrimary,
      cardTextSecondary: cardTextSecondary,
      priceHighlightColor: priceHighlightColor,
      dangerColor: dangerColor,
      dividerColor: dividerColor,
      iconColor: iconColor,
      shadowColor: shadowColor,
      buttonSecondaryBg: buttonSecondaryBg,
      buttonSecondaryText: buttonSecondaryText,
      buttonSecondaryBorder: buttonSecondaryBorder,
      badgeBackground: badgeBackground,
      badgeText: badgeText,
      headerColor: headerColor,
      headerTextColor: headerTextColor,
      headerIconColor: headerIconColor,
      headerSearchBg: headerSearchBg,
      headerSearchText: headerSearchText,
      headerSearchHint: headerSearchHint,
      footerBgColor: footerBgColor,
      footerTextColor: footerTextColor,
      footerTextSecondary: footerTextSecondary,
      footerIconColor: footerIconColor,
      footerLinkColor: footerLinkColor,
      footerDividerColor: footerDividerColor,
      checkoutCardColor: checkoutCardColor,
      checkoutFieldBg: checkoutFieldBg,
      checkoutFieldBorder: checkoutFieldBorder,
      checkoutFieldTextColor: checkoutFieldTextColor,
      checkoutLabelColor: checkoutLabelColor,
      checkoutTotalColor: checkoutTotalColor,
      checkoutFieldHint: checkoutFieldHint,
      productNameColor: productNameColor,
      productPriceColor: productPriceColor,
    );
  }
}

