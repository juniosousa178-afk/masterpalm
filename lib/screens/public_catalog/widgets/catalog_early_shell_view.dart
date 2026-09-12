// Shell mínimo do catálogo enquanto config/produtos carregam (handoff HTML ~4s).

import 'package:flutter/material.dart';

import '../../../catalog/catalog_loader_name_resolution.dart';
import '../../../core/catalog_loading_store_name.dart';
import 'catalog_skeleton_grid.dart';
import 'catalog_unified_loading.dart';

/// Nome legível a partir do slug da URL (sem hardcode de loja).
/// Preferir [CatalogLoadingStoreName.resolveVisiblePillLabel] na pill de loading.
String catalogStoreLabelFromSlug(String slug) {
  return CatalogLoadingStoreName.slugToStoreNameFallback(slug);
}

/// Cabeçalho + skeleton — conteúdo útil por trás do loader HTML antes da config.
///
/// A pill usa nome comercial quando disponível. Em `unresolved`/`loading` sem
/// comercial a pill fica oculta (sem flash de slug). Fallback de slug só após
/// `resolvedWithoutName` / `errorFallback`.
/// Em Web este é o widget LIVE de "Preparando sua loja..." após o handoff HTML.
class CatalogEarlyShellView extends StatefulWidget {
  const CatalogEarlyShellView({
    super.key,
    required this.storeSlug,
    this.commercialName,
    this.namePhase = CatalogLoaderNamePhase.loading,
    this.themeData,
    this.onFirstFrame,
  });

  final String storeSlug;

  /// Nome comercial já resolvido (ou preview de cache HTML). Null → sem comercial.
  final String? commercialName;

  /// Fase da resolução early-name. Controla se o fallback de slug é permitido.
  final CatalogLoaderNamePhase namePhase;
  final ThemeData? themeData;
  final VoidCallback? onFirstFrame;

  @override
  State<CatalogEarlyShellView> createState() => _CatalogEarlyShellViewState();
}

class _CatalogEarlyShellViewState extends State<CatalogEarlyShellView> {
  bool _firstFrameNotified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _firstFrameNotified) return;
      _firstFrameNotified = true;
      widget.onFirstFrame?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeData ?? Theme.of(context);
    final label = CatalogLoadingStoreName.resolveVisiblePillLabel(
      allowSlugFallback:
          catalogLoaderNamePhaseAllowsSlugFallback(widget.namePhase),
      commercialName: widget.commercialName,
      slug: widget.storeSlug,
    );
    final bg = theme.scaffoldBackgroundColor;
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null)
                    Container(
                      key: const Key('catalog_loading_store_pill'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9A4E6B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Semantics(
                        // Prova da pill Flutter VISÍVEL (não badge HTML oculto).
                        label: 'catalog_loading_store_pill',
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (label != null) const SizedBox(height: 16),
                  Text(
                    CatalogUnifiedLoadingCopy.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    CatalogUnifiedLoadingCopy.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withOpacity(0.72),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const CatalogSkeletonGrid(
            isDesktop: false,
            mobileCols: 2,
            childAspectRatio: 0.38,
          ),
        ],
      ),
    );
  }
}
