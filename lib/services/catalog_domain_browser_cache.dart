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
  final int cachedAtMs;

  const CatalogDomainCacheEntry({
    required this.lojaId,
    required this.status,
    this.nomeLoja,
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

/// Cache leve no navegador: `catalog_domain_cache_v1_{hostNormalizado}`.
class CatalogDomainBrowserCache {
  CatalogDomainBrowserCache._();

  static const String _prefix = 'catalog_domain_cache_v1_';

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
      final nomeLoja = (m['nomeLoja'] ?? '').toString().trim();
      final cachedAt =
          (m['cachedAt'] is num) ? (m['cachedAt'] as num).toInt() : 0;
      if (lojaId.isEmpty || cachedAt <= 0) return null;
      return CatalogDomainCacheEntry(
        lojaId: lojaId,
        status: status,
        nomeLoja: nomeLoja.isEmpty ? null : nomeLoja,
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
  ) {
    if (normalizedHost.isEmpty || lojaId.isEmpty) return;
    try {
      final payload = jsonEncode(<String, Object?>{
        'lojaId': lojaId,
        'status': status,
        if ((nomeLoja ?? '').trim().isNotEmpty) 'nomeLoja': nomeLoja!.trim(),
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      });
      catalogDomainBrowserStorageSet(_key(normalizedHost), payload);
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
    } catch (_) {}
  }
}
