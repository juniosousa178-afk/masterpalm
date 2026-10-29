// Shell mínimo do catálogo enquanto config/produtos carregam (handoff HTML ~4s).

import 'package:flutter/material.dart';

import 'catalog_skeleton_grid.dart';
import 'catalog_unified_loading.dart';

/// Cabeçalho + skeleton — conteúdo útil por trás do loader HTML antes da config.
///
/// [storeName] é o "Nome da loja" publicado (`config/config.nome`) já lido para esta loja;
/// sem ele o shell fica neutro — o slug da URL não é nome de exibição.
class CatalogEarlyShellView extends StatefulWidget {
  const CatalogEarlyShellView({
    super.key,
    this.storeName,
    this.themeData,
    this.onFirstFrame,
  });

  final String? storeName;
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
    final storeName = (widget.storeName ?? '').trim();

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
                  if (storeName.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9A4E6B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        storeName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
