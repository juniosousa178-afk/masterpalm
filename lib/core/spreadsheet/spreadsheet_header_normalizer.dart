import 'package:diacritic/diacritic.dart';

/// Normaliza cabeçalho de planilha para comparação determinística.
String normalizeSpreadsheetHeader(String raw) {
  var out = raw.replaceAll('\u00A0', ' ');
  out = out.replaceAll(RegExp(r'[\t\r\n]+'), ' ');
  out = out.trim().toLowerCase();
  out = removeDiacritics(out);
  out = out.replaceAll(RegExp(r'[_\-/]+'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}
