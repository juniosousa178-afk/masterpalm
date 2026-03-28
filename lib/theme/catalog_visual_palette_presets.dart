import 'package:flutter/material.dart';

/// Conjunto completo de cores do catálogo (espelha o estado da Loja Config).
/// Usado apenas para presets visuais — mesmos campos que [_applyPreset] preenche.
@immutable
class CatalogPaletteColors {
  const CatalogPaletteColors({
    required this.cFundo,
    required this.cCard,
    required this.cTexto,
    required this.cPrimaria,
    required this.cBotaoTexto,
    required this.cCabecalho,
    required this.cCarrinhoCard,
    required this.cCarrinhoCampo,
    required this.cCarrinhoTexto,
    required this.cCarrinhoLabel,
    required this.cCarrinhoTotal,
    required this.cTextSecondary,
    required this.cCardTextPrimary,
    required this.cCardTextSecondary,
    required this.cPriceHighlight,
    required this.cDanger,
    required this.cFieldHint,
    required this.cFieldBorder,
    required this.cDivider,
    required this.cButtonSecondaryBg,
    required this.cButtonSecondaryText,
    required this.cButtonSecondaryBorder,
    required this.cBadgeBackground,
    required this.cBadgeText,
    required this.cIcon,
    required this.cShadow,
    required this.cHeaderText,
    required this.cHeaderIcon,
    required this.cHeaderSearchBg,
    required this.cHeaderSearchText,
    required this.cHeaderSearchHint,
    required this.cFooterBackground,
    required this.cFooterText,
    required this.cFooterTextSecondary,
    required this.cFooterIcon,
    required this.cFooterLink,
    required this.cFooterDivider,
    required this.cDicasBackground,
    required this.cDicasFooterBg,
    required this.cDicasFooterText,
    required this.cDicasButtonBg,
    required this.cDicasButtonText,
    required this.cDicasTopicPrimary,
    required this.promoBarBg,
    required this.promoBarText,
    required this.heroCardBg,
    required this.heroTitleColor,
    required this.heroSubtitleColor,
    required this.heroButtonBg,
    required this.heroButtonTextColor,
  });

  final Color cFundo;
  final Color cCard;
  final Color cTexto;
  final Color cPrimaria;
  final Color cBotaoTexto;
  final Color cCabecalho;
  final Color cCarrinhoCard;
  final Color cCarrinhoCampo;
  final Color cCarrinhoTexto;
  final Color cCarrinhoLabel;
  final Color cCarrinhoTotal;
  final Color cTextSecondary;
  final Color cCardTextPrimary;
  final Color cCardTextSecondary;
  final Color cPriceHighlight;
  final Color cDanger;
  final Color cFieldHint;
  final Color cFieldBorder;
  final Color cDivider;
  final Color cButtonSecondaryBg;
  final Color cButtonSecondaryText;
  final Color cButtonSecondaryBorder;
  final Color cBadgeBackground;
  final Color cBadgeText;
  final Color cIcon;
  final Color cShadow;
  final Color cHeaderText;
  final Color cHeaderIcon;
  final Color cHeaderSearchBg;
  final Color cHeaderSearchText;
  final Color cHeaderSearchHint;
  final Color cFooterBackground;
  final Color cFooterText;
  final Color cFooterTextSecondary;
  final Color cFooterIcon;
  final Color cFooterLink;
  final Color cFooterDivider;
  final Color cDicasBackground;
  final Color cDicasFooterBg;
  final Color cDicasFooterText;
  final Color cDicasButtonBg;
  final Color cDicasButtonText;
  final Color cDicasTopicPrimary;
  final Color promoBarBg;
  final Color promoBarText;
  final Color heroCardBg;
  final Color heroTitleColor;
  final Color heroSubtitleColor;
  final Color heroButtonBg;
  final Color heroButtonTextColor;

  /// Amostras para preview nos cards (5 tons principais).
  List<Color> get previewSwatches => [
        cFundo,
        cCard,
        cPrimaria,
        cTexto,
        cPriceHighlight,
      ];
}

@immutable
class CatalogVisualPalettePreset {
  const CatalogVisualPalettePreset({
    required this.id,
    required this.title,
    required this.description,
    required this.colors,
  });

  final String id;
  final String title;
  final String description;
  final CatalogPaletteColors colors;
}

/// Presets prontos — aplicar só após confirmação explícita na UI.
abstract final class CatalogVisualPalettePresets {
  static const cleanPremium = CatalogVisualPalettePreset(
    id: 'clean_premium',
    title: 'Clean Premium',
    description: 'Off-white, chumbo suave e cinzas elegantes. Visual limpo e sofisticado.',
    colors: CatalogPaletteColors(
      cFundo: Color(0xFFF5F4F1),
      cCard: Color(0xFFFFFFFF),
      cTexto: Color(0xFF2C2C2C),
      cPrimaria: Color(0xFF354153),
      cBotaoTexto: Color(0xFFFFFFFF),
      cCabecalho: Color(0xFFF5F4F1),
      cCarrinhoCard: Color(0xFFFFFFFF),
      cCarrinhoCampo: Color(0xFFF0EFEB),
      cCarrinhoTexto: Color(0xFF4A4A4A),
      cCarrinhoLabel: Color(0xFF2C2C2C),
      cCarrinhoTotal: Color(0xFF1B4D3E),
      cTextSecondary: Color(0xFF6B6B6B),
      cCardTextPrimary: Color(0xFF2C2C2C),
      cCardTextSecondary: Color(0xFF6B6B6B),
      cPriceHighlight: Color(0xFF1B4D3E),
      cDanger: Color(0xFFDC2626),
      cFieldHint: Color(0xFF8E8E93),
      cFieldBorder: Color(0xFFC8C6C1),
      cDivider: Color(0xFFD1CFC9),
      cButtonSecondaryBg: Colors.transparent,
      cButtonSecondaryText: Color(0xFF354153),
      cButtonSecondaryBorder: Color(0xFF354153),
      cBadgeBackground: Color(0x26354153),
      cBadgeText: Color(0xFF354153),
      cIcon: Color(0xFF354153),
      cShadow: Color(0x66000000),
      cHeaderText: Color(0xFF2C2C2C),
      cHeaderIcon: Color(0xFF354153),
      cHeaderSearchBg: Color(0xFFE8E6E1),
      cHeaderSearchText: Color(0xFF2C2C2C),
      cHeaderSearchHint: Color(0xFF8E8E93),
      cFooterBackground: Color(0xFFECEAE7),
      cFooterText: Color(0xFF2C2C2C),
      cFooterTextSecondary: Color(0xFF6B6B6B),
      cFooterIcon: Color(0xFF6B6B6B),
      cFooterLink: Color(0xFF354153),
      cFooterDivider: Color(0xFFD1CFC9),
      cDicasBackground: Color(0xFFFFFFFF),
      cDicasFooterBg: Color(0xFFF5F4F1),
      cDicasFooterText: Color(0xFF4A4A4A),
      cDicasButtonBg: Color(0xFF354153),
      cDicasButtonText: Color(0xFFFFFFFF),
      cDicasTopicPrimary: Color(0xFF354153),
      promoBarBg: Color(0xFF354153),
      promoBarText: Color(0xFFFFFFFF),
      heroCardBg: Color(0xFFE8E6E1),
      heroTitleColor: Color(0xFF2C2C2C),
      heroSubtitleColor: Color(0xFF6B6B6B),
      heroButtonBg: Color(0xFF354153),
      heroButtonTextColor: Color(0xFFFFFFFF),
    ),
  );

  static const roseChic = CatalogVisualPalettePreset(
    id: 'rose_chic',
    title: 'Rosé Chic',
    description: 'Base clara com rosé queimado e cinzas suaves. Feminino refinado.',
    colors: CatalogPaletteColors(
      cFundo: Color(0xFFFDF6F4),
      cCard: Color(0xFFFFFFFF),
      cTexto: Color(0xFF4A3F42),
      cPrimaria: Color(0xFFB76E79),
      cBotaoTexto: Color(0xFFFFFFFF),
      cCabecalho: Color(0xFFFDF6F4),
      cCarrinhoCard: Color(0xFFFFFFFF),
      cCarrinhoCampo: Color(0xFFF5EDEB),
      cCarrinhoTexto: Color(0xFF6D5E62),
      cCarrinhoLabel: Color(0xFF4A3F42),
      cCarrinhoTotal: Color(0xFF9D5C65),
      cTextSecondary: Color(0xFF8A7E81),
      cCardTextPrimary: Color(0xFF4A3F42),
      cCardTextSecondary: Color(0xFF8A7E81),
      cPriceHighlight: Color(0xFF9D5C65),
      cDanger: Color(0xFFDC2626),
      cFieldHint: Color(0xFFA89B9E),
      cFieldBorder: Color(0xFFE5D5D8),
      cDivider: Color(0xFFE8D8DB),
      cButtonSecondaryBg: Colors.transparent,
      cButtonSecondaryText: Color(0xFFB76E79),
      cButtonSecondaryBorder: Color(0xFFB76E79),
      cBadgeBackground: Color(0x26B76E79),
      cBadgeText: Color(0xFF9D5C65),
      cIcon: Color(0xFFB76E79),
      cShadow: Color(0x4D000000),
      cHeaderText: Color(0xFF4A3F42),
      cHeaderIcon: Color(0xFFB76E79),
      cHeaderSearchBg: Color(0xFFF5EDEB),
      cHeaderSearchText: Color(0xFF4A3F42),
      cHeaderSearchHint: Color(0xFFA89B9E),
      cFooterBackground: Color(0xFFF5EDEB),
      cFooterText: Color(0xFF4A3F42),
      cFooterTextSecondary: Color(0xFF8A7E81),
      cFooterIcon: Color(0xFFB76E79),
      cFooterLink: Color(0xFF9D5C65),
      cFooterDivider: Color(0xFFE5D5D8),
      cDicasBackground: Color(0xFFFFFFFF),
      cDicasFooterBg: Color(0xFFFDF6F4),
      cDicasFooterText: Color(0xFF6D5E62),
      cDicasButtonBg: Color(0xFFB76E79),
      cDicasButtonText: Color(0xFFFFFFFF),
      cDicasTopicPrimary: Color(0xFF9D5C65),
      promoBarBg: Color(0xFFC9A4A8),
      promoBarText: Color(0xFF3D3436),
      heroCardBg: Color(0xFFF5EDEB),
      heroTitleColor: Color(0xFF4A3F42),
      heroSubtitleColor: Color(0xFF8A7E81),
      heroButtonBg: Color(0xFFB76E79),
      heroButtonTextColor: Color(0xFFFFFFFF),
    ),
  );

  static const luxoSuave = CatalogVisualPalettePreset(
    id: 'luxo_suave',
    title: 'Luxo suave',
    description: 'Neutros claros com dourado fosco e contraste discreto. Premium silencioso.',
    colors: CatalogPaletteColors(
      cFundo: Color(0xFFF9F7F2),
      cCard: Color(0xFFFFFFFF),
      cTexto: Color(0xFF3E3A36),
      cPrimaria: Color(0xFF9A8578),
      cBotaoTexto: Color(0xFFFFFFFF),
      cCabecalho: Color(0xFFF9F7F2),
      cCarrinhoCard: Color(0xFFFFFFFF),
      cCarrinhoCampo: Color(0xFFF2EFE8),
      cCarrinhoTexto: Color(0xFF6B6560),
      cCarrinhoLabel: Color(0xFF3E3A36),
      cCarrinhoTotal: Color(0xFF7D6B58),
      cTextSecondary: Color(0xFF8A847C),
      cCardTextPrimary: Color(0xFF3E3A36),
      cCardTextSecondary: Color(0xFF8A847C),
      cPriceHighlight: Color(0xFF7D6B58),
      cDanger: Color(0xFFB45309),
      cFieldHint: Color(0xFFA8A29E),
      cFieldBorder: Color(0xFFD6D1C8),
      cDivider: Color(0xFFE0DBD2),
      cButtonSecondaryBg: Colors.transparent,
      cButtonSecondaryText: Color(0xFF9A8578),
      cButtonSecondaryBorder: Color(0xFF9A8578),
      cBadgeBackground: Color(0x269A8578),
      cBadgeText: Color(0xFF7D6B58),
      cIcon: Color(0xFF9A8578),
      cShadow: Color(0x59000000),
      cHeaderText: Color(0xFF3E3A36),
      cHeaderIcon: Color(0xFF9A8578),
      cHeaderSearchBg: Color(0xFFF2EFE8),
      cHeaderSearchText: Color(0xFF3E3A36),
      cHeaderSearchHint: Color(0xFFA8A29E),
      cFooterBackground: Color(0xFFF2EFE8),
      cFooterText: Color(0xFF3E3A36),
      cFooterTextSecondary: Color(0xFF8A847C),
      cFooterIcon: Color(0xFF9A8578),
      cFooterLink: Color(0xFF7D6B58),
      cFooterDivider: Color(0xFFD6D1C8),
      cDicasBackground: Color(0xFFFFFFFF),
      cDicasFooterBg: Color(0xFFF9F7F2),
      cDicasFooterText: Color(0xFF6B6560),
      cDicasButtonBg: Color(0xFF9A8578),
      cDicasButtonText: Color(0xFFFFFFFF),
      cDicasTopicPrimary: Color(0xFF7D6B58),
      promoBarBg: Color(0xFFC4B5A0),
      promoBarText: Color(0xFF3E3A36),
      heroCardBg: Color(0xFFF2EFE8),
      heroTitleColor: Color(0xFF3E3A36),
      heroSubtitleColor: Color(0xFF8A847C),
      heroButtonBg: Color(0xFF9A8578),
      heroButtonTextColor: Color(0xFFFFFFFF),
    ),
  );

  static const cleanEscuro = CatalogVisualPalettePreset(
    id: 'clean_escuro',
    title: 'Clean escuro',
    description: 'Fundo escuro elegante, superfícies fechadas e destaques em tom quente.',
    colors: CatalogPaletteColors(
      cFundo: Color(0xFF121218),
      cCard: Color(0xFF1E1E26),
      cTexto: Color(0xFFE8E6E3),
      cPrimaria: Color(0xFFD4AF78),
      cBotaoTexto: Color(0xFF121218),
      cCabecalho: Color(0xFF121218),
      cCarrinhoCard: Color(0xFF1E1E26),
      cCarrinhoCampo: Color(0xFF2A2A34),
      cCarrinhoTexto: Color(0xFFB8B5B0),
      cCarrinhoLabel: Color(0xFFE8E6E3),
      cCarrinhoTotal: Color(0xFFD4AF78),
      cTextSecondary: Color(0xFF9C9894),
      cCardTextPrimary: Color(0xFFE8E6E3),
      cCardTextSecondary: Color(0xFF9C9894),
      cPriceHighlight: Color(0xFFD4AF78),
      cDanger: Color(0xFFF87171),
      cFieldHint: Color(0xFF7A7874),
      cFieldBorder: Color(0xFF3F3F4A),
      cDivider: Color(0xFF3F3F4A),
      cButtonSecondaryBg: Colors.transparent,
      cButtonSecondaryText: Color(0xFFD4AF78),
      cButtonSecondaryBorder: Color(0xFFD4AF78),
      cBadgeBackground: Color(0x26D4AF78),
      cBadgeText: Color(0xFFD4AF78),
      cIcon: Color(0xFFD4AF78),
      cShadow: Color(0x99000000),
      cHeaderText: Color(0xFFE8E6E3),
      cHeaderIcon: Color(0xFFD4AF78),
      cHeaderSearchBg: Color(0xFF2A2A34),
      cHeaderSearchText: Color(0xFFE8E6E3),
      cHeaderSearchHint: Color(0xFF9C9894),
      cFooterBackground: Color(0xFF121218),
      cFooterText: Color(0xFFE8E6E3),
      cFooterTextSecondary: Color(0xFF9C9894),
      cFooterIcon: Color(0xFFD4AF78),
      cFooterLink: Color(0xFFD4AF78),
      cFooterDivider: Color(0xFF3F3F4A),
      cDicasBackground: Color(0xFF1E1E26),
      cDicasFooterBg: Color(0xFF121218),
      cDicasFooterText: Color(0xFFB8B5B0),
      cDicasButtonBg: Color(0xFFD4AF78),
      cDicasButtonText: Color(0xFF121218),
      cDicasTopicPrimary: Color(0xFFD4AF78),
      promoBarBg: Color(0xFF2A2A34),
      promoBarText: Color(0xFFD4AF78),
      heroCardBg: Color(0xFF2A2A34),
      heroTitleColor: Color(0xFFE8E6E3),
      heroSubtitleColor: Color(0xFF9C9894),
      heroButtonBg: Color(0xFFD4AF78),
      heroButtonTextColor: Color(0xFF121218),
    ),
  );

  static const neutroSofisticado = CatalogVisualPalettePreset(
    id: 'neutro_sofisticado',
    title: 'Neutro sofisticado',
    description: 'Cinzas, branco e grafite. Universal, profissional e discreto.',
    colors: CatalogPaletteColors(
      cFundo: Color(0xFFF4F4F5),
      cCard: Color(0xFFFFFFFF),
      cTexto: Color(0xFF27272A),
      cPrimaria: Color(0xFF3F3F46),
      cBotaoTexto: Color(0xFFFFFFFF),
      cCabecalho: Color(0xFFF4F4F5),
      cCarrinhoCard: Color(0xFFFFFFFF),
      cCarrinhoCampo: Color(0xFFF4F4F5),
      cCarrinhoTexto: Color(0xFF52525B),
      cCarrinhoLabel: Color(0xFF27272A),
      cCarrinhoTotal: Color(0xFF18181B),
      cTextSecondary: Color(0xFF71717A),
      cCardTextPrimary: Color(0xFF27272A),
      cCardTextSecondary: Color(0xFF71717A),
      cPriceHighlight: Color(0xFF18181B),
      cDanger: Color(0xFFDC2626),
      cFieldHint: Color(0xFFA1A1AA),
      cFieldBorder: Color(0xFFD4D4D8),
      cDivider: Color(0xFFE4E4E7),
      cButtonSecondaryBg: Colors.transparent,
      cButtonSecondaryText: Color(0xFF3F3F46),
      cButtonSecondaryBorder: Color(0xFF3F3F46),
      cBadgeBackground: Color(0x263F3F46),
      cBadgeText: Color(0xFF3F3F46),
      cIcon: Color(0xFF52525B),
      cShadow: Color(0x4D000000),
      cHeaderText: Color(0xFF27272A),
      cHeaderIcon: Color(0xFF3F3F46),
      cHeaderSearchBg: Color(0xFFE4E4E7),
      cHeaderSearchText: Color(0xFF27272A),
      cHeaderSearchHint: Color(0xFFA1A1AA),
      cFooterBackground: Color(0xFFE4E4E7),
      cFooterText: Color(0xFF27272A),
      cFooterTextSecondary: Color(0xFF71717A),
      cFooterIcon: Color(0xFF52525B),
      cFooterLink: Color(0xFF3F3F46),
      cFooterDivider: Color(0xFFD4D4D8),
      cDicasBackground: Color(0xFFFFFFFF),
      cDicasFooterBg: Color(0xFFF4F4F5),
      cDicasFooterText: Color(0xFF52525B),
      cDicasButtonBg: Color(0xFF3F3F46),
      cDicasButtonText: Color(0xFFFFFFFF),
      cDicasTopicPrimary: Color(0xFF3F3F46),
      promoBarBg: Color(0xFF52525B),
      promoBarText: Color(0xFFFFFFFF),
      heroCardBg: Color(0xFFE4E4E7),
      heroTitleColor: Color(0xFF27272A),
      heroSubtitleColor: Color(0xFF71717A),
      heroButtonBg: Color(0xFF3F3F46),
      heroButtonTextColor: Color(0xFFFFFFFF),
    ),
  );

  static const comercialForte = CatalogVisualPalettePreset(
    id: 'comercial_forte',
    title: 'Comercial forte',
    description: 'CTA em destaque sobre fundo claro. Contraste que vende, sem gritar.',
    colors: CatalogPaletteColors(
      cFundo: Color(0xFFFAFAFA),
      cCard: Color(0xFFFFFFFF),
      cTexto: Color(0xFF171717),
      cPrimaria: Color(0xFFDC2626),
      cBotaoTexto: Color(0xFFFFFFFF),
      cCabecalho: Color(0xFFFAFAFA),
      cCarrinhoCard: Color(0xFFFFFFFF),
      cCarrinhoCampo: Color(0xFFF5F5F5),
      cCarrinhoTexto: Color(0xFF404040),
      cCarrinhoLabel: Color(0xFF171717),
      cCarrinhoTotal: Color(0xFF047857),
      cTextSecondary: Color(0xFF737373),
      cCardTextPrimary: Color(0xFF171717),
      cCardTextSecondary: Color(0xFF737373),
      cPriceHighlight: Color(0xFF047857),
      cDanger: Color(0xFFB91C1C),
      cFieldHint: Color(0xFFA3A3A3),
      cFieldBorder: Color(0xFFD4D4D4),
      cDivider: Color(0xFFE5E5E5),
      cButtonSecondaryBg: Colors.transparent,
      cButtonSecondaryText: Color(0xFFDC2626),
      cButtonSecondaryBorder: Color(0xFFDC2626),
      cBadgeBackground: Color(0x26DC2626),
      cBadgeText: Color(0xFFDC2626),
      cIcon: Color(0xFF404040),
      cShadow: Color(0x4D000000),
      cHeaderText: Color(0xFF171717),
      cHeaderIcon: Color(0xFFDC2626),
      cHeaderSearchBg: Color(0xFFF5F5F5),
      cHeaderSearchText: Color(0xFF171717),
      cHeaderSearchHint: Color(0xFFA3A3A3),
      cFooterBackground: Color(0xFFF5F5F5),
      cFooterText: Color(0xFF171717),
      cFooterTextSecondary: Color(0xFF737373),
      cFooterIcon: Color(0xFF525252),
      cFooterLink: Color(0xFFDC2626),
      cFooterDivider: Color(0xFFE5E5E5),
      cDicasBackground: Color(0xFFFFFFFF),
      cDicasFooterBg: Color(0xFFFAFAFA),
      cDicasFooterText: Color(0xFF404040),
      cDicasButtonBg: Color(0xFFDC2626),
      cDicasButtonText: Color(0xFFFFFFFF),
      cDicasTopicPrimary: Color(0xFF047857),
      promoBarBg: Color(0xFFDC2626),
      promoBarText: Color(0xFFFFFFFF),
      heroCardBg: Color(0xFFF5F5F5),
      heroTitleColor: Color(0xFF171717),
      heroSubtitleColor: Color(0xFF737373),
      heroButtonBg: Color(0xFFDC2626),
      heroButtonTextColor: Color(0xFFFFFFFF),
    ),
  );

  static const List<CatalogVisualPalettePreset> all = [
    cleanPremium,
    roseChic,
    luxoSuave,
    cleanEscuro,
    neutroSofisticado,
    comercialForte,
  ];
}
