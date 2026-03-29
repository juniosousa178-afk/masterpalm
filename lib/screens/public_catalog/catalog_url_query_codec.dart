// Codificação estável de query params do catálogo público (ord, preço, busca).

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

/// Texto de busca na URL (`q`): apenas trim; vazio ou só espaços => null.
String? catalogSanitizeSearchQuery(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

/// Produto em foco na URL (`prod`): trim, vazio => null; limite leve contra abuse.
String? catalogSanitizeProdQuery(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.length > 160) return null;
  return t;
}

/// Variação extra na URL (`xv` = [extraValor]): mesmo critério defensivo que [catalogSanitizeProdQuery].
String? catalogSanitizeXvQuery(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.length > 160) return null;
  return t;
}

/// Paginação na URL (`page`): inteiro >= 1; inválido => null.
int? catalogParsePaginationPageQuery(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final n = int.tryParse(t);
  if (n == null || n < 1) return null;
  return n;
}

/// Valor para `page` na query: 1-based; página 1 => omitir (null).
/// [zeroBasedPage] e [totalPaginas] alinhados ao catálogo (20 itens/página).
String? catalogFormatPaginationPageQuery({
  required int zeroBasedPage,
  required int totalPaginas,
}) {
  if (totalPaginas < 1) return null;
  final maxIdx = totalPaginas - 1;
  final idx = zeroBasedPage.clamp(0, maxIdx);
  final oneBased = idx + 1;
  if (oneBased <= 1) return null;
  return oneBased.toString();
}

/// Interpreta `?page=` para rotas: número → grid; `dicas` → [namedInitialPage];
/// demais valores não numéricos → ignorar (o catálogo sanitiza na URL).
({int? catalogPage1Based, String? namedInitialPage})
    catalogInterpretPageQueryParam(String? raw) {
  if (raw == null) return (catalogPage1Based: null, namedInitialPage: null);
  final t = raw.trim();
  if (t.isEmpty) return (catalogPage1Based: null, namedInitialPage: null);
  final n = catalogParsePaginationPageQuery(t);
  if (n != null) return (catalogPage1Based: n, namedInitialPage: null);
  if (t.toLowerCase() == 'dicas') {
    return (catalogPage1Based: null, namedInitialPage: 'dicas');
  }
  return (catalogPage1Based: null, namedInitialPage: null);
}
