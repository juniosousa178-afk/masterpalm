import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/smart_image.dart' show SmartImage;
import '../catalog_helpers.dart';
import 'public_catalog_banner_image.dart';

/// Letreiro promocional; com [marqueeWhenOverflow] mantém rolagem contínua.
class CatalogPromoBar extends StatefulWidget {
  final bool enabled;
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  final double height;
  final TextAlign textAlign;
  final bool bold;
  final VoidCallback? onTap;
  final bool marqueeWhenOverflow;

  const CatalogPromoBar({
    super.key,
    required this.enabled,
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
    required this.height,
    required this.textAlign,
    required this.bold,
    this.onTap,
    this.marqueeWhenOverflow = false,
  });

  @override
  State<CatalogPromoBar> createState() => _CatalogPromoBarState();
}

class _CatalogPromoBarState extends State<CatalogPromoBar> {
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final scaler = MediaQuery.textScalerOf(context);
    const baseFs = 11.5;
    final baseH = widget.height.clamp(28.0, 72.0).toDouble();
    final rawFs = math.min(scaler.scale(baseFs), baseH * 0.45);
    final minH = rawFs * 2.65 + 6;
    final h = math.max(baseH, minH).clamp(28.0, 72.0).toDouble();

    final fontSize = math.min(scaler.scale(baseFs), h * 0.45);
    TextStyle textStyle() => TextStyle(
          color: widget.textColor,
          fontSize: fontSize,
          fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w500,
          height: 1.0,
        );

    final double leading = widget.icon != null ? 44.0 : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: ClipRect(
          child: SizedBox(
            height: h,
            width: double.infinity,
            child: ColoredBox(
              color: widget.backgroundColor,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (widget.icon != null)
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      width: 28,
                      child: Center(
                        child: Icon(
                          widget.icon,
                          size: 16,
                          color: widget.textColor,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12 + leading,
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final style = textStyle();
                        final tp = TextPainter(
                          text: TextSpan(text: widget.text, style: style),
                          maxLines: 1,
                          textDirection: Directionality.of(context),
                        )..layout(maxWidth: double.infinity);
                        final useMarquee = widget.marqueeWhenOverflow;

                        if (!useMarquee) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              widget.text,
                              textAlign: widget.textAlign,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          );
                        }

                        return _CatalogPromoMarqueeLine(
                          key: ValueKey(widget.text),
                          text: widget.text,
                          style: style,
                          textWidth: tp.width,
                          barHeight: h,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rolagem horizontal contínua — controller criado em [initState], nunca no [build].
class _CatalogPromoMarqueeLine extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double textWidth;
  final double barHeight;

  const _CatalogPromoMarqueeLine({
    super.key,
    required this.text,
    required this.style,
    required this.textWidth,
    required this.barHeight,
  });

  @override
  State<_CatalogPromoMarqueeLine> createState() =>
      _CatalogPromoMarqueeLineState();
}

class _CatalogPromoMarqueeLineState extends State<_CatalogPromoMarqueeLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    const gap = 56.0;
    final segment = widget.textWidth + gap;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (segment * 42).round().clamp(12000, 52000),
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gap = 56.0;
    final segment = widget.textWidth + gap;
    // Uma linha só: evita altura intrínseca > [barHeight] (overflow ~20px típico).
    final fs = math.min(
      widget.style.fontSize ?? 11.5,
      widget.barHeight * 0.42,
    );
    final lineStyle = widget.style.copyWith(height: 1.0, fontSize: fs);
    final strut = StrutStyle(
      fontSize: fs,
      height: 1.0,
      forceStrutHeight: true,
      leadingDistribution: TextLeadingDistribution.even,
    );
    // O Row do letreiro é muito mais largo que a tela; sem OverflowBox o Flex
    // do pai recebe largura intrínseca gigante (~mil px) e estoura à direita.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: widget.barHeight,
          width: constraints.maxWidth,
          child: ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              minWidth: 0,
              minHeight: widget.barHeight,
              maxHeight: widget.barHeight,
              alignment: Alignment.centerLeft,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final off = _ctrl.value * segment;
                  // Text.rich (sem Row): uma única linha, altura estável; evita overflow vertical.
                  final rich = Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: widget.text, style: lineStyle),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: SizedBox(width: gap, height: fs),
                        ),
                        TextSpan(text: widget.text, style: lineStyle),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: SizedBox(width: gap, height: fs),
                        ),
                        TextSpan(text: widget.text, style: lineStyle),
                      ],
                    ),
                    maxLines: 1,
                    strutStyle: strut,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  );
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: Offset(-off, 0),
                      child: rich,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class CatalogMinimalCategoryImageStrip extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final Map<String, dynamic> categoryVisuals;
  final Map<String, Set<String>> categoryAliasesByName;
  final void Function(String category) onSelect;
  final VoidCallback onClear;
  final Color textColor;
  final Color fallbackBg;

  const CatalogMinimalCategoryImageStrip({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.categoryVisuals,
    required this.categoryAliasesByName,
    required this.onSelect,
    required this.onClear,
    required this.textColor,
    required this.fallbackBg,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final double imageSize =
        (((categoryVisuals['imageSize'] as num?)?.toDouble() ?? 82)
                .clamp(44, 120))
            .toDouble();
    final double spacing =
        (((categoryVisuals['spacing'] as num?)?.toDouble() ?? 14).clamp(4, 24))
            .toDouble();
    final showTitle = (categoryVisuals['showTitle'] as bool?) ?? true;
    final shape = (categoryVisuals['shape'] ?? 'circle').toString();

    BorderRadius radiusForShape() {
      if (shape == 'square') return BorderRadius.circular(0);
      if (shape == 'rounded') return BorderRadius.circular(16);
      return BorderRadius.circular(imageSize / 2);
    }

    String norm(String v) {
      final s = v
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[àáâãä]'), 'a')
          .replaceAll(RegExp(r'[èéêë]'), 'e')
          .replaceAll(RegExp(r'[ìíîï]'), 'i')
          .replaceAll(RegExp(r'[òóôõö]'), 'o')
          .replaceAll(RegExp(r'[ùúûü]'), 'u')
          .replaceAll(RegExp(r'ç'), 'c');
      return s
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
    }

    String imageFor(String cat) {
      final imgs = categoryVisuals['images'];
      final imgsById = categoryVisuals['imagesById'];
      final imgsByNorm = categoryVisuals['imagesByNameNorm'];
      final keyNorm = norm(cat);
      if (imgs is Map) {
        if (imgs[cat] != null) return imgs[cat].toString();
        if (imgs[keyNorm] != null) return imgs[keyNorm].toString();
        if (imgs['name:$keyNorm'] != null) {
          return imgs['name:$keyNorm'].toString();
        }
      }
      if (imgsByNorm is Map) {
        if (imgsByNorm[keyNorm] != null) return imgsByNorm[keyNorm].toString();
      }
      if (imgsById is Map) {
        final aliases = categoryAliasesByName[cat] ?? const <String>{};
        for (final alias in aliases) {
          if (imgsById[alias] != null) return imgsById[alias].toString();
        }
      }
      return '';
    }

    return SizedBox(
      height: showTitle ? imageSize + 38 : imageSize + 12,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          if (selectedCategory != null)
            Padding(
              padding: EdgeInsets.only(right: spacing.toDouble()),
              child: _CategoryItem(
                label: 'Todos',
                imageUrl: '',
                textColor: textColor,
                imageSize: imageSize,
                borderRadius: radiusForShape(),
                showTitle: showTitle,
                fallbackBg: fallbackBg,
                selected: false,
                onTap: onClear,
              ),
            ),
          ...categories.map(
            (cat) => Padding(
              padding: EdgeInsets.only(right: spacing.toDouble()),
              child: _CategoryItem(
                label: cat,
                imageUrl: imageFor(cat),
                textColor: textColor,
                imageSize: imageSize,
                borderRadius: radiusForShape(),
                showTitle: showTitle,
                fallbackBg: fallbackBg,
                selected: selectedCategory == cat,
                onTap: () => onSelect(cat),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  final String label;
  final String imageUrl;
  final Color textColor;
  final double imageSize;
  final BorderRadius borderRadius;
  final bool showTitle;
  final Color fallbackBg;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.label,
    required this.imageUrl,
    required this.textColor,
    required this.imageSize,
    required this.borderRadius,
    required this.showTitle,
    required this.fallbackBg,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
              color: fallbackBg,
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl.trim().isEmpty
                ? Icon(Icons.category_outlined,
                    color: textColor.withOpacity(0.7))
                : SmartImage(src: imageUrl, fit: BoxFit.cover),
          ),
          if (showTitle) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: imageSize + 8,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Chips de subcategoria abaixo da faixa de categorias (layout minimalista).
class CatalogMinimalSubcategoryStrip extends StatelessWidget {
  final List<String> subcategories;
  final String? selectedSubcategory;
  final Color primaryColor;
  final Color textColor;
  final Color surfaceColor;
  final VoidCallback onSelectAll;
  final void Function(String sub) onSelectSub;

  const CatalogMinimalSubcategoryStrip({
    super.key,
    required this.subcategories,
    required this.selectedSubcategory,
    required this.primaryColor,
    required this.textColor,
    required this.surfaceColor,
    required this.onSelectAll,
    required this.onSelectSub,
  });

  static Color _onPrimary(Color bg) =>
      bg.computeLuminance() > 0.55 ? const Color(0xFF1A1A1A) : Colors.white;

  @override
  Widget build(BuildContext context) {
    if (subcategories.isEmpty) return const SizedBox.shrink();

    final onPrimary = _onPrimary(primaryColor);
    final borderIdle = textColor.withOpacity(0.18);
    final labelMuted = textColor.withOpacity(0.72);

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: selected ? primaryColor : surfaceColor,
                border: Border.all(
                  color: selected ? primaryColor : borderIdle,
                  width: selected ? 0 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? onPrimary : textColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: labelMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  'Subcategorias',
                  style: TextStyle(
                    color: labelMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              physics: const BouncingScrollPhysics(),
              children: [
                chip(
                  label: 'Todas',
                  selected: selectedSubcategory == null,
                  onTap: onSelectAll,
                ),
                ...subcategories.map(
                  (sub) => chip(
                    label: sub,
                    selected: selectedSubcategory == sub,
                    onTap: () => onSelectSub(sub),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogMinimalHeroBanner extends StatelessWidget {
  final bool enabled;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback? onTap;
  final String imageUrl;
  final String? resolvedLojaId;
  final double height;

  /// Cor do card/fundo do banner (atrás da imagem ou gradiente sem imagem).
  final Color backgroundColor;

  /// Raio do card do banner.
  final double borderRadius;
  final double overlayOpacity;

  final Color titleColor;
  final double titleFontSize;
  final FontWeight titleFontWeight;
  final String titleLetterCase;

  final Color subtitleColor;
  final double subtitleFontSize;
  final FontWeight subtitleFontWeight;
  final String subtitleLetterCase;

  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final double buttonFontSize;
  final FontWeight buttonFontWeight;
  final double buttonBorderRadius;
  final String buttonLetterCase;

  const CatalogMinimalHeroBanner({
    super.key,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    this.onTap,
    required this.imageUrl,
    this.resolvedLojaId,
    required this.height,
    required this.backgroundColor,
    required this.borderRadius,
    this.overlayOpacity = 0.18,
    required this.titleColor,
    this.titleFontSize = 17,
    this.titleFontWeight = FontWeight.w600,
    this.titleLetterCase = 'none',
    required this.subtitleColor,
    this.subtitleFontSize = 13,
    this.subtitleFontWeight = FontWeight.w400,
    this.subtitleLetterCase = 'none',
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    this.buttonFontSize = 13,
    this.buttonFontWeight = FontWeight.w600,
    this.buttonBorderRadius = 8,
    this.buttonLetterCase = 'none',
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final screenSize = MediaQuery.sizeOf(context);
    final screenW = screenSize.width;
    final hasImage = imageUrl.trim().isNotEmpty;
    final hasCopy = title.trim().isNotEmpty ||
        subtitle.trim().isNotEmpty ||
        buttonText.trim().isNotEmpty;
    if (!hasImage && !hasCopy) {
      return const SizedBox.shrink();
    }
    final fallbackAspect =
        height > 0 ? (screenW / height).clamp(0.45, 3.2).toDouble() : (16 / 9);
    final titleDisplay = applyHeroLetterCase(title.trim(), titleLetterCase);
    final subtitleDisplay =
        applyHeroLetterCase(subtitle.trim(), subtitleLetterCase);
    final buttonDisplay =
        applyHeroLetterCase(buttonText.trim(), buttonLetterCase);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final isWide = maxW >= 900;
        final double cardMaxW =
            isWide ? math.min(960.0, maxW - 24.0) : maxW - 24.0;
        final double overlayBlend = isWide && hasImage
            ? (overlayOpacity + 0.06).clamp(0.0, 0.55)
            : overlayOpacity.clamp(0.0, 0.8);

        final inner = ClipRRect(
          borderRadius: BorderRadius.circular(
            borderRadius.clamp(8, 36).toDouble(),
          ),
          child: PublicCatalogBannerImage(
            imageUrl: imageUrl,
            resolvedLojaId: resolvedLojaId,
            fallbackAspectRatio: fallbackAspect,
            backgroundColor: backgroundColor,
            // Não trocar para BoxFit.cover no banner: cover recorta e aplica zoom.
            overlay: Container(
              color: Colors.black.withOpacity(overlayBlend),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (titleDisplay.isNotEmpty)
                      Text(
                        titleDisplay,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: titleFontSize.clamp(10, 40),
                          fontWeight: titleFontWeight,
                        ),
                      ),
                    if (subtitleDisplay.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitleDisplay,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: subtitleFontSize.clamp(9, 32),
                          fontWeight: subtitleFontWeight,
                        ),
                      ),
                    ],
                    if (buttonDisplay.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: buttonBackgroundColor,
                          foregroundColor: buttonTextColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              buttonBorderRadius.clamp(0, 28),
                            ),
                          ),
                        ),
                        child: Text(
                          buttonDisplay,
                          style: TextStyle(
                            fontSize: buttonFontSize.clamp(9, 24),
                            fontWeight: buttonFontWeight,
                            color: buttonTextColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );

        final wrapped = onTap == null
            ? inner
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  child: inner,
                ),
              );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isWide ? 16 : 12,
            8,
            isWide ? 16 : 12,
            12,
          ),
          child: isWide
              ? Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxW),
                    child: wrapped,
                  ),
                )
              : wrapped,
        );
      },
    );
  }
}
