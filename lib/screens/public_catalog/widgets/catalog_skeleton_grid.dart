// lib/screens/public_catalog/widgets/catalog_skeleton_grid.dart
// Skeleton de grid de produtos durante loading (extra�do de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// Sliver skeleton exibido enquanto carrega lista de produtos.
/// Usa [desktopCols] / [mobileCols] conforme [isDesktop] (config da aba Layout no Loja Config).
class CatalogSkeletonGrid extends StatelessWidget {
  final bool isDesktop;
  final int desktopCols;
  final int mobileCols;

  const CatalogSkeletonGrid({
    super.key,
    this.isDesktop = false,
    this.desktopCols = 4,
    this.mobileCols = 2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.brightness == Brightness.dark
        ? Colors.grey.shade800
        : Colors.grey.shade300;
    final cols = isDesktop ? desktopCols : mobileCols;
    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.38,
    );
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      sliver: SliverGrid(
        gridDelegate: gridDelegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => Container(
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: base.withValues(alpha:0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Container(
                  height: 14,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  decoration: BoxDecoration(
                    color: base.withValues(alpha:0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 18,
                  width: 80,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: base.withValues(alpha:0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          childCount: 8,
        ),
      ),
    );
  }
}

