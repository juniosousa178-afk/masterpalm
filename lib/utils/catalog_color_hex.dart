import 'package:flutter/material.dart';

/// Parse seguro de hex para [Color]. Aceita `#RGB`, `#RRGGBB`, `#AARRGGBB` (com ou sem `#`).
/// Retorna `null` se inválido — nunca lança.
Color? tryParseCatalogHex(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'\s'), '');
  if (!s.startsWith('#')) s = '#$s';
  var hex = s.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;

  if (hex.length == 3) {
    final r = hex[0] + hex[0];
    final g = hex[1] + hex[1];
    final b = hex[2] + hex[2];
    hex = r + g + b;
  }

  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
  if (hex.length == 8) {
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(v);
  }
  return null;
}

/// Formato estável para exibição e cópia (sempre `#RRGGBB`).
String formatCatalogHexRgb(Color color) {
  final argb = color.value;
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Inclui alpha quando não for FF (útil para debug / cópia avançada).
String formatCatalogHexArgb(Color color) {
  final v = color.value;
  return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
