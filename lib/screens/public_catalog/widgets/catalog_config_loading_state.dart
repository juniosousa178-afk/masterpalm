// lib/screens/public_catalog/widgets/catalog_config_loading_state.dart
// Loading enquanto espera config do StreamBuilder (extraído de public_catalog_screen.dart)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'catalog_unified_loading.dart';

/// UI de loading enquanto aguarda config da loja (StreamBuilder connectionState == waiting).
class CatalogConfigLoadingState extends StatelessWidget {
  final ThemeData? themeData;

  const CatalogConfigLoadingState({super.key, this.themeData});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    }
    final theme = themeData ?? Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CatalogUnifiedLoadingView(
          backgroundColor: theme.scaffoldBackgroundColor,
          diagPhaseLabel: 'cfg_stream',
        ),
      ),
    );
  }
}
