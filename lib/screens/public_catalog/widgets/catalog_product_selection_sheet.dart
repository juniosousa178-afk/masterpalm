// lib/screens/public_catalog/widgets/catalog_product_selection_sheet.dart
// Modal de seleção de tamanho/cor — corpo em [CatalogProductVariationPickBody].

import 'package:flutter/material.dart';

import 'catalog_product_variation_pick_body.dart';

class CatalogProductSelectionSheet extends StatelessWidget {
  final String name;
  final double price;
  final double? precoOriginal;
  final bool emPromocao;
  final String imageUrl;
  final Map<String, int> estoquePorTamanho;
  final Map<String, int> estoquePorCor;
  final Map<String, dynamic>? variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final Map<String, double>? precoPorTamanho;
  final CatalogVariationPickCommit onAddToCart;
  final double percentualDescontoPix;
  final bool mostrarQuantidadeNoCatalogo;
  final String? initialExtraValor;
  final void Function(String? value)? onCatalogVariacaoExtraChanged;

  const CatalogProductSelectionSheet({
    super.key,
    required this.name,
    required this.price,
    this.precoOriginal,
    required this.emPromocao,
    required this.imageUrl,
    required this.estoquePorTamanho,
    required this.estoquePorCor,
    this.variacoes,
    this.variacoesExtraTipo,
    this.precoPorTamanho,
    required this.onAddToCart,
    this.percentualDescontoPix = 0.0,
    this.mostrarQuantidadeNoCatalogo = false,
    this.initialExtraValor,
    this.onCatalogVariacaoExtraChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selecione as opcoes',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CatalogProductVariationPickBody(
                name: name,
                price: price,
                precoOriginal: precoOriginal,
                emPromocao: emPromocao,
                imageUrl: imageUrl,
                estoquePorTamanho: estoquePorTamanho,
                estoquePorCor: estoquePorCor,
                variacoes: variacoes,
                variacoesExtraTipo: variacoesExtraTipo,
                precoPorTamanho: precoPorTamanho,
                onPickCommit: onAddToCart,
                percentualDescontoPix: percentualDescontoPix,
                mostrarQuantidadeNoCatalogo: mostrarQuantidadeNoCatalogo,
                initialExtraValor: initialExtraValor,
                onCatalogVariacaoExtraChanged: onCatalogVariacaoExtraChanged,
                showProductSnippet: true,
                showAddToCartButton: true,
                showSectionTitle: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
