import 'package:flutter/material.dart';

import '../../../widgets/smart_image.dart';

/// Letreiro promocional; com [marqueeWhenOverflow] rola o texto quando não couber (layout minimalista).
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
  TextStyle _textStyle() => TextStyle(
        color: widget.textColor,
        fontSize: 11.5,
        fontWeight: widget.bold ? FontWeight.w600 : FontWeight.w500,
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final h = widget.height.clamp(28.0, 72.0).toDouble();
    return InkWell(
      onTap: widget.onTap,
      child: Container(
        height: h,
        width: double.infinity,
        color: widget.backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 16, color: widget.textColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final style = _textStyle();
                  final tp = TextPainter(
                    text: TextSpan(text: widget.text, style: style),
                    maxLines: 1,
                    textDirection: Directionality.of(context),
                  )..layout(maxWidth: double.infinity);
                  final iconW = widget.icon != null ? 24.0 : 0.0;
                  final maxW =
                      (constraints.maxWidth - iconW).clamp(40.0, 9999.0);
                  final needMarquee = widget.marqueeWhenOverflow &&
                      tp.width > maxW + 4;

                  if (!needMarquee) {
                    return Center(
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
                  );
                },
              ),
            ),
          ],
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

  const _CatalogPromoMarqueeLine({
    super.key,
    required this.text,
    required this.style,
    required this.textWidth,
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
    final gap = 56.0;
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
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final off = _ctrl.value * segment;
          return Transform.translate(
            offset: Offset(-off, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(widget.text, style: widget.style),
                SizedBox(width: gap),
                Text(widget.text, style: widget.style),
                SizedBox(width: gap),
                Text(widget.text, style: widget.style),
              ],
            ),
          );
        },
      ),
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
    final double imageSize = (((categoryVisuals['imageSize'] as num?)?.toDouble() ?? 82)
            .clamp(44, 120))
        .toDouble();
    final double spacing = (((categoryVisuals['spacing'] as num?)?.toDouble() ?? 14)
            .clamp(4, 24))
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
      return s.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    }

    String imageFor(String cat) {
      final imgs = categoryVisuals['images'];
      final imgsById = categoryVisuals['imagesById'];
      final keyNorm = norm(cat);
      if (imgs is Map) {
        if (imgs[cat] != null) return imgs[cat].toString();
        if (imgs[keyNorm] != null) return imgs[keyNorm].toString();
        for (final e in imgs.entries) {
          if (norm(e.key.toString()) == keyNorm && e.value != null) {
            return e.value.toString();
          }
        }
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
      height: showTitle ? imageSize + 34 : imageSize + 12,
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
                color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 2,
              ),
              color: fallbackBg,
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl.trim().isEmpty
                ? Icon(Icons.category_outlined, color: textColor.withValues(alpha: 0.7))
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
                  fontSize: 10.5,
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

class CatalogMinimalHeroBanner extends StatelessWidget {
  final bool enabled;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback? onTap;
  final String imageUrl;
  final double height;
  final Color textColor;
  final Color buttonColor;
  final Color backgroundColor;
  final double borderRadius;
  final double overlayOpacity;

  const CatalogMinimalHeroBanner({
    super.key,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    this.onTap,
    required this.imageUrl,
    required this.height,
    required this.textColor,
    required this.buttonColor,
    required this.backgroundColor,
    required this.borderRadius,
    this.overlayOpacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final hasImage = imageUrl.trim().isNotEmpty;
    final hasCopy = title.trim().isNotEmpty ||
        subtitle.trim().isNotEmpty ||
        buttonText.trim().isNotEmpty;
    if (!hasImage && !hasCopy) {
      return const SizedBox.shrink();
    }
    final boxH = hasImage
        ? height.clamp(120, 360).toDouble()
        : (hasCopy ? 96.0 : 0.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          borderRadius.clamp(8, 28).toDouble(),
        ),
        child: Stack(
          children: [
            Container(
              height: boxH,
              width: double.infinity,
              decoration: BoxDecoration(
                color: backgroundColor,
                gradient: !hasImage && hasCopy
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          backgroundColor,
                          backgroundColor.withValues(alpha: 0.88),
                        ],
                      )
                    : null,
              ),
              child: hasImage
                  ? SmartImage(src: imageUrl, fit: BoxFit.cover)
                  : null,
            ),
            Container(
              height: boxH,
              width: double.infinity,
              color: Colors.black.withValues(alpha: overlayOpacity.clamp(0.0, 0.8)),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (title.trim().isNotEmpty)
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
                      ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.96),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (buttonText.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: buttonColor,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          buttonText,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
