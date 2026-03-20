// lib/themes/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  // ============================
  // MP: Paleta de cores padrão
  // ============================
  static const Color neonBlue  = Color(0xFF00A8FF);
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color bgDark    = Color(0xFF000000);
  // OBS: usando ARGB explícito para evitar confusão de máscaras
  static const Color surface10 = Color(0x1AFFFFFF); // ~10% branco
  static const Color surface20 = Color(0x33FFFFFF); // ~20% branco
  static const Color textOnDark = Colors.white;

  // Mantido do seu projeto (NÃO alterei nada aqui)
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16),
      ),
    );
  }

  // ============================================
  // MP: Tema dark futurista (MasterPalm visual)
  // ============================================
  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: neonBlue,
        secondary: neonGreen,
        surface: Color(0xFF0E0E10),
        onSurface: Colors.white,
      ),
    );

    return base.copyWith(
      // AppBar minimalista
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: textOnDark,
        elevation: 0,
        centerTitle: false,
      ),

      // Campos de texto estilo “glass”
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface20,
        hintStyle: const TextStyle(color: Colors.white70),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: neonBlue, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),

      // Botão principal fluorescente azul
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: neonBlue,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      // Botão secundário fluorescente verde (use OutlinedButton)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: neonGreen,
          side: const BorderSide(color: neonGreen, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // Chips e Badges — usa WidgetStateProperty para cores por estado
      chipTheme: base.chipTheme.copyWith(
        // Cor do container por estado (selecionado ganha um “azul 25%”)
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          final selected = states.contains(WidgetState.selected);
          return selected
              • neonBlue.withValues(alpha:0.25)
              : surface10;
        }),
        // Estilo do texto
        labelStyle: const TextStyle(color: Colors.white),
        // Opcional: checkmark/ícone
        checkmarkColor: Colors.white,
      ),

      // Cards “glass”
      cardTheme: base.cardTheme.copyWith(
        color: surface10,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      ),

      // Diálogos
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: const Color(0xFF0E0E10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: const TextStyle(height: 1.4),
      ),

      // Snackbars
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF141416),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),

      // Tipografia
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        bodyMedium: const TextStyle(fontSize: 16),
      ),
    );
  }

  // Alias padrão
  static ThemeData get theme => darkTheme;
}

