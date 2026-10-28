// Shell mínimo do catálogo enquanto config/produtos carregam (handoff HTML ~4s).

import 'package:flutter/material.dart';

import 'catalog_skeleton_grid.dart';
import 'catalog_unified_loading.dart';

/// Cabeçalho + skeleton — conteúdo útil por trás do loader HTML antes da config.
///
/// Sem nome da loja: o nome comercial só existe na config (ainda a carregar) e o slug
/// da URL não é nome de exibição.
class CatalogEarlyShellView extends StatefulWidget {
  const CatalogEarlyShellView({
    super.key,
    this.themeData,
    this.onFirstFrame,
  });

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
