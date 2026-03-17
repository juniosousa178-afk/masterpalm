// lib/screens/public_catalog/widgets/catalog_empty_products_state.dart
// Estado vazio quando não há produtos no catálogo (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// Sliver exibido quando não há produtos disponíveis.
class CatalogEmptyProductsState extends StatelessWidget {
  const CatalogEmptyProductsState({super.key});

  @override
  Widget build(BuildContext context) {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text('Nenhum produto disponível.'),
      ),
    );
  }
}
