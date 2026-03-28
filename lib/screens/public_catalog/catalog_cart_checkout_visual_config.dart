// lib/screens/public_catalog/catalog_cart_checkout_visual_config.dart
// Tokens visuais do carrinho/checkout público + oferta de cupom de primeira compra (config Firestore).

import 'package:flutter/material.dart';

import 'catalog_helpers.dart';
import 'catalog_theme.dart';

/// Chaves opcionais em `uiColors` para personalizar o carrinho/checkout.
/// Documentação espelhada em [catalog_ui_color_reference.dart].
abstract final class CatalogCartColorKeys {
  CatalogCartColorKeys._();

  static const cartBackground = 'cartBackground';
  static const cartCardBackground = 'cartCardBackground';
  static const cartSectionTitleColor = 'cartSectionTitleColor';
  static const cartPrimaryTextColor = 'cartPrimaryTextColor';
  static const cartSecondaryTextColor = 'cartSecondaryTextColor';
  static const cartMutedTextColor = 'cartMutedTextColor';
  static const cartInputBackground = 'cartInputBackground';
  static const cartInputTextColor = 'cartInputTextColor';
  static const cartInputHintColor = 'cartInputHintColor';
  static const cartInputBorderColor = 'cartInputBorderColor';
  static const cartSummaryBackground = 'cartSummaryBackground';
  static const cartSummaryLabelColor = 'cartSummaryLabelColor';
  static const cartSummaryValueColor = 'cartSummaryValueColor';
  static const cartSummaryDiscountColor = 'cartSummaryDiscountColor';
  static const cartSummaryTotalColor = 'cartSummaryTotalColor';
  static const cartPrimaryActionBackground = 'cartPrimaryActionBackground';
  static const cartPrimaryActionTextColor = 'cartPrimaryActionTextColor';
  static const cartSecondaryActionBackground = 'cartSecondaryActionBackground';
  static const cartSecondaryActionTextColor = 'cartSecondaryActionTextColor';
  static const cartWhatsappButtonBackground = 'cartWhatsappButtonBackground';
  static const cartWhatsappButtonTextColor = 'cartWhatsappButtonTextColor';
  static const cartPixButtonBorderColor = 'cartPixButtonBorderColor';
  static const cartPixButtonTextColor = 'cartPixButtonTextColor';
  static const cartItemDividerColor = 'cartItemDividerColor';
  static const cartRemoveIconColor = 'cartRemoveIconColor';
}

/// Chaves em `uiColors` para a modal de primeira compra.
abstract final class CatalogFirstPurchaseCouponColorKeys {
  CatalogFirstPurchaseCouponColorKeys._();

  static const background = 'firstPurchaseCouponBackground';
  static const titleColor = 'firstPurchaseCouponTitleColor';
  static const textColor = 'firstPurchaseCouponTextColor';
  static const codeBackground = 'firstPurchaseCouponCodeBackground';
  static const codeTextColor = 'firstPurchaseCouponCodeTextColor';
  static const copyButtonBackground = 'firstPurchaseCouponCopyButtonBackground';
  static const copyButtonTextColor = 'firstPurchaseCouponCopyButtonTextColor';
  static const useButtonBackground = 'firstPurchaseCouponUseButtonBackground';
  static const useButtonTextColor = 'firstPurchaseCouponUseButtonTextColor';
  static const borderColor = 'firstPurchaseCouponBorderColor';
  static const shadowColor = 'firstPurchaseCouponShadowColor';
}

/// Cores e estilos do carrinho derivados de `uiColors` + fallbacks do tema.
class CatalogCartUiTokens {
  final Color sheetBackground;
  final Color cartCardBackground;
  final Color sectionTitleColor;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final Color mutedTextColor;
  final Color inputBackground;
  final Color inputTextColor;
  final Color inputHintColor;
  final Color inputBorderColor;
  final Color summaryCardBackground;
  final Color summaryLabelColor;
  final Color summaryValueColor;
  final Color summaryDiscountColor;
  final Color summaryTotalColor;
  final Color primaryActionBackground;
  final Color primaryActionTextColor;
  final Color secondaryActionBackground;
  final Color secondaryActionTextColor;
  final Color whatsappButtonBackground;
  final Color whatsappButtonTextColor;
  final Color pixButtonBorderColor;
  final Color pixButtonTextColor;
  final Color itemDividerColor;
  final Color removeIconColor;

  const CatalogCartUiTokens({
    required this.sheetBackground,
    required this.cartCardBackground,
    required this.sectionTitleColor,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.mutedTextColor,
    required this.inputBackground,
    required this.inputTextColor,
    required this.inputHintColor,
    required this.inputBorderColor,
    required this.summaryCardBackground,
    required this.summaryLabelColor,
    required this.summaryValueColor,
    required this.summaryDiscountColor,
    required this.summaryTotalColor,
    required this.primaryActionBackground,
    required this.primaryActionTextColor,
    required this.secondaryActionBackground,
    required this.secondaryActionTextColor,
    required this.whatsappButtonBackground,
    required this.whatsappButtonTextColor,
    required this.pixButtonBorderColor,
    required this.pixButtonTextColor,
    required this.itemDividerColor,
    required this.removeIconColor,
  });

  static CatalogCartUiTokens fromConfig(
    Map<String, dynamic> cfg, {
    required CatalogThemeData theme,
  }) {
    final uiRaw = cfg['uiColors'];
    final ui = (uiRaw is Map
            ? uiRaw.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{});

    Color c(String key, Color fallback) {
      final raw = ui[key];
      return readColorFromCfg(raw) ?? fallback;
    }

    final card = theme.checkoutCardColor;
    final fieldBg = theme.checkoutFieldBg;
    final fieldText = theme.checkoutFieldTextColor;
    final label = theme.checkoutLabelColor;
    final total = theme.checkoutTotalColor;
    final primary = theme.primaryColor;
    final btnText = theme.btnTextColor;
    final secondary = theme.textSecondaryColor;

    return CatalogCartUiTokens(
      sheetBackground: c(CatalogCartColorKeys.cartBackground, Colors.transparent),
      cartCardBackground: c(CatalogCartColorKeys.cartCardBackground, card),
      sectionTitleColor:
          c(CatalogCartColorKeys.cartSectionTitleColor, label.withValues(alpha: 0.95)),
      primaryTextColor: c(CatalogCartColorKeys.cartPrimaryTextColor, fieldText),
      secondaryTextColor:
          c(CatalogCartColorKeys.cartSecondaryTextColor, fieldText.withValues(alpha: 0.88)),
      mutedTextColor:
          c(CatalogCartColorKeys.cartMutedTextColor, secondary.withValues(alpha: 0.85)),
      inputBackground: c(CatalogCartColorKeys.cartInputBackground, fieldBg),
      inputTextColor: c(CatalogCartColorKeys.cartInputTextColor, fieldText),
      inputHintColor: c(CatalogCartColorKeys.cartInputHintColor, theme.checkoutFieldHint),
      inputBorderColor: c(CatalogCartColorKeys.cartInputBorderColor, theme.checkoutFieldBorder),
      summaryCardBackground: c(CatalogCartColorKeys.cartSummaryBackground, card),
      summaryLabelColor: c(CatalogCartColorKeys.cartSummaryLabelColor, label),
      summaryValueColor: c(CatalogCartColorKeys.cartSummaryValueColor, fieldText),
      summaryDiscountColor:
          c(CatalogCartColorKeys.cartSummaryDiscountColor, theme.checkoutSummaryDeductionColor),
      summaryTotalColor: c(CatalogCartColorKeys.cartSummaryTotalColor, total),
      primaryActionBackground:
          c(CatalogCartColorKeys.cartPrimaryActionBackground, primary),
      primaryActionTextColor:
          c(CatalogCartColorKeys.cartPrimaryActionTextColor, btnText),
      secondaryActionBackground:
          c(CatalogCartColorKeys.cartSecondaryActionBackground, Colors.transparent),
      secondaryActionTextColor:
          c(CatalogCartColorKeys.cartSecondaryActionTextColor, primary),
      whatsappButtonBackground:
          c(CatalogCartColorKeys.cartWhatsappButtonBackground, const Color(0xFF25D366)),
      whatsappButtonTextColor:
          c(CatalogCartColorKeys.cartWhatsappButtonTextColor, Colors.white),
      pixButtonBorderColor:
          c(CatalogCartColorKeys.cartPixButtonBorderColor, const Color(0xFF0D9488)),
      pixButtonTextColor:
          c(CatalogCartColorKeys.cartPixButtonTextColor, const Color(0xFF0D9488)),
      itemDividerColor: c(
        CatalogCartColorKeys.cartItemDividerColor,
        Colors.white.withValues(alpha: 0.06),
      ),
      removeIconColor: c(
        CatalogCartColorKeys.cartRemoveIconColor,
        theme.dangerColor.withValues(alpha: 0.85),
      ),
    );
  }
}

/// Estilo da modal de cupom de primeira compra (cores via `uiColors`).
class CatalogFirstPurchaseCouponStyle {
  final Color background;
  final Color titleColor;
  final Color textColor;
  final Color codeBackground;
  final Color codeTextColor;
  final Color copyButtonBackground;
  final Color copyButtonTextColor;
  final Color useButtonBackground;
  final Color useButtonTextColor;
  final Color borderColor;
  final Color shadowColor;

  const CatalogFirstPurchaseCouponStyle({
    required this.background,
    required this.titleColor,
    required this.textColor,
    required this.codeBackground,
    required this.codeTextColor,
    required this.copyButtonBackground,
    required this.copyButtonTextColor,
    required this.useButtonBackground,
    required this.useButtonTextColor,
    required this.borderColor,
    required this.shadowColor,
  });

  static CatalogFirstPurchaseCouponStyle fromUiColors(
    Map<String, dynamic> uiColors,
    CatalogThemeData theme,
  ) {
    Color c(String key, Color fallback) {
      return readColorFromCfg(uiColors[key]) ?? fallback;
    }

    const softBg = Color(0xFF1C1917);
    const gold = Color(0xFFC4A574);
    return CatalogFirstPurchaseCouponStyle(
      background: c(
        CatalogFirstPurchaseCouponColorKeys.background,
        softBg,
      ),
      titleColor: c(
        CatalogFirstPurchaseCouponColorKeys.titleColor,
        const Color(0xFFF5F0E8),
      ),
      textColor: c(
        CatalogFirstPurchaseCouponColorKeys.textColor,
        const Color(0xFFD6D0C4),
      ),
      codeBackground: c(
        CatalogFirstPurchaseCouponColorKeys.codeBackground,
        Colors.black.withValues(alpha: 0.35),
      ),
      codeTextColor: c(
        CatalogFirstPurchaseCouponColorKeys.codeTextColor,
        gold,
      ),
      copyButtonBackground: c(
        CatalogFirstPurchaseCouponColorKeys.copyButtonBackground,
        Colors.transparent,
      ),
      copyButtonTextColor: c(
        CatalogFirstPurchaseCouponColorKeys.copyButtonTextColor,
        gold,
      ),
      useButtonBackground: c(
        CatalogFirstPurchaseCouponColorKeys.useButtonBackground,
        gold,
      ),
      useButtonTextColor: c(
        CatalogFirstPurchaseCouponColorKeys.useButtonTextColor,
        const Color(0xFF1A1A1A),
      ),
      borderColor: c(
        CatalogFirstPurchaseCouponColorKeys.borderColor,
        gold.withValues(alpha: 0.35),
      ),
      shadowColor: c(
        CatalogFirstPurchaseCouponColorKeys.shadowColor,
        Colors.black.withValues(alpha: 0.55),
      ),
    );
  }
}

/// Oferta configurável em `config.firstPurchaseCoupon` (Firestore).
class CatalogFirstPurchaseCouponOffer {
  final bool enabled;
  final String couponCode;
  final String title;
  final String body;
  /// Se true, só exibe para cliente logado sem pedidos anteriores (consulta assíncrona).
  final bool requireClienteSemPedidos;
  final CatalogFirstPurchaseCouponStyle style;

  const CatalogFirstPurchaseCouponOffer({
    required this.enabled,
    required this.couponCode,
    required this.title,
    required this.body,
    required this.requireClienteSemPedidos,
    required this.style,
  });

  /// `null` = desligado ou sem código.
  static CatalogFirstPurchaseCouponOffer? parse(
    Map<String, dynamic> cfg, {
    required CatalogThemeData theme,
  }) {
    final raw = cfg['firstPurchaseCoupon'];
    final m = (raw is Map
            ? raw.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{});

    final enabled = m['enabled'] == true || m['ativo'] == true;
    final code = (m['code'] ?? m['codigo'] ?? '').toString().trim();
    if (!enabled || code.isEmpty) return null;

    final title = (m['title'] ?? m['titulo'] ?? '')
            .toString()
            .trim()
            .isNotEmpty
        ? (m['title'] ?? m['titulo']).toString().trim()
        : 'Um presente para sua primeira compra';

    final body = (m['body'] ?? m['texto'] ?? m['mensagem'] ?? '')
            .toString()
            .trim()
            .isNotEmpty
        ? (m['body'] ?? m['texto'] ?? m['mensagem']).toString().trim()
        : 'Use este cupom exclusivo e aproveite um desconto especial no seu primeiro pedido.';

    final require = m['requireClienteSemPedidos'] == true ||
        m['somenteSemPedidos'] == true;

    final uiRaw = cfg['uiColors'];
    final ui = (uiRaw is Map
            ? uiRaw.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{});

    return CatalogFirstPurchaseCouponOffer(
      enabled: true,
      couponCode: code.toUpperCase(),
      title: title,
      body: body,
      requireClienteSemPedidos: require,
      style: CatalogFirstPurchaseCouponStyle.fromUiColors(ui, theme),
    );
  }
}

/// Evita repetir a modal na mesma sessão do app (por loja).
class CatalogFirstPurchasePromoSession {
  CatalogFirstPurchasePromoSession._();

  static final Set<String> _shownForLoja = <String>{};

  static bool wasShownForLoja(String lojaId) =>
      _shownForLoja.contains(lojaId.trim());

  static void markShownForLoja(String lojaId) {
    final k = lojaId.trim();
    if (k.isEmpty) return;
    _shownForLoja.add(k);
  }
}
