// lib/screens/public_catalog/widgets/catalog_products_grid_sliver.dart
// Sliver do grid principal de produtos (extraído de public_catalog_screen.dart). UI only.

import 'package:flutter/material.dart';

import '../../../utils/safe_parse.dart';
import 'product_card.dart';

/// Retorna o Sliver do grid de produtos (SliverPadding + SliverGrid + SliverChildBuilderDelegate).
/// Paginação e lista (listaPaginated) continuam no chamador.
/// [isDesktop] true = usa [desktopCols], senão usa [mobileCols] (config da aba Layout no Loja Config).
/// [todosProdutosParaCombo] lista completa do catálogo para resolver itens do kit no modal (por id/nome/slug). Se null, usa [products].
Widget buildCatalogProductsGridSliver({
  required List<Map<String, dynamic>> products,
  /// Lista completa do catálogo (antes de filtro/página) para o modal "Configurar kit" encontrar cada item do combo.
  List<Map<String, dynamic>>? todosProdutosParaCombo,
  required String lojaId,
  required void Function(Map<String, dynamic>) onAdd,
  void Function(String productId)? onProductViewed,
  void Function(String productId)? onToggleFavorito,
  VoidCallback? onAbrirLoginParaFavorito,
  VoidCallback? onAbrirCarrinho,
  String? clienteId,
  List<String> favoritosIds = const [],
  required bool mostrarEstoqueNoCatalogo,
  required bool mostrarQuantidadeNoCatalogo,
  required double cardBorderRadius,
  required bool cardShowShadow,
  String? prazoEntregaTexto,
  double? jurosParcelamento,
  required int maxParcelas,
  int imageCacheWidth = 360,
  int imageCacheHeight = 480,
  double childAspectRatio = 0.38,
  double mainAxisSpacing = 16,
  double crossAxisSpacing = 16,
  EdgeInsets padding = const EdgeInsets.fromLTRB(12, 0, 12, 24),
  bool isDesktop = false,
  int desktopCols = 4,
  int mobileCols = 2,
  /// URL do catálogo para compartilhar (pode incluir ref/indicacao). Se null, o card usa padrão por lojaId.
  String? catalogShareUrl,
  /// Layout minimalista: card abre tela de detalhe ao toque, sem botão Ver, tipografia reduzida.
  bool useMinimalLayout = false,
}) {
  final listaParaCombo = todosProdutosParaCombo ?? products;
  final cols = isDesktop ? desktopCols : mobileCols;
  final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: cols,
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
    childAspectRatio: childAspectRatio,
  );
  return SliverPadding(
    padding: padding,
    sliver: SliverGrid(
      gridDelegate: gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final p = products[index];
          return RepaintBoundary(
            child: PublicCatalogProductCard(
              produto: p,
              lojaId: lojaId,
              onAdd: onAdd,
              onProductViewed: onProductViewed,
              onToggleFavorito: clienteId != null
                  ? () => onToggleFavorito?.call(safeStr(p['id']))
                  : onAbrirLoginParaFavorito,
              onAbrirCarrinho: onAbrirCarrinho,
              clienteId: clienteId,
              favoritosIds: favoritosIds,
              todosProdutos: listaParaCombo,
              mostrarEstoqueNoCatalogo: mostrarEstoqueNoCatalogo,
              mostrarQuantidadeNoCatalogo: mostrarQuantidadeNoCatalogo,
              cardBorderRadius: cardBorderRadius,
              cardShowShadow: cardShowShadow,
              prazoEntregaTexto: prazoEntregaTexto,
              jurosParcelamento: jurosParcelamento,
              maxParcelas: maxParcelas,
              imageCacheWidth: imageCacheWidth,
              imageCacheHeight: imageCacheHeight,
              catalogShareUrl: catalogShareUrl,
              minimalLayout: useMinimalLayout,
            ),
          );
        },
        childCount: products.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    ),
  );
}
