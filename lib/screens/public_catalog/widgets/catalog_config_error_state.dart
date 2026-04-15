// lib/screens/public_catalog/widgets/catalog_config_error_state.dart
// Erro quando config da loja não foi encontrada (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// UI quando configuração da loja não foi encontrada.
class CatalogConfigErrorState extends StatelessWidget {
  final ThemeData? themeData;

  const CatalogConfigErrorState({super.key, this.themeData});

  @override
  Widget build(BuildContext context) {
    final theme = themeData ?? Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 64,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Configuração da loja não encontrada.',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
