import 'package:flutter/material.dart';

import '../theme/catalog_visual_palette_presets.dart';

/// Lista horizontal de paletas prontas (só dispara confirmação no callback).
class CatalogVisualPalettePresetsPanel extends StatelessWidget {
  const CatalogVisualPalettePresetsPanel({
    super.key,
    required this.presets,
    required this.onApplyRequested,
  });

  final List<CatalogVisualPalettePreset> presets;
  final ValueChanged<CatalogVisualPalettePreset> onApplyRequested;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxWidth >= 600 ? 198.0 : 220.0;
        return SizedBox(
          height: h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final p = presets[i];
              return _PalettePresetCard(
                preset: p,
                colorScheme: cs,
                textTheme: tt,
                onApply: () => onApplyRequested(p),
              );
            },
          ),
        );
      },
    );
  }
}

class _PalettePresetCard extends StatelessWidget {
  const _PalettePresetCard({
    required this.preset,
    required this.colorScheme,
    required this.textTheme,
    required this.onApply,
  });

  final CatalogVisualPalettePreset preset;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final sw = preset.colors.previewSwatches;

    return SizedBox(
      width: 168,
      child: Material(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var j = 0; j < sw.length; j++)
                    Padding(
                      padding: EdgeInsets.only(right: j < sw.length - 1 ? 5 : 0),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: sw[j],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.25),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preset.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.2,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  preset.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.25,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.9),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Aplicar paleta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
