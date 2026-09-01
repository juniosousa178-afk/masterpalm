/// Parser numérico determinístico para valores de planilha (PT-BR e EN).
double? parseSpreadsheetNumber(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();

  var s = raw.toString().trim();
  if (s.isEmpty) return null;

  s = s.replaceAll(RegExp(r'[R\$€USD\s]+', caseSensitive: false), '');
  if (s.isEmpty) return null;

  final brMatch = RegExp(r'^(\d{1,3}(?:\.\d{3})*),(\d+)$').firstMatch(s);
  if (brMatch != null) {
    final parteInteira = brMatch.group(1)!.replaceAll('.', '');
    final parteDec = brMatch.group(2)!;
    return double.tryParse('$parteInteira.$parteDec');
  }

  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');

  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      // BR: 1.234,56
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // EN: 1,234.56
      s = s.replaceAll(',', '');
    }
    return double.tryParse(s);
  }

  if (lastComma >= 0 && lastDot < 0) {
    return double.tryParse(s.replaceAll(',', '.'));
  }

  return double.tryParse(s);
}
