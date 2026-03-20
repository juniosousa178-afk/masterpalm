// lib/screens/public_catalog/widgets/catalog_recent_section_sliver.dart
// Sliver da seção "Vistos recentemente" (extraído de public_catalog_screen.dart). UI only.
// A lista de produtos recentes deve ser calculada pelo chamador (algoritmo de recentes não alterado).

import 'package:flutter/material.dart';

import '../../../utils/safe_parse.dart';
import '../catalog_product_card_size.dart';
import 'catalog_minimal_best_sellers.dart';
import 'product_card.dart';

/// Retorna o Sliver da seção "Vistos recentemente" (SliverToBoxAdapter + Column + ListView horizontal).
/// [recentProducts] deve ser a lista já filtrada/ordenada pelo chamador (ex.: _recentIds + prodMap).
Widget buildCatalogRecentSectionSliver({
  required List<Map<String, dynamic>> recentProducts,
  /// Lista completa de produtos do catálogo (para combos na seção recentes).
  List<Map<String, dynamic>>? todosProdutos,
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
  required Color textColor,
  bool useMinimalLayout = false,
  Color? cardColor,
  Color? priceColor,
  String? catalogShareUrl,
  String? nomeLoja,
  String? contatoWhatsapp,
  String? politicaFrete,
  String productCardSize = CatalogProductCardSize.medium,
}) {
  if (recentProducts.isEmpty) {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  if (useMinimalLayout) {
    return SliverToBoxAdapter(
      child: CatalogMinimalBestSellersSection(
        title: 'Visto por último',
        productCardSize: productCardSize,
        products: recentProducts,
        lojaId: lojaId,
        todosProdutos: todosProdutos ?? recentProducts,
        onAdd: onAdd,
        onAbrirCarrinho: onAbrirCarrinho,
        catalogShareUrl: catalogShareUrl,
        textColor: textColor,
        cardColor: cardColor ?? ThemeData.fallback().cardColor,
        priceColor: priceColor ?? textColor,
        prazoEntregaTexto: prazoEntregaTexto,
        nomeLoja: nomeLoja,
        contatoWhatsapp: contatoWhatsapp,
        politicaFrete: politicaFrete,
        onProductViewed: onProductViewed,
      ),
    );
  }

  return SliverToBoxAdapter(
    child: LayoutBuilder(
      builder: (context, constraints) {
        const paddingHorizontal = 12.0;
        const gapBetweenCards = 8.0;
        final screenWidth = constraints.maxWidth;
        final cardWidth =
            (screenWidth - paddingHorizontal * 2 - gapBetweenCards * 2) / 3;
        final size = CatalogProductCardSize.normalize(productCardSize);
        final is360 = screenWidth <= 360;
        final is390 = screenWidth > 360 && screenWidth <= 390;
        final recentHeight = size == CatalogProductCardSize.large
            ? (is360 ? 366.0 : (is390 ? 372.0 : 380.0))
            : size == CatalogProductCardSize.small
                ? (is360 ? 334.0 : (is390 ? 340.0 : 344.0))
                : (is360 ? 352.0 : (is390 ? 356.0 : 360.0));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Text(
                'Vistos recentemente',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: recentHeight,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
                itemCount: recentProducts.length,
                itemBuilder: (context, index) {
                  final p = recentProducts[index];
                  return SizedBox(
                    width: cardWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: gapBetweenCards),
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
                        todosProdutos: todosProdutos ?? recentProducts,
                        mostrarEstoqueNoCatalogo: mostrarEstoqueNoCatalogo,
                        mostrarQuantidadeNoCatalogo: mostrarQuantidadeNoCatalogo,
                        cardBorderRadius: cardBorderRadius,
                        cardShowShadow: cardShowShadow,
                        prazoEntregaTexto: prazoEntregaTexto,
                        jurosParcelamento: jurosParcelamento,
                        maxParcelas: maxParcelas,
                        compact: true,
                        minimalLayout: useMinimalLayout,
                        productCardSize: productCardSize,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    ),
  );
}
