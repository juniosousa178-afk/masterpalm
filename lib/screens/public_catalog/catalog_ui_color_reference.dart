// lib/screens/public_catalog/catalog_ui_color_reference.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// REFERÊNCIA RÁPIDA — cores do catálogo público (Firestore: config / uiColors)
// ═══════════════════════════════════════════════════════════════════════════
//
// Relacionado:
// - [CatalogThemeData] em catalog_theme.dart — parse completo (página, cards, checkout base).
// - [CatalogCartColorKeys] / [CatalogCartUiTokens] em catalog_cart_checkout_visual_config.dart
//   — lista de itens, campos, botões WhatsApp/PIX, resumo genérico do carrinho.
// - [CatalogCheckoutSummaryColorKeys] abaixo — painel numérico à direita (subtotal/total).
//
// Edite no painel da loja em `uiColors` (Map) salvo em config. Valores: hex "#RRGGBB"
// ou "#AARRGGBB". Fallbacks estão em [CatalogThemeData.fromConfig].
//
// ── FUNDO GERAL ─────────────────────────────────────────────────────────────
//   background              → Página (scaffold)
//   cardBackground          → Cards de produto + fallback do checkout externo
//
// ── TEXTO GERAL / CATÁLOGO ─────────────────────────────────────────────────
//   textPrimary             → Texto principal da página
//   textSecondary           → Texto secundário / muted
//   cardTextPrimary         → Nome do produto no card
//   cardTextSecondary       → Texto secundário no card
//   priceHighlight          → Preço em destaque + total checkout (fallback)
//
// ── BOTÕES PRIMÁRIOS / FILTROS ───────────────────────────────────────────────
//   buttonPrimaryBg         → Fundo botão principal (Comprar, chips selecionados)
//   buttonPrimaryText       → Texto sobre botão primário
//   buttonSecondaryBg       → Fundo botão secundário (Ver)
//   buttonSecondaryText     → Texto botão secundário
//   buttonSecondaryBorder   → Borda botão secundário
//
// ── CHECKOUT / CARRINHO (campos e labels gerais) ────────────────────────────
//   fieldBackground         → Fundo dos inputs
//   fieldText               → Texto digitado
//   fieldHint               → Placeholder
//   fieldBorder             → Borda dos campos
//   labelText               → Labels de formulário
//
// ── RESUMO FINANCEIRO (card escuro interno) — chaves dedicadas ───────────────
//   checkoutSummaryGradientStart   → Topo do gradiente do painel de linhas
//   checkoutSummaryGradientEnd     → Base do gradiente (default: card checkout)
//   checkoutSummaryRowLabel        → Rótulos: Subtotal, Frete, Desconto PIX…
//   checkoutSummaryRowValue        → Valores à direita nas linhas (padrão)
//   checkoutSummaryPixDiscount     → Valor da linha "Desconto PIX"
//   checkoutSummaryDeduction       → Linhas de desconto negativo (ex.: cupom)
//   checkoutSummaryTotalLabel      → Rótulo "Total a pagar"
//   checkoutSummaryTotalBannerBg   → Fundo da faixa "Total R$ …" no topo
//   checkoutSummaryTotalBannerText → Texto sobre a faixa do total
//   checkoutCardShadow             → Sombra do card do resumo (ARGB)
//
// Também existem: theme.* (legado), checkoutTheme.*, catalogHeaderColors.*,
// catalogFooterColors.* — ver [CatalogThemeData.fromConfig].
//
// ── CARRINHO / CHECKOUT (tokens dedicados) — [CatalogCartUiTokens.fromConfig] ─
//   cartBackground                 → Fundo atrás do scroll do sheet (opcional)
//   cartCardBackground             → Fundo dos cards (itens, formulário, coluna direita)
//   cartSectionTitleColor          → Títulos de seção (Itens, Dados, Entrega…)
//   cartPrimaryTextColor           → Texto principal nos blocos
//   cartSecondaryTextColor         → Texto secundário / labels de campo
//   cartMutedTextColor             → Texto discreto (subtítulo variação, qtd)
//   cartInputBackground            → Fundo dos TextFields
//   cartInputTextColor             → Texto digitado
//   cartInputHintColor             → Placeholder
//   cartInputBorderColor           → Borda dos inputs
//   cartSummaryBackground          → Card externo da coluna resumo + pagamento
//   cartSummaryLabelColor          → Rótulos das linhas do resumo (sobrepõe parcialmente
//                                    ao gradiente interno quando passado explicitamente)
//   cartSummaryValueColor          → Valores numéricos das linhas do resumo
//   cartSummaryDiscountColor       → Descontos (cupom) em vermelho/acento
//   cartSummaryTotalColor          → Valor final "Total a pagar"
//   cartPrimaryActionBackground    → Botão primário (ex.: Aplicar cupom)
//   cartPrimaryActionTextColor     → Texto do botão primário
//   cartSecondaryActionBackground  → Fundo ações secundárias (geralmente transparente)
//   cartSecondaryActionTextColor   → Texto/borda secundária (Selecionar cupom, gateway)
//   cartWhatsappButtonBackground   → Botão WhatsApp
//   cartWhatsappButtonTextColor    → Texto/ícone no botão WhatsApp
//   cartPixButtonBorderColor       → Borda do botão PIX
//   cartPixButtonTextColor         → Texto/ícone do botão PIX
//   cartItemDividerColor           → Divisor sob o título "Itens do carrinho"
//   cartRemoveIconColor            → Ícone remover item
//
// ── MODAL PRIMEIRA COMPRA — [CatalogFirstPurchaseCouponStyle.fromUiColors] ───
//   firstPurchaseCouponBackground
//   firstPurchaseCouponTitleColor
//   firstPurchaseCouponTextColor
//   firstPurchaseCouponCodeBackground
//   firstPurchaseCouponCodeTextColor
//   firstPurchaseCouponCopyButtonBackground  → Se transparente, "Copiar" vira outline
//   firstPurchaseCouponCopyButtonTextColor
//   firstPurchaseCouponUseButtonBackground
//   firstPurchaseCouponUseButtonTextColor
//   firstPurchaseCouponBorderColor
//   firstPurchaseCouponShadowColor
//
// Config da oferta (raiz do config, não uiColors): `firstPurchaseCoupon` com
// enabled|ativo, code|codigo, title|titulo, body|texto|mensagem,
// requireClienteSemPedidos|somenteSemPedidos.
//
// ═══════════════════════════════════════════════════════════════════════════

/// Nomes das chaves opcionais em `uiColors` para o bloco de resumo do checkout.
/// Use estes literais ao gravar no Firestore para evitar typos.
abstract final class CatalogCheckoutSummaryColorKeys {
  CatalogCheckoutSummaryColorKeys._();

  static const gradientStart = 'checkoutSummaryGradientStart';
  static const gradientEnd = 'checkoutSummaryGradientEnd';
  static const rowLabel = 'checkoutSummaryRowLabel';
  static const rowValue = 'checkoutSummaryRowValue';
  static const pixDiscount = 'checkoutSummaryPixDiscount';
  static const deduction = 'checkoutSummaryDeduction';
  static const totalLabel = 'checkoutSummaryTotalLabel';
  static const totalBannerBg = 'checkoutSummaryTotalBannerBg';
  static const totalBannerText = 'checkoutSummaryTotalBannerText';
  static const cardShadow = 'checkoutCardShadow';
}
