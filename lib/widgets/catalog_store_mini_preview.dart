import 'package:flutter/material.dart';

/// Cores do rascunho da Loja Config — só para mock visual (sem Firestore/catálogo real).
@immutable
class CatalogStoreMiniPreviewColors {
  const CatalogStoreMiniPreviewColors({
    required this.pageBackground,
    required this.headerBackground,
    required this.headerText,
    required this.headerIcon,
    required this.searchBackground,
    required this.searchHint,
    required this.promoBackground,
    required this.promoForeground,
    required this.heroCardBackground,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.heroButtonBackground,
    required this.heroButtonForeground,
    required this.cardBackground,
    required this.cardShadow,
    required this.cardTitle,
    required this.cardSubtitle,
    required this.priceHighlight,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.primaryButtonBackground,
    required this.primaryButtonForeground,
    required this.outlineButtonBorder,
    required this.outlineButtonForeground,
    required this.cartPanelBackground,
    required this.cartFieldBackground,
    required this.cartLabel,
    required this.cartBody,
    required this.cartTotal,
    required this.footerBackground,
    required this.footerText,
    required this.footerSecondary,
    required this.divider,
  });

  final Color pageBackground;
  final Color headerBackground;
  final Color headerText;
  final Color headerIcon;
  final Color searchBackground;
  final Color searchHint;
  final Color promoBackground;
  final Color promoForeground;
  final Color heroCardBackground;
  final Color heroTitle;
  final Color heroSubtitle;
  final Color heroButtonBackground;
  final Color heroButtonForeground;
  final Color cardBackground;
  final Color cardShadow;
  final Color cardTitle;
  final Color cardSubtitle;
  final Color priceHighlight;
  final Color badgeBackground;
  final Color badgeForeground;
  final Color primaryButtonBackground;
  final Color primaryButtonForeground;
  final Color outlineButtonBorder;
  final Color outlineButtonForeground;
  final Color cartPanelBackground;
  final Color cartFieldBackground;
  final Color cartLabel;
  final Color cartBody;
  final Color cartTotal;
  final Color footerBackground;
  final Color footerText;
  final Color footerSecondary;
  final Color divider;
}

enum CatalogStoreMiniPreviewDensity { compact, comfortable }

/// Miniatura estática do catálogo — apenas cores e hierarquia visual.
class CatalogStoreMiniPreview extends StatelessWidget {
  const CatalogStoreMiniPreview({
    super.key,
    required this.colors,
    this.storeName = 'Sua loja',
    this.density = CatalogStoreMiniPreviewDensity.comfortable,
  });

  final CatalogStoreMiniPreviewColors colors;
  final String storeName;
  final CatalogStoreMiniPreviewDensity density;

  bool get _compact => density == CatalogStoreMiniPreviewDensity.compact;

  double get _rSmall => _compact ? 6 : 8;
  double get _rCard => _compact ? 10 : 12;
  double get _fsTitle => _compact ? 11 : 12;
  double get _fsBody => _compact ? 9.5 : 10.5;
  double get _fsMicro => _compact ? 8.5 : 9.5;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final frameBorder = cs.outlineVariant.withOpacity(0.55);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: frameBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ColoredBox(
          color: colors.pageBackground,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _promoStrip(),
              _header(),
              _hero(),
              Padding(
                padding: EdgeInsets.fromLTRB(_compact ? 8 : 10, _compact ? 8 : 10, _compact ? 8 : 10, 0),
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth >= 280) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _productCard()),
                          SizedBox(width: _compact ? 8 : 10),
                          Expanded(flex: 2, child: _cartBlock()),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _productCard(),
                        SizedBox(height: _compact ? 8 : 10),
                        _cartBlock(),
                      ],
                    );
                  },
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _promoStrip() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: _compact ? 8 : 10, vertical: _compact ? 4 : 5),
      color: colors.promoBackground,
      child: Text(
        'Frete grátis acima de R\$ 199 · use o cupom BEMVINDO',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colors.promoForeground,
          fontSize: _fsMicro,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: colors.headerBackground,
      padding: EdgeInsets.fromLTRB(_compact ? 8 : 10, _compact ? 6 : 8, _compact ? 8 : 10, _compact ? 6 : 8),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: _compact ? 18 : 20, color: colors.headerIcon),
          SizedBox(width: _compact ? 6 : 8),
          Expanded(
            child: Text(
              storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.headerText,
                fontWeight: FontWeight.w700,
                fontSize: _fsTitle,
              ),
            ),
          ),
          Icon(Icons.tune_rounded, size: _compact ? 18 : 20, color: colors.headerIcon),
        ],
      ),
    );
  }

  Widget _searchFake() {
    return Container(
      margin: EdgeInsets.fromLTRB(_compact ? 8 : 10, 0, _compact ? 8 : 10, _compact ? 6 : 8),
      padding: EdgeInsets.symmetric(horizontal: _compact ? 8 : 10, vertical: _compact ? 5 : 6),
      decoration: BoxDecoration(
        color: colors.searchBackground,
        borderRadius: BorderRadius.circular(_rSmall),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: _compact ? 14 : 15, color: colors.headerIcon.withOpacity(0.85)),
          SizedBox(width: _compact ? 6 : 8),
          Expanded(
            child: Text(
              'Buscar produtos…',
              style: TextStyle(color: colors.searchHint, fontSize: _fsMicro),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchFake(),
        Padding(
          padding: EdgeInsets.fromLTRB(_compact ? 8 : 10, 0, _compact ? 8 : 10, _compact ? 8 : 10),
          child: Container(
            padding: EdgeInsets.all(_compact ? 10 : 12),
            decoration: BoxDecoration(
              color: colors.heroCardBackground,
              borderRadius: BorderRadius.circular(_rCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Novidades da semana',
                  style: TextStyle(
                    color: colors.heroTitle,
                    fontSize: _compact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: _compact ? 3 : 4),
                Text(
                  'Peças selecionadas com entrega rápida.',
                  style: TextStyle(color: colors.heroSubtitle, fontSize: _fsBody, height: 1.25),
                ),
                SizedBox(height: _compact ? 8 : 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: _compact ? 10 : 12, vertical: _compact ? 5 : 6),
                    decoration: BoxDecoration(
                      color: colors.heroButtonBackground,
                      borderRadius: BorderRadius.circular(_rSmall),
                    ),
                    child: Text(
                      'Ver coleção',
                      style: TextStyle(
                        color: colors.heroButtonForeground,
                        fontSize: _fsMicro,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _productCard() {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(_rCard),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow.withOpacity(0.35),
            blurRadius: _compact ? 6 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.05,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.cardSubtitle.withOpacity(0.25),
                    colors.priceHighlight.withOpacity(0.12),
                  ],
                ),
              ),
              child: Icon(Icons.checkroom_outlined, size: _compact ? 32 : 36, color: colors.cardSubtitle),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(_compact ? 8 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: _compact ? 5 : 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.badgeBackground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Novo',
                    style: TextStyle(
                      color: colors.badgeForeground,
                      fontSize: _fsMicro,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: _compact ? 4 : 6),
                Text(
                  'Produto exemplo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.cardTitle,
                    fontSize: _fsTitle,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Referência · P',
                  style: TextStyle(color: colors.cardSubtitle, fontSize: _fsMicro),
                ),
                SizedBox(height: _compact ? 6 : 8),
                Text(
                  'R\$ 89,90',
                  style: TextStyle(
                    color: colors.priceHighlight,
                    fontSize: _compact ? 13 : 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: _compact ? 8 : 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(vertical: _compact ? 6 : 7),
                        decoration: BoxDecoration(
                          color: colors.primaryButtonBackground,
                          borderRadius: BorderRadius.circular(_rSmall),
                        ),
                        child: Text(
                          'Comprar',
                          style: TextStyle(
                            color: colors.primaryButtonForeground,
                            fontSize: _fsMicro,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: _compact ? 6 : 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: _compact ? 8 : 10, vertical: _compact ? 6 : 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_rSmall),
                        border: Border.all(color: colors.outlineButtonBorder, width: 1),
                      ),
                      child: Text(
                        'Ver',
                        style: TextStyle(
                          color: colors.outlineButtonForeground,
                          fontSize: _fsMicro,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartBlock() {
    return Container(
      padding: EdgeInsets.all(_compact ? 8 : 10),
      decoration: BoxDecoration(
        color: colors.cartPanelBackground,
        borderRadius: BorderRadius.circular(_rCard),
        border: Border.all(color: colors.divider.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Resumo',
            style: TextStyle(color: colors.cartLabel, fontSize: _fsTitle, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: _compact ? 6 : 8),
          Container(
            padding: EdgeInsets.all(_compact ? 6 : 8),
            decoration: BoxDecoration(
              color: colors.cartFieldBackground,
              borderRadius: BorderRadius.circular(_rSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1 item', style: TextStyle(color: colors.cartBody, fontSize: _fsMicro)),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal', style: TextStyle(color: colors.cartBody, fontSize: _fsMicro)),
                    Text('R\$ 89,90', style: TextStyle(color: colors.cartBody, fontSize: _fsMicro)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: _compact ? 8 : 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(color: colors.cartLabel, fontSize: _fsBody, fontWeight: FontWeight.w700)),
              Text(
                'R\$ 89,90',
                style: TextStyle(
                  color: colors.cartTotal,
                  fontSize: _compact ? 12 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: _compact ? 8 : 10),
          Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(vertical: _compact ? 7 : 8),
            decoration: BoxDecoration(
              color: colors.primaryButtonBackground,
              borderRadius: BorderRadius.circular(_rSmall),
            ),
            child: Text(
              'Ir para pagamento',
              style: TextStyle(
                color: colors.primaryButtonForeground,
                fontSize: _fsMicro,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      margin: EdgeInsets.only(top: _compact ? 8 : 10),
      padding: EdgeInsets.fromLTRB(_compact ? 10 : 12, _compact ? 10 : 12, _compact ? 10 : 12, _compact ? 10 : 12),
      color: colors.footerBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Institucional · Ajuda · Contato',
            style: TextStyle(color: colors.footerText, fontSize: _fsMicro, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '© 2026 · preview visual',
            style: TextStyle(color: colors.footerSecondary, fontSize: _fsMicro * 0.95),
          ),
        ],
      ),
    );
  }
}
