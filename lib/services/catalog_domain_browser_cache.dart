import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog_domain_browser_storage_stub.dart'
    if (dart.library.html) 'catalog_domain_browser_storage_web.dart';

/// TTL sugerido: 10–30 min; usamos 20 min.
const Duration kCatalogDomainBrowserCacheTtl = Duration(minutes: 20);

class CatalogDomainCacheEntry {
  final String lojaId;
  final String status;
  final String? nomeLoja;
  final String? logoUrl;
  final int cachedAtMs;

  const CatalogDomainCacheEntry({
    required this.lojaId,
    required this.status,
    this.nomeLoja,
    this.logoUrl,
    required this.cachedAtMs,
  });

  bool get isValid {
    if (lojaId.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
    if (age > kCatalogDomainBrowserCacheTtl.inMilliseconds) return false;
    return _statusMeansActiveForCache(status);
  }
}

bool _statusMeansActiveForCache(String s) {
  final t = s.trim().toLowerCase();
  return t == 'ativo' || t == 'active';
}

String? _sanitizePublicStoreNameForCache(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (t.toLowerCase() == 'masterpalm') return null;
  return t;
}

String? _sanitizePublicStoreLogoUrlForCache(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  if (lower == 'null' || lower == 'undefined') return null;
  if (!(lower.startsWith('http://') || lower.startsWith('https://')))
    return null;
  return t;
}

/// Cache leve no navegador: `catalog_domain_cache_v2_{hostNormalizado}`.
class CatalogDomainBrowserCache {
  CatalogDomainBrowserCache._();

  static const String _prefix = 'catalog_domain_cache_v2_';
  static const String _legacyPrefix = 'catalog_domain_cache_v1_';

  static String _key(String normalizedHost) => '$_prefix$normalizedHost';

  static CatalogDomainCacheEntry? read(String normalizedHost) {
    if (normalizedHost.isEmpty) return null;
    try {
      final raw = catalogDomainBrowserStorageGet(_key(normalizedHost));
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final lojaId = (m['lojaId'] ?? '').toString().trim();
      final status = (m['status'] ?? '').toString().trim();
      final nomeLoja = _sanitizePublicStoreNameForCache(
        (m['nomeLoja'] ?? '').toString().trim(),
      );
      final logoUrl = _sanitizePublicStoreLogoUrlForCache(
        (m['logoUrl'] ?? '').toString().trim(),
      );
      final cachedAt =
          (m['cachedAt'] is num) ? (m['cachedAt'] as num).toInt() : 0;
      if (lojaId.isEmpty || cachedAt <= 0) return null;
      return CatalogDomainCacheEntry(
        lojaId: lojaId,
        status: status,
        nomeLoja: nomeLoja,
        logoUrl: logoUrl,
        cachedAtMs: cachedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static void write(
    String normalizedHost,
    String lojaId,
    String status,
    String? nomeLoja,
    String? logoUrl,
  ) {
    final nomeLojaOk = _sanitizePublicStoreNameForCache(nomeLoja);
    final logoUrlOk = _sanitizePublicStoreLogoUrlForCache(logoUrl);
    if (normalizedHost.isEmpty || lojaId.isEmpty) return;
    try {
      final payload = jsonEncode(<String, Object?>{
        'lojaId': lojaId,
        'status': status,
        if (nomeLojaOk != null) 'nomeLoja': nomeLojaOk,
        if (logoUrlOk != null) 'logoUrl': logoUrlOk,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      });
      catalogDomainBrowserStorageSet(_key(normalizedHost), payload);
      catalogDomainBrowserStorageRemove('$_legacyPrefix$normalizedHost');
    } catch (_) {}

    if (kDebugMode) {
      debugPrint(
        '[CATALOG_DOMAIN_CACHE] write host=$normalizedHost lojaId=$lojaId',
      );
    }
  }

  static void clear(String normalizedHost) {
    if (normalizedHost.isEmpty) return;
    try {
      catalogDomainBrowserStorageRemove(_key(normalizedHost));
      catalogDomainBrowserStorageRemove('$_legacyPrefix$normalizedHost');
    } catch (_) {}
  }
}
