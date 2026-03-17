// lib/utils/theme_extensions.dart
// Use nas telas para modo escuro/claro: texto branco no escuro, preto no claro.

import 'package:flutter/material.dart';

extension ThemeContext on BuildContext {
  /// Cor de texto principal: preto no tema claro, branco no escuro.
  Color get adaptiveTextColor => Theme.of(this).colorScheme.onSurface;

  /// Cor de superfície (fundo de cards, etc.).
  Color get adaptiveSurfaceColor => Theme.of(this).colorScheme.surface;

  /// Cor secundária para texto (subtítulos).
  Color get adaptiveTextSecondary =>
      Theme.of(this).colorScheme.onSurfaceVariant;

  /// Retorna se o tema atual é escuro.
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;
}
