import 'dart:html' as html;

import 'catalog_url_query_codec.dart';

String? _nonEmpty(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Interpreta `ord` atual na query (vazio => nome; inválido => sentinela).
String _ordInternalFromQueryMap(Map<String, String> qp) {
  final raw = qp['ord']?.trim();
  if (raw == null || raw.isEmpty) return 'nome';
  return catalogOrdQueryToInternal(raw) ?? '__bad__';
}

/// Atualiza na query apenas chaves do catálogo público, preservando `ref`, `page`, `cart`, etc.
/// Usa [history.replaceState] — não empilha histórico.
void catalogSyncPublicCatalogQueryUri({
  String? cat,
  String? sub,
  String? ord,
  String? pmin,
  String? pmax,
  String? tam,
  String? cor,
}) {
  final href = html.window.location.href;
  if (href.isEmpty) return;

  final u = Uri.parse(href);
  final qp = Map<String, String>.from(u.queryParameters);

  final wantCat = _nonEmpty(cat);
  final wantSub = _nonEmpty(sub);
  final wantOrdInternal = (ord != null && catalogOrdInternalIsValid(ord))
      ? ord
      : 'nome';
  final wantPmin = _nonEmpty(pmin);
  final wantPmax = _nonEmpty(pmax);
  final wantTam = _nonEmpty(tam);
  final wantCor = _nonEmpty(cor);

  final curOrdInternal = _ordInternalFromQueryMap(qp);
  if (qp['cat'] == wantCat &&
      qp['sub'] == wantSub &&
      curOrdInternal == wantOrdInternal &&
      qp['pmin'] == wantPmin &&
      qp['pmax'] == wantPmax &&
      qp['tam'] == wantTam &&
      qp['cor'] == wantCor) {
    return;
  }

  void setOrRemove(String key, String? val) {
    if (val == null || val.isEmpty) {
      qp.remove(key);
    } else {
      qp[key] = val;
    }
  }

  setOrRemove('cat', wantCat);
  setOrRemove('sub', wantSub);
  if (wantOrdInternal == 'nome') {
    qp.remove('ord');
  } else {
    qp['ord'] = catalogOrdInternalToQuery(wantOrdInternal);
  }
  setOrRemove('pmin', wantPmin);
  setOrRemove('pmax', wantPmax);
  setOrRemove('tam', wantTam);
  setOrRemove('cor', wantCor);

  final newQuery = Uri(queryParameters: qp).query;
  final path = u.path;
  final fragment = u.hasFragment ? '#${u.fragment}' : '';
  final relative = '$path${newQuery.isNotEmpty ? '?$newQuery' : ''}$fragment';
  html.window.history.replaceState(null, '', relative);
}
