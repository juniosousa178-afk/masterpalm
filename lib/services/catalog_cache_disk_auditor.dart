// lib/services/catalog_cache_disk_auditor.dart
// Auditoria opcional do cache em disco do catálogo. ETAPA 22A. Não usado pelo app; utilitário apenas.
// Logs apenas em debug; nunca imprime cfg nem dados sensíveis.
//
// Exemplo (debug):
//   if (kEnableCatalogDiskCacheAuditLogs) {
//     await CatalogCacheDiskAuditor.auditLoja(lojaId, preview: false);
//   }

import '../core/logger.dart';
import 'catalog_cache_disk_store.dart';

class CatalogCacheDiskAuditor {
  CatalogCacheDiskAuditor._();

  static final CatalogCacheDiskStore _store = CatalogCacheDiskStore.instance;

  /// Audita o cache em disco para uma loja. LogD com updatedAtMs, ageSeconds, topKeysCount.
  /// Não imprime cfg. Se não existir cache: logW.
  static Future<void> auditLoja(String lojaId, {bool preview = false}) async {
    final result = await _store.readConfig(lojaId, preview: preview);
    if (result.cfg == null && result.updatedAtMs == null) {
      logW('[CACHE-DISK] Sem cache em disco', tag: 'CACHE-DISK');
      return;
    }
    final updatedAtMs = result.updatedAtMs ?• 0;
    final ageSeconds = (DateTime.now().millisecondsSinceEpoch - updatedAtMs) / 1000;
    final topKeysCount = result.cfg?.keys.length ?• 0;
    logD(
      '[CACHE-DISK] audit preview=$preview updatedAtMs=$updatedAtMs '
      'ageSeconds=${ageSeconds.toStringAsFixed(1)} cfgTopKeysCount=$topKeysCount',
      tag: 'CACHE-DISK',
    );
  }
}
