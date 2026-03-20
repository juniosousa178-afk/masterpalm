// lib/screens/public_catalog/widgets/catalog_config_loading_state.dart
// Loading enquanto espera config do StreamBuilder (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// UI de loading enquanto aguarda config da loja (StreamBuilder connectionState == waiting).
class CatalogConfigLoadingState extends StatelessWidget {
  final ThemeData• themeData;

  const CatalogConfigLoadingState({super.key, this.themeData});

  @override
  Widget build(BuildContext context) {
    final theme = themeData ?• Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Carregando catálogo...',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
