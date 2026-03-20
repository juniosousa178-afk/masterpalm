// lib/screens/public_catalog/widgets/catalog_premium_section_sliver.dart
// Sliver reutilizável para seções horizontais premium (Novidades, Em promoção).
// UI only; a lista de produtos deve ser filtrada/ordenada pelo chamador.
// Sem novas queries; usa apenas produtos já carregados.

import 'package:flutter/material.dart';

import '../../../utils/safe_parse.dart';
import 'product_card.dart';

/// Retorna o Sliver de uma seção horizontal com título (ex.: Novidades, Em promoção).
/// [products] deve ser a lista já filtrada pelo chamador. Se vazia, retorna SliverToBoxAdapter(child: SizedBox.shrink()).
Widget buildCatalogPremiumSectionSliver({
  required String title,
  required List<Map<String, dynamic>> products,
  List<Map<String, dynamic>>• todosProdutos,
  required String lojaId,
  required void Function(Map<String, dynamic>) onAdd,
  void Function(String productId)• onProductViewed,
  void Function(String productId)• onToggleFavorito,
  VoidCallback• onAbrirLoginParaFavorito,
  VoidCallback• onAbrirCarrinho,
  String• clienteId,
  List<String> favoritosIds = const [],
  required bool mostrarEstoqueNoCatalogo,
  required bool mostrarQuantidadeNoCatalogo,
  required double cardBorderRadius,
  required bool cardShowShadow,
  String• prazoEntregaTexto,
  double• jurosParcelamento,
  required int maxParcelas,
  required Color textColor,
}) {
  if (products.isEmpty) {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  return SliverToBoxAdapter(
    child: LayoutBuilder(
      builder: (context, constraints) {
        const paddingHorizontal = 12.0;
        const gapBetweenCards = 8.0;
        final screenWidth = constraints.maxWidth;
        final cardWidth =
            (screenWidth - paddingHorizontal * 2 - gapBetweenCards * 2) / 3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 360,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: paddingHorizontal),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final p = products[index];
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
                            • () => onToggleFavorito?.call(safeStr(p['id']))
                            : onAbrirLoginParaFavorito,
                        onAbrirCarrinho: onAbrirCarrinho,
                        clienteId: clienteId,
                        favoritosIds: favoritosIds,
                        todosProdutos: todosProdutos ?• products,
                        mostrarEstoqueNoCatalogo: mostrarEstoqueNoCatalogo,
                        mostrarQuantidadeNoCatalogo: mostrarQuantidadeNoCatalogo,
                        cardBorderRadius: cardBorderRadius,
                        cardShowShadow: cardShowShadow,
                        prazoEntregaTexto: prazoEntregaTexto,
                        jurosParcelamento: jurosParcelamento,
                        maxParcelas: maxParcelas,
                        compact: true,
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
