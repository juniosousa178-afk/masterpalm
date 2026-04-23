// lib/screens/public_catalog/catalog_storage_image_url_resolver.dart
// Corrige URLs do Firebase Storage quando o path usa slug/ID antigo em `lojas/{id}/…`
// e o catálogo já resolveu o ID canónico da loja (evita 404 + exceções na Web).
// Também obtém token de download atual (evita 403/404 intermitente em URL antiga).

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'catalog_helpers.dart' show isValidHttpUrl;

/// URLs de mídia servidas pelo Firebase Storage (formato clássico ou `*.firebasestorage.app`).
bool isCatalogFirebaseStorageMediaUrl(String url) {
  if (url.isEmpty) return false;
  return url.contains('firebasestorage.googleapis.com') ||
      url.contains('.firebasestorage.app');
}

/// Decodifica o segmento de path do objeto após `/o/` na URL de download do Storage.
String? firebaseStorageDecodedObjectPath(String downloadUrl) {
  final i = downloadUrl.indexOf('/o/');
  if (i < 0) return null;
  final start = i + 3;
  final q = downloadUrl.indexOf('?', start);
  final encoded = q < 0
      ? downloadUrl.substring(start)
      : downloadUrl.substring(start, q);
  try {
    return Uri.decodeFull(encoded);
  } catch (_) {
    return null;
  }
}

final Map<String, String> _resolvedUrlMemo = {};
final Map<String, Future<String>> _resolveInflight = {};

/// Se [originalUrl] aponta para `lojas/{outroId}/…` e [canonicalLojaId] difere de [outroId],
/// tenta obter URL de download para `lojas/{canonicalLojaId}/…` (mesmo sufixo).
/// Caso contrário devolve [originalUrl]. Resultados são memorizados por sessão.
Future<String> resolveCatalogFirebaseStorageDownloadUrl(
  String originalUrl,
  String canonicalLojaId,
) async {
  final canon = canonicalLojaId.trim();
  if (originalUrl.isEmpty || canon.isEmpty) return originalUrl;
  if (!isCatalogFirebaseStorageMediaUrl(originalUrl)) {
    return originalUrl;
  }

  final decoded = firebaseStorageDecodedObjectPath(originalUrl);
  if (decoded == null) return originalUrl;

  final parts = decoded.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 3 || parts[0] != 'lojas') return originalUrl;

  final segment = parts[1];
  if (segment == canon) return originalUrl;

  final memoKey = '$canon::$decoded';
  final cached = _resolvedUrlMemo[memoKey];
  if (cached != null) return cached;

  return _resolveInflight.putIfAbsent(memoKey, () async {
    try {
      final suffix = parts.sublist(2).join('/');
      final newPath = 'lojas/$canon/$suffix';
      final ref = FirebaseStorage.instance.ref(newPath);
      final fixed = await ref.getDownloadURL();
      _resolvedUrlMemo[memoKey] = fixed;
      if (_resolvedUrlMemo.length > 600) {
        _resolvedUrlMemo.clear();
      }
      return fixed;
    } catch (_) {
      _resolvedUrlMemo[memoKey] = originalUrl;
      return originalUrl;
    } finally {
      _resolveInflight.remove(memoKey);
    }
  });
}

final Map<String, String> _refreshedDownloadUrlMemo = {};
final Map<String, Future<String>> _refreshedDownloadInflight = {};

Future<String> _refreshedFirebaseStorageDownloadUrl(String u) {
  final c = _refreshedDownloadUrlMemo[u];
  if (c != null) {
    return Future.value(c);
  }
  return _refreshedDownloadInflight.putIfAbsent(u, () async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(u);
      final fresh = await ref.getDownloadURL();
      _refreshedDownloadUrlMemo[u] = fresh;
      if (_refreshedDownloadUrlMemo.length > 500) {
        _refreshedDownloadUrlMemo.clear();
      }
      return fresh;
    } catch (_) {
      _refreshedDownloadUrlMemo[u] = u;
      return u;
    } finally {
      _refreshedDownloadInflight.remove(u);
    }
  });
}

/// (1) Se [canonicalLojaId] difere de `lojas/…/`, ajusta o path. (2) Para qualquer
/// URL conhecida do Storage, gera download URL com token actual (mesmo com ID já correcto).
Future<String> resolveCatalogImageUrlForDisplay(
  String originalUrl, {
  String? canonicalLojaId,
}) async {
  if (originalUrl.isEmpty) return originalUrl;
  var u = originalUrl;
  final canon = canonicalLojaId?.trim() ?? '';
  if (canon.isNotEmpty &&
      isValidHttpUrl(u) &&
      isCatalogFirebaseStorageMediaUrl(u)) {
    final decoded = firebaseStorageDecodedObjectPath(u);
    if (decoded != null) {
      final parts = decoded.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 3 && parts[0] == 'lojas' && parts[1] != canon) {
        u = await resolveCatalogFirebaseStorageDownloadUrl(u, canon);
      }
    }
  }
  if (!isValidHttpUrl(u) || !isCatalogFirebaseStorageMediaUrl(u)) {
    return u;
  }
  // No web, refresh via SDK por vezes atrapalha (CORS/CanvasKit) — URL já traz
  // token; slug fixo acima é o que importa. Android/iOS: token fresco.
  if (kIsWeb) {
    return u;
  }
  return _refreshedFirebaseStorageDownloadUrl(u);
}
