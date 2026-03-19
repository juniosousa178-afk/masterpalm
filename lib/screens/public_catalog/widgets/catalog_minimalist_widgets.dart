import 'package:flutter/material.dart';

import '../../../widgets/smart_image.dart';

class CatalogPromoBar extends StatelessWidget {
  final bool enabled;
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  final double height;
  final TextAlign textAlign;
  final bool bold;
  final VoidCallback? onTap;

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
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || text.trim().isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height.clamp(28, 72),
        width: double.infinity,
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                text,
                textAlign: textAlign,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
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
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          borderRadius.clamp(8, 28).toDouble(),
        ),
        child: Stack(
          children: [
            Container(
              height: height.clamp(120, 360).toDouble(),
              width: double.infinity,
              color: backgroundColor,
              child: imageUrl.trim().isEmpty
                  ? null
                  : SmartImage(src: imageUrl, fit: BoxFit.cover),
            ),
            Container(
              height: height.clamp(120, 360).toDouble(),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
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
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (buttonText.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(backgroundColor: buttonColor),
                        child: Text(buttonText),
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
