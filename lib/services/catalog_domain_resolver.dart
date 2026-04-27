// lib/services/catalog_domain_resolver.dart
//
// Domínio próprio deve resolver loja por índice direto domínio → loja
// (coleção [catalog_domains]). Não fazer scan em lojas nem aguardar timeouts longos
// antes de renderizar o catálogo.
//
// Documento: catalog_domains/{hostNormalizado}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../core/safe_cast.dart';
import 'catalog_domain_browser_cache.dart';

/// Coleção Firestore: um documento por host normalizado (id = host).
const String kCatalogDomainsCollection = 'catalog_domains';

/// Orçamento máximo para uma tentativa de resolução (cache miss → Firestore).
const Duration kCatalogDomainResolveBudget = Duration(seconds: 5);

String? sanitizePublicStoreName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  if (lower == 'masterpalm') return null;
  return t;
}

/// Normaliza host para id do documento: lowercase, trim, sem porta, sem `www.`.
String normalizeCatalogDomainHost(String raw) {
  var h = raw.trim().toLowerCase();
  if (h.isEmpty) return '';
  if (h.startsWith('www.')) {
    h = h.substring(4);
  }
  if (h.startsWith('[')) {
    final end = h.indexOf(']');
    if (end > 0) return h.substring(0, end + 1);
  }
  final colon = h.lastIndexOf(':');
  if (colon > 0) {
    final after = h.substring(colon + 1);
    if (RegExp(r'^\d+$').hasMatch(after)) {
      h = h.substring(0, colon);
    }
  }
  while (h.endsWith('.')) {
    h = h.substring(0, h.length - 1);
  }
  return h;
}

bool _firestoreStatusIsPublicActive(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  return s == 'ativo' || s == 'active';
}

/// Resultado interno da leitura Firestore (inclui [status] para gravar no cache).
class CatalogDomainFirestoreHit {
  final String lojaId;
  final String status;
  final String? nomeLoja;
  final String? logoUrl;

  const CatalogDomainFirestoreHit({
    required this.lojaId,
    required this.status,
    this.nomeLoja,
    this.logoUrl,
  });
}

String? _extractNomeLoja(dynamic rawData) {
  final data = asMap(rawData);
  if (data.isEmpty) return null;
  final direct = <String?>[
    data['nomeLoja']?.toString(),
    data['lojaNome']?.toString(),
    data['nomeFantasia']?.toString(),
    data['nome']?.toString(),
  ];
  for (final v in direct) {
    final t = (v ?? '').trim();
    final ok = sanitizePublicStoreName(t);
    if (ok != null) return ok;
  }
  final empresa = asMap(data['empresa']);
  if (empresa.isNotEmpty) {
    final n = (empresa['nome'] ?? '').toString().trim();
    final ok = sanitizePublicStoreName(n);
    if (ok != null) return ok;
  }
  return null;
}

String? sanitizePublicStoreLogoUrl(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  if (lower == 'null' || lower == 'undefined') return null;
  if (!(lower.startsWith('http://') || lower.startsWith('https://')))
    return null;
  return t;
}

String? _extractLogoUrl(dynamic rawData) {
  final data = asMap(rawData);
  if (data.isEmpty) return null;
  final direct = <String?>[
    data['logoUrl']?.toString(),
    data['logo']?.toString(),
    data['logoLoja']?.toString(),
    data['media.logo']?.toString(),
    data['media.logoUrl']?.toString(),
    data['imagens.logo']?.toString(),
    data['marca.logo']?.toString(),
  ];
  for (final v in direct) {
    final ok = sanitizePublicStoreLogoUrl(v);
    if (ok != null) return ok;
  }
  final empresa = asMap(data['empresa']);
  if (empresa.isNotEmpty) {
    final fromEmpresa = <String?>[
      empresa['logo']?.toString(),
      empresa['logoUrl']?.toString(),
    ];
    for (final v in fromEmpresa) {
      final ok = sanitizePublicStoreLogoUrl(v);
      if (ok != null) return ok;
    }
  }
  final media = asMap(data['media']);
  if (media.isNotEmpty) {
    final fromMedia = <String?>[
      media['logo']?.toString(),
      media['logoUrl']?.toString(),
    ];
    for (final v in fromMedia) {
      final ok = sanitizePublicStoreLogoUrl(v);
      if (ok != null) return ok;
    }
  }
  return null;
}

String? _lojaIdFromDomainDocData(dynamic rawData) {
  final data = asMap(rawData);
  if (data.isEmpty) return null;
  // Legado: só bloquear se vier explicitamente false.
  if (data['verified'] == false) return null;
  if (!_firestoreStatusIsPublicActive(data['status']?.toString())) {
    return null;
  }
  final lojaId = data['lojaId']?.toString().trim();
  if (lojaId == null || lojaId.isEmpty) return null;
  return lojaId;
}

Iterable<String> _catalogDomainDocIdsToTry(String normalizedHost) sync* {
  if (normalizedHost.isEmpty) return;
  yield normalizedHost;
  if (!normalizedHost.startsWith('catalogo.')) {
    yield 'catalogo.$normalizedHost';
  }
}

/// Lê o primeiro documento existente entre [normalizedHost] e `catalogo.` + apex.
Future<CatalogDomainFirestoreHit?> fetchCatalogDomainFromFirestore(
  String normalizedHost,
) async {
  if (normalizedHost.isEmpty) return null;
  if (Firebase.apps.isEmpty) return null;
  for (final docId in _catalogDomainDocIdsToTry(normalizedHost)) {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kCatalogDomainsCollection)
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 4));
      if (!snap.exists) continue;
      final data = snap.data();
      final lojaId = _lojaIdFromDomainDocData(data);
      if (lojaId == null) continue;
      final st = (data?['status'] ?? 'ativo').toString().trim();
      final nomeLoja = _extractNomeLoja(data);
      final logoUrl = _extractLogoUrl(data);
      logD('🌐 [CATALOG_DOMAIN] host=$docId → lojaId=$lojaId');
      return CatalogDomainFirestoreHit(
        lojaId: lojaId,
        status: st,
        nomeLoja: nomeLoja,
        logoUrl: logoUrl,
      );
    } on TimeoutException catch (_) {
      logW('⚠️ [CATALOG_DOMAIN] timeout ao ler catalog_domains/$docId');
    } catch (e) {
      logW('⚠️ [CATALOG_DOMAIN] leitura falhou ($docId type=${e.runtimeType})');
    }
  }
  return null;
}

/// API legada — preferir [resolveLojaIdForPublicCatalogHost].
Future<String?> resolveLojaIdFromCatalogDomainMap(String normalizedHost) async {
  final hit = await fetchCatalogDomainFromFirestore(normalizedHost);
  return hit?.lojaId;
}

/// Revalida em segundo plano o mapeamento e limpa cache se o domínio deixou de estar ativo.
void scheduleCatalogDomainCacheRevalidation(String normalizedHost) {
  if (!kIsWeb || normalizedHost.isEmpty) return;
  unawaited(() async {
    try {
      final hit = await fetchCatalogDomainFromFirestore(normalizedHost);
      if (hit == null) {
        CatalogDomainBrowserCache.clear(normalizedHost);
        return;
      }
      CatalogDomainBrowserCache.write(
        normalizedHost,
        hit.lojaId,
        hit.status,
        hit.nomeLoja,
        hit.logoUrl,
      );
    } catch (_) {}
  }());
}

/// Resolve [lojaId] para o catálogo público a partir do host atual (com cache no browser).
Future<String?> resolveLojaIdForPublicCatalogHost(
  String rawHost, {
  bool useBrowserCache = true,
}) async {
  final t0 = DateTime.now();
  final host = normalizeCatalogDomainHost(rawHost);
  if (kDebugMode) {
    debugPrint(
      '[CATALOG_DOMAIN_TIMING] host detectado+normalizado em '
      '${DateTime.now().difference(t0).inMilliseconds}ms → $host',
    );
  }
  if (host.isEmpty || Firebase.apps.isEmpty) return null;

  if (kIsWeb && useBrowserCache) {
    final cached = CatalogDomainBrowserCache.read(host);
    if (cached != null && cached.isValid) {
      if (kDebugMode) {
        debugPrint(
          '[CATALOG_DOMAIN_TIMING] cache válido → lojaId=${cached.lojaId} (instantâneo)'
          ' nomeLoja=${cached.nomeLoja ?? "-"} logo=${cached.logoUrl ?? "-"}',
        );
      }
      scheduleCatalogDomainCacheRevalidation(host);
      return cached.lojaId;
    }
  }

  final sw = Stopwatch()..start();
  CatalogDomainFirestoreHit? hit;
  try {
    hit = await fetchCatalogDomainFromFirestore(host).timeout(
      kCatalogDomainResolveBudget,
      onTimeout: () {
        logW(
            '⚠️ [CATALOG_DOMAIN] orçamento ${kCatalogDomainResolveBudget.inSeconds}s esgotado');
        return null;
      },
    );
  } catch (e) {
    logW('⚠️ [CATALOG_DOMAIN] resolve falhou (type=${e.runtimeType})');
  }
  if (kDebugMode) {
    debugPrint(
      '[CATALOG_DOMAIN_TIMING] Firestore resolve ${sw.elapsedMilliseconds}ms → ${hit?.lojaId}',
    );
  }

  if (hit != null) {
    if (kIsWeb) {
      CatalogDomainBrowserCache.write(
        host,
        hit.lojaId,
        hit.status,
        hit.nomeLoja,
        hit.logoUrl,
      );
    }
    return hit.lojaId;
  }
  if (kIsWeb) {
    CatalogDomainBrowserCache.clear(host);
  }
  return null;
}

/// Igual [resolveLojaIdForPublicCatalogHost], mas retorna metadados úteis do loader
/// (ex.: [nomeLoja]) quando disponíveis no cache/índice.
Future<CatalogDomainFirestoreHit?> resolveCatalogDomainHitForPublicCatalogHost(
  String rawHost, {
  bool useBrowserCache = true,
}) async {
  final host = normalizeCatalogDomainHost(rawHost);
  if (host.isEmpty || Firebase.apps.isEmpty) return null;

  if (kIsWeb && useBrowserCache) {
    final cached = CatalogDomainBrowserCache.read(host);
    if (cached != null && cached.isValid) {
      scheduleCatalogDomainCacheRevalidation(host);
      return CatalogDomainFirestoreHit(
        lojaId: cached.lojaId,
        status: cached.status,
        nomeLoja: cached.nomeLoja,
        logoUrl: cached.logoUrl,
      );
    }
  }

  final hit = await fetchCatalogDomainFromFirestore(host).timeout(
    kCatalogDomainResolveBudget,
    onTimeout: () => null,
  );
  if (hit != null && kIsWeb) {
    CatalogDomainBrowserCache.write(
      host,
      hit.lojaId,
      hit.status,
      hit.nomeLoja,
      hit.logoUrl,
    );
  }
  return hit;
}
