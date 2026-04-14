// lib/services/catalog_domain_resolver.dart
// P0: mapeamento mínimo host → lojaId para catálogo web (domínio customizado).
// Documento: catalog_domains/{hostNormalizado}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/logger.dart';

/// Coleção Firestore: um documento por host normalizado (id = host).
const String kCatalogDomainsCollection = 'catalog_domains';

/// Normaliza host: lowercase, trim, sem porta (Uri.host já vem sem porta na prática).
String normalizeCatalogDomainHost(String raw) {
  var h = raw.trim().toLowerCase();
  if (h.isEmpty) return '';
  // IPv6 ou host:porta raro em Uri.host; defensivo
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

/// Resolve [lojaId] canônico a partir do host mapeado em [catalog_domains].
/// Retorna null se Firebase indisponível, host vazio, doc inexistente ou inválido.
Future<String?> resolveLojaIdFromCatalogDomainMap(String normalizedHost) async {
  if (normalizedHost.isEmpty) return null;
  if (Firebase.apps.isEmpty) return null;
  try {
    final snap = await FirebaseFirestore.instance
        .collection(kCatalogDomainsCollection)
        .doc(normalizedHost)
        .get()
        .timeout(const Duration(seconds: 4));
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    if (data['status']?.toString() != 'active') return null;
    if (data['verified'] != true) return null;
    final lojaId = data['lojaId']?.toString().trim();
    if (lojaId == null || lojaId.isEmpty) return null;
    logD('🌐 [CATALOG_DOMAIN] host=$normalizedHost → lojaId=$lojaId');
    return lojaId;
  } on TimeoutException catch (_) {
    logW('⚠️ [CATALOG_DOMAIN] timeout ao ler catalog_domains');
    return null;
  } catch (e) {
    logW('⚠️ [CATALOG_DOMAIN] leitura falhou (type=${e.runtimeType})');
    return null;
  }
}
