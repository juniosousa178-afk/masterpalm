// lib/services/catalog_domains_index_service.dart
// Mantém índice direto catalog_domains/{host} ↔ loja ao publicar ou ativar domínio.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../catalog/domain/catalog_custom_domain.dart';
import 'catalog_domain_resolver.dart';

const String kCatalogDomainIndexStatusAtivo = 'ativo';
const String kCatalogDomainIndexStatusInativo = 'inativo';

/// Hosts que recebem documento no índice (apex + subdomínio recomendado do catálogo).
Set<String> catalogDomainIndexDocIdsForConfig(String normalizedDomainInput) {
  final base = normalizeCatalogDomainInput(normalizedDomainInput);
  if (base.isEmpty) return {};
  final h = normalizeCatalogDomainHost(base);
  if (h.isEmpty) return {};
  final out = <String>{h};
  final rec = recommendedCatalogFqdn(base);
  final recNorm = normalizeCatalogDomainHost(rec);
  if (recNorm.isNotEmpty && recNorm != h) {
    out.add(recNorm);
  }
  return out;
}

class CatalogDomainsIndexService {
  CatalogDomainsIndexService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> _writeInactiveForHosts(Set<String> hosts) async {
    for (final id in hosts) {
      if (id.isEmpty) continue;
      try {
        await _db.collection(kCatalogDomainsCollection).doc(id).set(
          <String, dynamic>{
            'status': kCatalogDomainIndexStatusInativo,
            'atualizadoEm': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }

  static Future<void> _writeActiveForHosts({
    required String lojaId,
    required String dominioDisplay,
    required Set<String> hosts,
  }) async {
    final idLoja = lojaId.trim();
    if (idLoja.isEmpty || hosts.isEmpty) return;
    for (final hostId in hosts) {
      if (hostId.isEmpty) continue;
      try {
        await _db.collection(kCatalogDomainsCollection).doc(hostId).set(
          <String, dynamic>{
            'lojaId': idLoja,
            'dominio': dominioDisplay,
            'status': kCatalogDomainIndexStatusAtivo,
            'verified': true,
            'atualizadoEm': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }

  /// Chamado após publicar [config/config] (mapa já mesclado com domínio).
  static Future<void> syncAfterCatalogPublish({
    required String lojaId,
    required Map<String, dynamic> publishedConfig,
    String? previousDominioCatalogoNormalized,
  }) async {
    final idLoja = lojaId.trim();
    if (idLoja.isEmpty) return;

    final domRaw =
        (publishedConfig['dominioCatalogo'] ?? publishedConfig['dominio_catalogo'] ?? '')
            .toString();
    final domNorm = normalizeCatalogDomainInput(domRaw);
    final st = (publishedConfig['dominioStatus'] ?? publishedConfig['dominio_status'] ?? '')
        .toString();

    final oldHosts = previousDominioCatalogoNormalized == null ||
            previousDominioCatalogoNormalized.isEmpty
        ? <String>{}
        : catalogDomainIndexDocIdsForConfig(previousDominioCatalogoNormalized);

    final newHosts =
        domNorm.isNotEmpty && st.trim().toLowerCase() == kDominioStatusAtivo
            ? catalogDomainIndexDocIdsForConfig(domNorm)
            : <String>{};

    final toDeactivate = oldHosts.difference(newHosts);
    if (toDeactivate.isNotEmpty) {
      await _writeInactiveForHosts(toDeactivate);
    }

    if (newHosts.isNotEmpty) {
      await _writeActiveForHosts(
        lojaId: idLoja,
        dominioDisplay: domNorm,
        hosts: newHosts,
      );
    }
  }

  /// Após verificação DNS bem-sucedida (status ativo), garante índice sem esperar publicação completa.
  static Future<void> syncOnDomainActivated({
    required String lojaId,
    required String dominioUserNormalized,
  }) async {
    final domNorm = normalizeCatalogDomainInput(dominioUserNormalized);
    if (domNorm.isEmpty) return;
    final hosts = catalogDomainIndexDocIdsForConfig(domNorm);
    await _writeActiveForHosts(
      lojaId: lojaId,
      dominioDisplay: domNorm,
      hosts: hosts,
    );
  }
}
