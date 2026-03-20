// lib/models/ui_colors_config.dart
// Modelo unificado de cores para Catálogo + Carrinho/Checkout
// ✅ Backward compatible com estruturas antigas (theme, checkoutTheme)

import 'package:flutter/material.dart';

/// Cores unificadas para Catálogo + Carrinho/Checkout
class UiColorsConfig {
  // === FUNDO GERAL ===
  final Color background;
  final Color cardBackground;

  // === TEXTOS ===
  final Color textPrimary;
  final Color textSecondary;
  final Color cardTextPrimary;
  final Color cardTextSecondary;
  final Color labelText;

  // === DESTAQUES ===
  final Color primaryColor;
  final Color priceHighlight;
  final Color danger;

  // === CAMPOS (INPUTS) ===
  final Color fieldBackground;
  final Color fieldText;
  final Color fieldHint;
  final Color fieldBorder;

  // === DIVISORES ===
  final Color dividerColor;

  // === BOTÕES PRIMÁRIOS ===
  final Color buttonPrimaryBg;
  final Color buttonPrimaryText;

  // === BOTÕES SECUNDÁRIOS ===
  final Color buttonSecondaryBg;
  final Color buttonSecondaryText;
  final Color buttonSecondaryBorder;

  // === BADGES/CHIPS ===
  final Color badgeBackground;
  final Color badgeText;

  // === ÍCONES ===
  final Color iconColor;

  // === SOMBRAS ===
  final Color shadowColor;

  const UiColorsConfig({
    required this.background,
    required this.cardBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.cardTextPrimary,
    required this.cardTextSecondary,
    required this.labelText,
    required this.primaryColor,
    required this.priceHighlight,
    required this.danger,
    required this.fieldBackground,
    required this.fieldText,
    required this.fieldHint,
    required this.fieldBorder,
    required this.dividerColor,
    required this.buttonPrimaryBg,
    required this.buttonPrimaryText,
    required this.buttonSecondaryBg,
    required this.buttonSecondaryText,
    required this.buttonSecondaryBorder,
    required this.badgeBackground,
    required this.badgeText,
    required this.iconColor,
    required this.shadowColor,
  });

  /// Preset padrão Master (Azul Neon)
  factory UiColorsConfig.masterPadrao() {
    const primary = Color(0xFF00A8FF);
    const bg = Color(0xFF050509);
    const card = Color(0xFF11111A);
    const text = Colors.white;
    const textSec = Color(0xFFB0B0B0);

    return UiColorsConfig(
      background: bg,
      cardBackground: card,
      textPrimary: text,
      textSecondary: textSec,
      cardTextPrimary: text,
      cardTextSecondary: textSec,
      labelText: text,
      primaryColor: primary,
      priceHighlight: const Color(0xFF4ADE80),
      danger: const Color(0xFFEF4444),
      fieldBackground: const Color(0xFF1E1E24),
      fieldText: text,
      fieldHint: const Color(0xFF6B7280),
      fieldBorder: const Color(0xFF374151),
      dividerColor: const Color(0xFF374151),
      buttonPrimaryBg: primary,
      buttonPrimaryText: Colors.white,
      buttonSecondaryBg: Colors.transparent,
      buttonSecondaryText: primary,
      buttonSecondaryBorder: primary,
      badgeBackground: primary.withValues(alpha: 0.15),
      badgeText: primary,
      iconColor: text,
      shadowColor: Colors.black45,
    );
  }

  /// Preset Master Luxo (Dourado)
  factory UiColorsConfig.masterLuxo() {
    const primary = Color(0xFFFFD700);
    const bg = Color(0xFF0A0A0F);
    const card = Color(0xFF14141A);
    const text = Colors.white;
    const textSec = Color(0xFFD4AF37);

    return UiColorsConfig(
      background: bg,
      cardBackground: card,
      textPrimary: text,
      textSecondary: textSec,
      cardTextPrimary: text,
      cardTextSecondary: textSec,
      labelText: text,
      primaryColor: primary,
      priceHighlight: primary,
      danger: const Color(0xFFEF4444),
      fieldBackground: const Color(0xFF1A1A20),
      fieldText: text,
      fieldHint: const Color(0xFF9CA3AF),
      fieldBorder: const Color(0xFF4B5563),
      dividerColor: const Color(0xFF4B5563),
      buttonPrimaryBg: primary,
      buttonPrimaryText: Colors.black,
      buttonSecondaryBg: Colors.transparent,
      buttonSecondaryText: primary,
      buttonSecondaryBorder: primary,
      badgeBackground: primary.withValues(alpha: 0.15),
      badgeText: primary,
      iconColor: text,
      shadowColor: Colors.black54,
    );
  }

  /// Preset Dark Clean (Verde Neon)
  factory UiColorsConfig.darkClean() {
    const primary = Color(0xFF00FFA3);
    const bg = Color(0xFF020617);
    const card = Color(0xFF0F172A);
    const text = Colors.white;
    const textSec = Color(0xFF94A3B8);

    return UiColorsConfig(
      background: bg,
      cardBackground: card,
      textPrimary: text,
      textSecondary: textSec,
      cardTextPrimary: text,
      cardTextSecondary: textSec,
      labelText: text,
      primaryColor: primary,
      priceHighlight: primary,
      danger: const Color(0xFFEF4444),
      fieldBackground: const Color(0xFF1E293B),
      fieldText: text,
      fieldHint: const Color(0xFF64748B),
      fieldBorder: const Color(0xFF334155),
      dividerColor: const Color(0xFF334155),
      buttonPrimaryBg: primary,
      buttonPrimaryText: Colors.black,
      buttonSecondaryBg: Colors.transparent,
      buttonSecondaryText: primary,
      buttonSecondaryBorder: primary,
      badgeBackground: primary.withValues(alpha: 0.15),
      badgeText: primary,
      iconColor: text,
      shadowColor: Colors.black38,
    );
  }

  /// Cria UiColorsConfig a partir de Map (Firestore)
  /// Suporta estrutura nova (uiColors) e antiga (theme + checkoutTheme)
  factory UiColorsConfig.fromMap(Map<String, dynamic> data) {
    Color• parseColor(dynamic v) {
      if (v == null) return null;
      if (v is int) return Color(v);
      if (v is String) {
        final cleaned = v.replaceAll('#', '');
        final parsed = int.tryParse(cleaned, radix: 16);
        if (parsed != null) {
          return cleaned.length == 6 • Color(0xFF000000 | parsed) : Color(parsed);
        }
      }
      return null;
    }

    // Tenta carregar da nova estrutura (uiColors)
    final uiColorsRaw = data['uiColors'];
    final Map<String, dynamic> uiColors = uiColorsRaw is Map
        • Map<String, dynamic>.from(uiColorsRaw)
        : {};

    // Fallback para estrutura antiga (theme + checkoutTheme)
    final themeRaw = data['theme'];
    final Map<String, dynamic> theme = themeRaw is Map
        • Map<String, dynamic>.from(themeRaw)
        : {};

    final checkoutThemeRaw = data['checkoutTheme'];
    final Map<String, dynamic> checkoutTheme = checkoutThemeRaw is Map
        • Map<String, dynamic>.from(checkoutThemeRaw)
        : {};

    // Defaults
    final defaults = UiColorsConfig.masterPadrao();

    // Helper para ler cor com fallbacks
    Color readColorWithFallback(
      String uiKey,
      List<String> themeKeys,
      List<String> checkoutKeys,
      Color defaultColor,
    ) {
      // Tenta uiColors primeiro
      final fromUi = parseColor(uiColors[uiKey]);
      if (fromUi != null) return fromUi;

      // Tenta theme
      for (final key in themeKeys) {
        final fromTheme = parseColor(theme[key]);
        if (fromTheme != null) return fromTheme;
      }

      // Tenta checkoutTheme
      for (final key in checkoutKeys) {
        final fromCheckout = parseColor(checkoutTheme[key]);
        if (fromCheckout != null) return fromCheckout;
      }

      return defaultColor;
    }

    return UiColorsConfig(
      background: readColorWithFallback('background', ['fundo'], [], defaults.background),
      cardBackground: readColorWithFallback('cardBackground', ['card'], ['card'], defaults.cardBackground),
      textPrimary: readColorWithFallback('textPrimary', ['texto'], [], defaults.textPrimary),
      textSecondary: readColorWithFallback('textSecondary', [], ['texto'], defaults.textSecondary),
      cardTextPrimary: readColorWithFallback('cardTextPrimary', ['texto'], [], defaults.cardTextPrimary),
      cardTextSecondary: readColorWithFallback('cardTextSecondary', [], ['texto'], defaults.cardTextSecondary),
      labelText: readColorWithFallback('labelText', [], ['label'], defaults.labelText),
      primaryColor: readColorWithFallback('primaryColor', ['primaria'], [], defaults.primaryColor),
      priceHighlight: readColorWithFallback('priceHighlight', [], ['total'], defaults.priceHighlight),
      danger: readColorWithFallback('danger', [], [], defaults.danger),
      fieldBackground: readColorWithFallback('fieldBackground', [], ['campo'], defaults.fieldBackground),
      fieldText: readColorWithFallback('fieldText', [], ['texto'], defaults.fieldText),
      fieldHint: readColorWithFallback('fieldHint', [], [], defaults.fieldHint),
      fieldBorder: readColorWithFallback('fieldBorder', [], [], defaults.fieldBorder),
      dividerColor: readColorWithFallback('dividerColor', [], [], defaults.dividerColor),
      buttonPrimaryBg: readColorWithFallback('buttonPrimaryBg', ['primaria'], [], defaults.buttonPrimaryBg),
      buttonPrimaryText: readColorWithFallback('buttonPrimaryText', ['botaoTexto'], [], defaults.buttonPrimaryText),
      buttonSecondaryBg: readColorWithFallback('buttonSecondaryBg', [], [], defaults.buttonSecondaryBg),
      buttonSecondaryText: readColorWithFallback('buttonSecondaryText', ['primaria'], [], defaults.buttonSecondaryText),
      buttonSecondaryBorder: readColorWithFallback('buttonSecondaryBorder', ['primaria'], [], defaults.buttonSecondaryBorder),
      badgeBackground: readColorWithFallback('badgeBackground', [], [], defaults.badgeBackground),
      badgeText: readColorWithFallback('badgeText', ['primaria'], [], defaults.badgeText),
      iconColor: readColorWithFallback('iconColor', ['texto'], [], defaults.iconColor),
      shadowColor: readColorWithFallback('shadowColor', [], [], defaults.shadowColor),
    );
  }

  /// Converte para Map (para salvar no Firestore)
  Map<String, dynamic> toMap() {
    return {
      'background': background.toARGB32(),
      'cardBackground': cardBackground.toARGB32(),
      'textPrimary': textPrimary.toARGB32(),
      'textSecondary': textSecondary.toARGB32(),
      'cardTextPrimary': cardTextPrimary.toARGB32(),
      'cardTextSecondary': cardTextSecondary.toARGB32(),
      'labelText': labelText.toARGB32(),
      'primaryColor': primaryColor.toARGB32(),
      'priceHighlight': priceHighlight.toARGB32(),
      'danger': danger.toARGB32(),
      'fieldBackground': fieldBackground.toARGB32(),
      'fieldText': fieldText.toARGB32(),
      'fieldHint': fieldHint.toARGB32(),
      'fieldBorder': fieldBorder.toARGB32(),
      'dividerColor': dividerColor.toARGB32(),
      'buttonPrimaryBg': buttonPrimaryBg.toARGB32(),
      'buttonPrimaryText': buttonPrimaryText.toARGB32(),
      'buttonSecondaryBg': buttonSecondaryBg.toARGB32(),
      'buttonSecondaryText': buttonSecondaryText.toARGB32(),
      'buttonSecondaryBorder': buttonSecondaryBorder.toARGB32(),
      'badgeBackground': badgeBackground.toARGB32(),
      'badgeText': badgeText.toARGB32(),
      'iconColor': iconColor.toARGB32(),
      'shadowColor': shadowColor.toARGB32(),
    };
  }

  /// Gera estrutura legada (theme + checkoutTheme) para backward compatibility
  Map<String, dynamic> toLegacyMap() {
    return {
      'theme': {
        'fundo': background.toARGB32(),
        'card': cardBackground.toARGB32(),
        'texto': textPrimary.toARGB32(),
        'primaria': primaryColor.toARGB32(),
        'botaoTexto': buttonPrimaryText.toARGB32(),
      },
      'checkoutTheme': {
        'card': cardBackground.toARGB32(),
        'campo': fieldBackground.toARGB32(),
        'texto': textSecondary.toARGB32(),
        'label': labelText.toARGB32(),
        'total': priceHighlight.toARGB32(),
      },
    };
  }

  /// Copia com modificações
  UiColorsConfig copyWith({
    Color• background,
    Color• cardBackground,
    Color• textPrimary,
    Color• textSecondary,
    Color• cardTextPrimary,
    Color• cardTextSecondary,
    Color• labelText,
    Color• primaryColor,
    Color• priceHighlight,
    Color• danger,
    Color• fieldBackground,
    Color• fieldText,
    Color• fieldHint,
    Color• fieldBorder,
    Color• dividerColor,
    Color• buttonPrimaryBg,
    Color• buttonPrimaryText,
    Color• buttonSecondaryBg,
    Color• buttonSecondaryText,
    Color• buttonSecondaryBorder,
    Color• badgeBackground,
    Color• badgeText,
    Color• iconColor,
    Color• shadowColor,
  }) {
    return UiColorsConfig(
      background: background ?• this.background,
      cardBackground: cardBackground ?• this.cardBackground,
      textPrimary: textPrimary ?• this.textPrimary,
      textSecondary: textSecondary ?• this.textSecondary,
      cardTextPrimary: cardTextPrimary ?• this.cardTextPrimary,
      cardTextSecondary: cardTextSecondary ?• this.cardTextSecondary,
      labelText: labelText ?• this.labelText,
      primaryColor: primaryColor ?• this.primaryColor,
      priceHighlight: priceHighlight ?• this.priceHighlight,
      danger: danger ?• this.danger,
      fieldBackground: fieldBackground ?• this.fieldBackground,
      fieldText: fieldText ?• this.fieldText,
      fieldHint: fieldHint ?• this.fieldHint,
      fieldBorder: fieldBorder ?• this.fieldBorder,
      dividerColor: dividerColor ?• this.dividerColor,
      buttonPrimaryBg: buttonPrimaryBg ?• this.buttonPrimaryBg,
      buttonPrimaryText: buttonPrimaryText ?• this.buttonPrimaryText,
      buttonSecondaryBg: buttonSecondaryBg ?• this.buttonSecondaryBg,
      buttonSecondaryText: buttonSecondaryText ?• this.buttonSecondaryText,
      buttonSecondaryBorder: buttonSecondaryBorder ?• this.buttonSecondaryBorder,
      badgeBackground: badgeBackground ?• this.badgeBackground,
      badgeText: badgeText ?• this.badgeText,
      iconColor: iconColor ?• this.iconColor,
      shadowColor: shadowColor ?• this.shadowColor,
    );
  }
}

/// Cores separadas para o Cabeçalho do Catálogo
class CatalogHeaderColors {
  final Color background;
  final Color text;
  final Color icon;
  final Color searchBackground;
  final Color searchText;
  final Color searchHint;

  const CatalogHeaderColors({
    required this.background,
    required this.text,
    required this.icon,
    required this.searchBackground,
    required this.searchText,
    required this.searchHint,
  });

  factory CatalogHeaderColors.defaults(Color bgFallback) {
    return CatalogHeaderColors(
      background: bgFallback,
      text: Colors.white,
      icon: Colors.white,
      searchBackground: Colors.white.withValues(alpha: 0.1),
      searchText: Colors.white,
      searchHint: Colors.white70,
    );
  }

  factory CatalogHeaderColors.fromMap(Map<String, dynamic> data, Color bgFallback) {
    Color• parseColor(dynamic v) {
      if (v == null) return null;
      if (v is int) return Color(v);
      if (v is String) {
        final cleaned = v.replaceAll('#', '');
        final parsed = int.tryParse(cleaned, radix: 16);
        if (parsed != null) {
          return cleaned.length == 6 • Color(0xFF000000 | parsed) : Color(parsed);
        }
      }
      return null;
    }

    // Lê de catalogHeaderColors ou de theme.cabecalho (legado)
    final headerColorsRaw = data['catalogHeaderColors'];
    final Map<String, dynamic> headerColors = headerColorsRaw is Map
        • Map<String, dynamic>.from(headerColorsRaw)
        : {};

    // Fallback para theme.cabecalho (legado)
    final themeRaw = data['theme'];
    final Map<String, dynamic> theme = themeRaw is Map
        • Map<String, dynamic>.from(themeRaw)
        : {};

    final defaults = CatalogHeaderColors.defaults(bgFallback);

    return CatalogHeaderColors(
      background: parseColor(headerColors['background']) ??
          parseColor(theme['cabecalho']) ??
          defaults.background,
      text: parseColor(headerColors['text']) ?• defaults.text,
      icon: parseColor(headerColors['icon']) ?• defaults.icon,
      searchBackground: parseColor(headerColors['searchBackground']) ?• defaults.searchBackground,
      searchText: parseColor(headerColors['searchText']) ?• defaults.searchText,
      searchHint: parseColor(headerColors['searchHint']) ?• defaults.searchHint,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'background': background.toARGB32(),
      'text': text.toARGB32(),
      'icon': icon.toARGB32(),
      'searchBackground': searchBackground.toARGB32(),
      'searchText': searchText.toARGB32(),
      'searchHint': searchHint.toARGB32(),
    };
  }

  CatalogHeaderColors copyWith({
    Color• background,
    Color• text,
    Color• icon,
    Color• searchBackground,
    Color• searchText,
    Color• searchHint,
  }) {
    return CatalogHeaderColors(
      background: background ?• this.background,
      text: text ?• this.text,
      icon: icon ?• this.icon,
      searchBackground: searchBackground ?• this.searchBackground,
      searchText: searchText ?• this.searchText,
      searchHint: searchHint ?• this.searchHint,
    );
  }
}

/// Cores separadas para o Rodapé do Catálogo
class CatalogFooterColors {
  final Color background;
  final Color text;
  final Color textSecondary;
  final Color icon;
  final Color link;
  final Color divider;

  const CatalogFooterColors({
    required this.background,
    required this.text,
    required this.textSecondary,
    required this.icon,
    required this.link,
    required this.divider,
  });

  factory CatalogFooterColors.defaults(Color bgFallback, Color primaryFallback) {
    return CatalogFooterColors(
      background: bgFallback,
      text: Colors.white,
      textSecondary: Colors.white70,
      icon: Colors.white70,
      link: primaryFallback,
      divider: Colors.white24,
    );
  }

  factory CatalogFooterColors.fromMap(Map<String, dynamic> data, Color bgFallback, Color primaryFallback) {
    Color• parseColor(dynamic v) {
      if (v == null) return null;
      if (v is int) return Color(v);
      if (v is String) {
        final cleaned = v.replaceAll('#', '');
        final parsed = int.tryParse(cleaned, radix: 16);
        if (parsed != null) {
          return cleaned.length == 6 • Color(0xFF000000 | parsed) : Color(parsed);
        }
      }
      return null;
    }

    final footerColorsRaw = data['catalogFooterColors'];
    final Map<String, dynamic> footerColors = footerColorsRaw is Map
        • Map<String, dynamic>.from(footerColorsRaw)
        : {};

    final defaults = CatalogFooterColors.defaults(bgFallback, primaryFallback);

    return CatalogFooterColors(
      background: parseColor(footerColors['background']) ?• defaults.background,
      text: parseColor(footerColors['text']) ?• defaults.text,
      textSecondary: parseColor(footerColors['textSecondary']) ?• defaults.textSecondary,
      icon: parseColor(footerColors['icon']) ?• defaults.icon,
      link: parseColor(footerColors['link']) ?• defaults.link,
      divider: parseColor(footerColors['divider']) ?• defaults.divider,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'background': background.toARGB32(),
      'text': text.toARGB32(),
      'textSecondary': textSecondary.toARGB32(),
      'icon': icon.toARGB32(),
      'link': link.toARGB32(),
      'divider': divider.toARGB32(),
    };
  }

  CatalogFooterColors copyWith({
    Color• background,
    Color• text,
    Color• textSecondary,
    Color• icon,
    Color• link,
    Color• divider,
  }) {
    return CatalogFooterColors(
      background: background ?• this.background,
      text: text ?• this.text,
      textSecondary: textSecondary ?• this.textSecondary,
      icon: icon ?• this.icon,
      link: link ?• this.link,
      divider: divider ?• this.divider,
    );
  }
}

