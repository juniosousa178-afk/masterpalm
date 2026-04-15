import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/catalog_color_hex.dart';
import 'catalog_color_field_editor.dart';

void _feedbackHexCopied(BuildContext context, String hex) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text('HEX copiado'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
      margin: EdgeInsets.all(12),
    ),
  );
}

void _showPaletteColorDetail(BuildContext context, CatalogColorSuggestion s) {
  final hex = formatCatalogHexRgb(s.color);
  final uses = s.originLabel
      .split('·')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final cs = Theme.of(context).colorScheme;

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cor na paleta',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outline.withOpacity(0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: s.color.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                hex,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: hex));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _feedbackHexCopied(context, hex);
                  }
                },
                icon: const Icon(Icons.content_copy, size: 20),
                label: const Text('Copiar HEX'),
              ),
              const SizedBox(height: 20),
              Text(
                'Onde esta cor é usada',
                style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final u in uses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.circle, size: 6, color: cs.primary.withOpacity(0.8)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(u, style: Theme.of(ctx).textTheme.bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Para aplicar em um campo, abra o editor de cor desejado e use a mesma tonalidade nas sugestões ou cole o HEX.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Painel de referência: paleta atual do catálogo (visual + copiar + detalhes).
class CatalogStorePaletteCard extends StatelessWidget {
  const CatalogStorePaletteCard({
    super.key,
    required this.entries,
    this.title = 'Paleta da Loja',
    this.subtitle =
        'Referência das cores do rascunho. Toque para ver onde cada cor aparece; use o ícone para copiar o HEX.',
    /// No hub: mostra só uma faixa com as primeiras cores e abre o restante em sheet (mais leve).
    this.compactStrip = false,
  });

  final List<CatalogColorSuggestion> entries;
  final String title;
  final String subtitle;
  final bool compactStrip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    const accent = Color(0xFFC9A4A8);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.palette_outlined, size: 22, color: cs.onSurface.withOpacity(0.85)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withOpacity(0.92),
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Text(
                'Nenhuma cor agregada ainda.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              )
            else if (compactStrip && entries.length > 8)
              _CompactPaletteStrip(
                entries: entries,
                title: title,
                subtitle: subtitle,
              )
            else
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final cell = w >= 520 ? 108.0 : (w >= 360 ? 96.0 : 88.0);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      for (final e in entries)
                        SizedBox(
                          width: cell,
                          child: _PaletteSwatch(suggestion: e),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactPaletteStrip extends StatelessWidget {
  const _CompactPaletteStrip({
    required this.entries,
    required this.title,
    required this.subtitle,
  });

  final List<CatalogColorSuggestion> entries;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final preview = entries.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumo rápido (${entries.length} cores distintas)',
          style: tt.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withOpacity(0.88),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final e in preview)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () => _showPaletteColorDetail(context, e),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: e.color,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outline.withOpacity(0.35)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatCatalogHexRgb(e.color),
                          style: tt.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                builder: (ctx) => DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.72,
                  minChildSize: 0.45,
                  maxChildSize: 0.92,
                  builder: (ctx, scroll) => SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.only(bottom: 24),
                    child: CatalogStorePaletteCard(
                      entries: entries,
                      title: title,
                      subtitle: subtitle,
                      compactStrip: false,
                    ),
                  ),
                ),
              );
            },
            icon: Icon(Icons.palette_outlined, size: 20, color: cs.primary.withOpacity(0.9)),
            label: Text('Ver paleta completa (${entries.length} cores)'),
          ),
        ),
      ],
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.suggestion});

  final CatalogColorSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hex = formatCatalogHexRgb(suggestion.color);

    return Material(
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showPaletteColorDetail(context, suggestion),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: suggestion.color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outline.withOpacity(0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: suggestion.color.withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      suggestion.originLabel,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.88),
                        height: 1.25,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hex,
                      style: tt.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copiar HEX',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.content_copy_outlined, size: 18, color: cs.onSurfaceVariant.withOpacity(0.85)),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: hex));
              if (!context.mounted) return;
              _feedbackHexCopied(context, hex);
            },
          ),
        ],
      ),
    );
  }
}
