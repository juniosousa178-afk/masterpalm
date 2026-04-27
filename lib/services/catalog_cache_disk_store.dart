// lib/services/catalog_cache_disk_store.dart
// Persistência em disco (Hive) do config do catálogo por lojaId. ETAPA 21 (zero risco).
// Somente CONFIG; tipos JSON-safe; TTL validado pelo caller.
// Hardening: flag kEnableCatalogDiskCacheSanitize remove chaves sensíveis apenas no disco.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../core/feature_flags.dart';
import '../core/logger.dart';
import '../core/safe_cast.dart';

/// Chaves sensíveis a remover do disco (case-insensitive). Apenas quando flag ON.
const Set<String> _bannedDiskKeys = {
  'access_token',
  'refresh_token',
  'private_key',
  'secret',
  'api_key',
  'token',
  'bearer',
  'authorization',
  'client_secret',
  'mp_access_token',
  'mercadopago_access_token',
};

const String _boxName = 'catalog_cache_disk';

String _cfgKey(String lojaId, bool preview) => 'cfg:${lojaId}_$preview';
String _metaKey(String lojaId, bool preview) => 'meta:${lojaId}_$preview';

/// Deep remove: remove chaves cujo nome (lowercase) está em [bannedLowerKeys].
/// Retorna (valor sanitizado, quantidade de chaves removidas).
({dynamic value, int removed}) _deepRemoveKeys(
  dynamic value,
  Set<String> bannedLowerKeys,
) {
  if (value == null) return (value: null, removed: 0);
  if (value is num || value is bool || value is String) {
    return (value: value, removed: 0);
  }
  if (value is Map) {
    int count = 0;
    final out = <String, dynamic>{};
    for (final e in value.entries) {
      final k = e.key.toString();
      if (bannedLowerKeys.contains(k.toLowerCase())) {
        count++;
        continue;
      }
      final r = _deepRemoveKeys(e.value, bannedLowerKeys);
      out[k] = r.value;
      count += r.removed;
    }
    return (value: out, removed: count);
  }
  if (value is List) {
    int count = 0;
    final out = <dynamic>[];
    for (final v in value) {
      final r = _deepRemoveKeys(v, bannedLowerKeys);
      out.add(r.value);
      count += r.removed;
    }
    return (value: out, removed: count);
  }
  return (value: value, removed: 0);
}

/// Sanitiza config para disco: deep copy + remove chaves sensíveis.
/// Retorna (map sanitizado, quantidade removida). Só usado quando flag ON.
({Map<String, dynamic> cfg, int removed}) _sanitizeConfigForDisk(
  Map<String, dynamic> cfg,
) {
  final safe = _toJsonSafe(cfg);
  if (safe is! Map<String, dynamic>) return (cfg: {}, removed: 0);
  final r = _deepRemoveKeys(safe, _bannedDiskKeys);
  return (cfg: asMap(r.value), removed: r.removed);
}

/// Converte valor para tipos JSON-safe (Map/List/num/bool/String/null).
/// Timestamp/DateTime -> millis (int).
dynamic _toJsonSafe(dynamic value) {
  if (value == null) return null;
  if (value is num || value is bool || value is String) return value;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is Map) {
    return value
        .map<String, dynamic>((k, v) => MapEntry(k.toString(), _toJsonSafe(v)));
  }
  if (value is List) {
    return value.map<dynamic>(_toJsonSafe).toList();
  }
  return value.toString();
}

class CatalogCacheDiskStore {
  CatalogCacheDiskStore._();

  static final CatalogCacheDiskStore _instance = CatalogCacheDiskStore._();

  static CatalogCacheDiskStore get instance => _instance;

  Future<Box> _open() => Hive.openBox(_boxName);

  /// Persiste config no disco. Apenas tipos json-safe; [updatedAtMs] para TTL no leitor.
  /// Se kEnableCatalogDiskCacheSanitize: remove chaves sensíveis antes de gravar.
  Future<void> writeConfig(
    String lojaId,
    Map<String, dynamic> cfg, {
    required int updatedAtMs,
    bool preview = false,
  }) async {
    try {
      final box = await _open();
      Map<String, dynamic> safe;
      int removedCount = 0;
      if (kEnableCatalogDiskCacheSanitize) {
        final sanitized = _sanitizeConfigForDisk(cfg);
        safe = sanitized.cfg;
        removedCount = sanitized.removed;
        if (sanitized.removed > 0) {
          logW(
            '🔒 [CACHE-DISK] Config sanitizado para disco (removidos: ${sanitized.removed} keys)',
            tag: 'CACHE-DISK',
          );
        }
      } else {
        final s = _toJsonSafe(cfg);
        if (s is! Map<String, dynamic>) return;
        safe = s;
      }
      final jsonStr = jsonEncode(safe);
      await box.put(_cfgKey(lojaId, preview), jsonStr);
      await box.put(_metaKey(lojaId, preview), {
        'updatedAtMs': updatedAtMs,
        'schemaVersion': 1,
      });
      if (kEnableCatalogDiskCacheAuditLogs) {
        logD(
          '[CACHE-DISK] write_ok preview=$preview updatedAtMs=$updatedAtMs topKeys=${safe.keys.length}',
          tag: 'CACHE-DISK',
        );
        if (kEnableCatalogDiskCacheSanitize && removedCount > 0) {
          logD('[CACHE-DISK] write sanitized: removed $removedCount keys',
              tag: 'CACHE-DISK');
        }
      }
    } catch (e) {
      logW('[CACHE-DISK] writeConfig falhou (type=${e.runtimeType})',
          tag: 'CACHE-DISK');
    }
  }

  /// Lê config do disco. Retorna nulls se não existir ou erro.
  Future<({Map<String, dynamic>? cfg, int? updatedAtMs})> readConfig(
    String lojaId, {
    bool preview = false,
  }) async {
    try {
      final box = await _open();
      final jsonStr = box.get(_cfgKey(lojaId, preview));
      final meta = box.get(_metaKey(lojaId, preview));
      if (jsonStr == null || jsonStr is! String) {
        if (kEnableCatalogDiskCacheAuditLogs) {
          logD('[CACHE-DISK] read miss preview=$preview temCfg=false',
              tag: 'CACHE-DISK');
        }
        return (cfg: null, updatedAtMs: null);
      }
      final cfg = asMap(jsonDecode(jsonStr));
      final updatedAtMs = meta is Map
          ? (meta['updatedAtMs'] is num
              ? (meta['updatedAtMs'] as num).toInt()
              : int.tryParse('${meta['updatedAtMs'] ?? ''}'))
          : null;
      if (kEnableCatalogDiskCacheAuditLogs) {
        logD(
          '[CACHE-DISK] read_ok preview=$preview temCfg=${cfg.isNotEmpty} '
          'updatedAtMs=$updatedAtMs topKeys=${cfg.keys.length}',
          tag: 'CACHE-DISK',
        );
      }
      return (cfg: cfg.isEmpty ? null : cfg, updatedAtMs: updatedAtMs);
    } catch (e) {
      logW('[CACHE-DISK] readConfig falhou (type=${e.runtimeType})',
          tag: 'CACHE-DISK');
      return (cfg: null, updatedAtMs: null);
    }
  }

  Future<void> clear(String lojaId, {bool preview = false}) async {
    try {
      final box = await _open();
      await box.delete(_cfgKey(lojaId, preview));
      await box.delete(_metaKey(lojaId, preview));
    } catch (e) {
      logW('[CACHE-DISK] clear falhou (type=${e.runtimeType})',
          tag: 'CACHE-DISK');
    }
  }
}
