// Codificação estável de query params do catálogo público (ord, preço).

/// Converte valor de `ord` na URL para chave interna [_ordenacaoProdutos].
/// Aceita aliases amigáveis (`menor_preco`) e técnicos (`preco_asc`).
String? catalogOrdQueryToInternal(String? raw) {
  if (raw == null) return null;
  final s =
      raw.trim().toLowerCase().replaceAll('-', '_');
  if (s.isEmpty) return null;
  switch (s) {
    case 'nome':
      return 'nome';
    case 'novidade':
      return 'novidade';
    case 'preco_asc':
    case 'menor_preco':
    case 'menor':
      return 'preco_asc';
    case 'preco_desc':
    case 'maior_preco':
    case 'maior':
      return 'preco_desc';
    default:
      return null;
  }
}

/// Valor gravado na URL (estável para compartilhamento).
String catalogOrdInternalToQuery(String internal) {
  switch (internal) {
    case 'novidade':
      return 'novidade';
    case 'preco_asc':
      return 'menor_preco';
    case 'preco_desc':
      return 'maior_preco';
    case 'nome':
    default:
      return 'nome';
  }
}

bool catalogOrdInternalIsValid(String? v) {
  return v == 'nome' ||
      v == 'novidade' ||
      v == 'preco_asc' ||
      v == 'preco_desc';
}

/// Parse defensivo para `pmin` / `pmax` (aceita vírgula decimal).
double? catalogParsePrecoQuery(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Formato simples na URL (sem zeros desnecessários à direita).
String? catalogFormatPrecoQuery(double? v) {
  if (v == null) return null;
  if (v.isNaN || v.isInfinite) return null;
  if (v == v.roundToDouble()) {
    return v.round().toString();
  }
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s.isEmpty ? null : s;
}
