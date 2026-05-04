// lib/screens/public_catalog/widgets/catalog_loading_state.dart
// Widget de loading inicial do catálogo (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// UI de carregamento inicial do catálogo (lojaId).
class CatalogLoadingState extends StatelessWidget {
  final ThemeData themeData;

  const CatalogLoadingState({
    super.key,
    required this.themeData,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themeData,
      child: Scaffold(
        backgroundColor: themeData.scaffoldBackgroundColor,
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
                  color: themeData.colorScheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Estamos preparando a loja para você.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: themeData.colorScheme.onSurface.withOpacity(0.75),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
