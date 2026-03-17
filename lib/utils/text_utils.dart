// lib/utils/text_utils.dart
// Helpers para normalização de texto (comparação de nomes, etc.)

import 'package:diacritic/diacritic.dart';

/// Normaliza texto para comparação: remove acentos e converte para minúsculas.
/// Usado para matching de cliente por nome em vendas antigas.
String normalizeText(String text) {
  if (text.isEmpty) return '';
  return removeDiacritics(text.trim().toLowerCase());
}

/// Capitaliza a primeira letra de cada palavra.
/// Ex: "joão da silva" → "João Da Silva"
String capitalizeWords(String text) {
  if (text.isEmpty) return '';
  return text.trim().split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join(' ');
}

/// Garante string segura para envio ao native (Share, platform channel).
/// Substitui substitutos Unicode não pareados por U+FFFD para evitar "Invalid UTF8 sequence".
String sanitizeForPlatform(String text) {
  if (text.isEmpty) return text;
  final runes = text.runes.toList();
  final buffer = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    if (r >= 0xD800 && r <= 0xDBFF) {
      if (i + 1 < runes.length && runes[i + 1] >= 0xDC00 && runes[i + 1] <= 0xDFFF) {
        buffer.writeCharCode(r);
        buffer.writeCharCode(runes[i + 1]);
        i++;
      } else {
        buffer.writeCharCode(0xFFFD);
      }
    } else if (r >= 0xDC00 && r <= 0xDFFF) {
      buffer.writeCharCode(0xFFFD);
    } else {
      buffer.writeCharCode(r);
    }
  }
  return buffer.toString();
}
