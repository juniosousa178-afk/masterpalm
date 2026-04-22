// ignore_for_file: avoid_web_libraries_in_flutter
// Web-only: replaceState / location (Flutter web plugin pattern).
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

/// Atualiza na query apenas chaves do catálogo público, preservando `ref`, `cart`, etc.
/// `page` nomeado (ex.: dicas) não é removido quando [page] é null (só limpa valor numérico).
/// Usa [history.replaceState] — não empilha histórico.
void catalogSyncPublicCatalogQueryUri({
  String? cat,
  String? sub,
  String? ord,
  String? pmin,
  String? pmax,
  String? tam,
  String? cor,
  String? xv,
  String? q,
  String? page,
  String? prod,
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
  final wantXv = _nonEmpty(xv);
  final wantQ = _nonEmpty(q);
  final wantPage = _nonEmpty(page);
  final wantProd = _nonEmpty(prod);

  bool pageQueryMatches() {
    final curRaw = qp['page'];
    if (curRaw == null || curRaw.trim().isEmpty) {
      return wantPage == null;
    }
    final cur = curRaw.trim();
    final curParsed = int.tryParse(cur);
    if (curParsed == null) {
      // Só preserva nomeado "dicas"; outros (ex.: page=abc) devem ser removidos.
      final isDicas = cur.toLowerCase() == 'dicas';
      if (isDicas) return wantPage == null;
      return false;
    }
    return cur == wantPage;
  }

  final curOrdInternal = _ordInternalFromQueryMap(qp);
  if (qp['cat'] == wantCat &&
      qp['sub'] == wantSub &&
      curOrdInternal == wantOrdInternal &&
      qp['pmin'] == wantPmin &&
      qp['pmax'] == wantPmax &&
      qp['tam'] == wantTam &&
      qp['cor'] == wantCor &&
      qp['xv'] == wantXv &&
      qp['q'] == wantQ &&
      qp['prod'] == wantProd &&
      pageQueryMatches()) {
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
  setOrRemove('xv', wantXv);
  setOrRemove('q', wantQ);
  setOrRemove('prod', wantProd);

  final curPageRaw = qp['page'];
  final curTrim = curPageRaw?.trim() ?? '';
  final curParsed = curTrim.isEmpty ? null : int.tryParse(curTrim);
  final curPageNamedNonDicas = curTrim.isNotEmpty &&
      curParsed == null &&
      curTrim.toLowerCase() != 'dicas';
  if (wantPage == null) {
    if (curPageNamedNonDicas || curParsed != null) {
      qp.remove('page');
    }
  } else {
    qp['page'] = wantPage;
  }

  final newQuery = Uri(queryParameters: qp).query;
  final path = u.path;
  final fragment = u.hasFragment ? '#${u.fragment}' : '';
  final relative = '$path${newQuery.isNotEmpty ? '?$newQuery' : ''}$fragment';
  html.window.history.replaceState(null, '', relative);
}
