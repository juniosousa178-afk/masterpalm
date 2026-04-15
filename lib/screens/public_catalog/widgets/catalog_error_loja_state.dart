// lib/screens/public_catalog/widgets/catalog_error_loja_state.dart
// Estado de erro quando não foi possível carregar o catálogo (extraído de public_catalog_screen.dart)

import 'package:flutter/material.dart';

/// UI quando a loja não pôde ser carregada (link inválido, etc).
class CatalogErrorLojaState extends StatelessWidget {
  final ThemeData themeData;

  const CatalogErrorLojaState({
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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 64,
                  color: themeData.colorScheme.onSurface.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Não foi possível carregar o catálogo.',
                  style: themeData.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Verifique se o link está correto e completo (ex: app.mastepalm.com.br/loja/nome-da-loja).',
                  style: themeData.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

