// lib/screens/public_catalog/widgets/catalog_config_loading_state.dart
// Loading enquanto espera config do StreamBuilder (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// UI de loading enquanto aguarda config da loja (StreamBuilder connectionState == waiting).
class CatalogConfigLoadingState extends StatelessWidget {
  final ThemeData? themeData;

  const CatalogConfigLoadingState({super.key, this.themeData});

  @override
  Widget build(BuildContext context) {
    final theme = themeData ?? Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Carregando loja',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Estamos preparando a loja para você.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.75),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
