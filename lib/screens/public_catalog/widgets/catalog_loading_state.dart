// lib/screens/public_catalog/widgets/catalog_loading_state.dart
// Widget de loading inicial do catálogo (extraído de public_catalog_screen.dart)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog_unified_loading.dart';

/// UI de carregamento inicial do catálogo (lojaId).
class CatalogLoadingState extends StatelessWidget {
  final ThemeData themeData;

  const CatalogLoadingState({
    super.key,
    required this.themeData,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    }
    return Theme(
      data: themeData,
      child: Scaffold(
        backgroundColor: themeData.scaffoldBackgroundColor,
        body: SafeArea(
          child: CatalogUnifiedLoadingView(
            backgroundColor: themeData.scaffoldBackgroundColor,
            diagPhaseLabel: 'resolve_loja_id',
          ),
        ),
      ),
    );
  }
}
