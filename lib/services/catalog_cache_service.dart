// lib/services/catalog_cache_service.dart
//
// Cache agressivo para o catálogo público.
// Reduz leituras Firestore: TTL em memória, get() em vez de snapshots().
// Mantém atualização automática ao expirar TTL.
//
// Uso: substituir _cfgStream e _produtosStream pelo CatalogCacheService.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import '../core/safe_cast.dart';
import 'catalog_cache_disk_store.dart';

/// Cache em memória para config e produtos do catálogo público.
/// TTL configurável; ao expirar, busca Firestore em background e emite.
class CatalogCacheService {
  CatalogCacheService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // TTL em segundos (aumentado para reduzir leituras Firestore em escala)
  static const int _configTtlSeconds = 600; // 10 min
  static const int _produtosTtlSeconds = 300; // 5 min

  // Cache em memória: lojaId -> (data, timestamp)
  static final Map<String, _CachedConfig> _configCache = {};
  static final Map<String, _CachedProdutos> _produtosCache = {};

  /// Stream de config com cache. Emite cache imediatamente se válido,
  /// depois busca Firestore. Atualização automática: refetch após TTL.
  /// ETAPA 19: sem while(true); usa StreamController + Timer.periodic; para ao cancelar.
  static Stream<Map<String, dynamic>> getConfigStream({
    required String lojaId,
    required bool preview,
    bool forceRefresh = false,
  }) {
    return _configStreamWithBackgroundRefresh(
      lojaId: lojaId,
      preview: preview,
      forceRefresh: forceRefresh,
    );
  }

  /*
   * LÓGICA ORIGINAL (antes da ETAPA 19):
   * - Fonte: Firestore lojas/{lojaId}/config|draft_config + payments + cupons (via _fetchConfig).
   * - Cache em memória: _configCache[cacheKey], TTL _configTtlSeconds (10 min).
   * - Se cache válido e !forceRefresh: emitia cache 1x e entrava em while(true) com
   *   Future.delayed(TTL) + _fetchConfig + yield se não vazio; em erro apenas logW (não reemitia).
   * - Senão: um fetch inicial (yield ou fallback do cache/{}), depois while(true) igual.
   * - Problema: while(true) nunca parava ao cancelar o listener (stream async* não cancelava o loop).
   */

  static final CatalogCacheDiskStore _disk = CatalogCacheDiskStore.instance;

  static Stream<Map<String, dynamic>> _configStreamWithBackgroundRefresh({
    required String lojaId,
    required bool preview,
    bool forceRefresh = false,
  }) {
    final cfgCol = preview • 'draft_config' : 'config';
    final cacheKey = '${lojaId}_$preview';
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    Timer• timer;
    Map<String, dynamic>• lastEmitted;
    const timeout = Duration(seconds: 10);
    const ttlMs = _configTtlSeconds * 1000;

    Future<void> tick() async {
      try {
        final cfg = await _fetchConfig(lojaId, cfgCol).timeout(timeout);
        if (cfg.isEmpty) return;
        _configCache[cacheKey] = _CachedConfig(cfg, DateTime.now());
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        _disk.writeConfig(lojaId, cfg, updatedAtMs: nowMs, preview: preview);
        bool isDifferent = true;
        if (lastEmitted != null) {
          try {
            isDifferent = jsonEncode(cfg) != jsonEncode(lastEmitted);
          } catch (_) {}
        }
        if (isDifferent && !controller.isClosed) {
          lastEmitted = cfg;
          controller.add(cfg);
        }
      } on TimeoutException catch (e) {
        logW('⚠️ [CACHE] Refresh config timeout (type=${e.runtimeType})');
      } catch (e) {
        logW('⚠️ [CACHE] Refresh config (type=${e.runtimeType})');
      }
    }

    void onListen() {
      if (!forceRefresh) {
        final cached = _configCache[cacheKey];
        if (cached != null && !cached.isExpired(_configTtlSeconds)) {
          logD('📦 [CACHE] Config servido do cache');
          lastEmitted = cached.data;
          controller.add(cached.data);
          timer = Timer.periodic(
            const Duration(seconds: _configTtlSeconds),
            (_) => tick(),
          );
          return;
        }
      }
      (() async {
        if (!forceRefresh) {
          final disk = await _disk.readConfig(lojaId, preview: preview);
          if (disk.cfg != null &&
              disk.updatedAtMs != null &&
              (DateTime.now().millisecondsSinceEpoch - disk.updatedAtMs!) <= ttlMs) {
            final inMemory = _configCache[cacheKey];
            if (inMemory == null || inMemory.isExpired(_configTtlSeconds)) {
              _configCache[cacheKey] =
                  _CachedConfig(disk.cfg!, DateTime.fromMillisecondsSinceEpoch(disk.updatedAtMs!));
              lastEmitted = disk.cfg;
              if (!controller.isClosed) {
                logD('📦 [CACHE] Config servido do disco');
                controller.add(disk.cfg!);
              }
              timer = Timer.periodic(
                const Duration(seconds: _configTtlSeconds),
                (_) => tick(),
              );
              return;
            }
          }
        }
        try {
          final cfg = await _fetchConfig(lojaId, cfgCol).timeout(timeout);
          if (cfg.isNotEmpty) {
            _configCache[cacheKey] = _CachedConfig(cfg, DateTime.now());
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            _disk.writeConfig(lojaId, cfg, updatedAtMs: nowMs, preview: preview);
            lastEmitted = cfg;
            if (!controller.isClosed) controller.add(cfg);
          } else if (!_configCache.containsKey(cacheKey) && !controller.isClosed) {
            controller.add({});
          }
        } catch (e) {
          logW('⚠️ [CACHE] Erro ao buscar config (type=${e.runtimeType})');
          final fallback = _configCache[cacheKey]?.data;
          if (!controller.isClosed) {
            if (fallback != null) {
              controller.add(fallback);
            } else {
              controller.add({});
            }
          }
        }
        timer = Timer.periodic(
          const Duration(seconds: _configTtlSeconds),
          (_) => tick(),
        );
      })();
    }

    void onCancel() {
      timer?.cancel();
      timer = null;
    }

    controller.onListen = onListen;
    controller.onCancel = onCancel;

    return controller.stream;
  }

  static Future<Map<String, dynamic>> _fetchConfig(
    String lojaId,
    String cfgCol,
  ) async {
    final baseRef = _db.collection('lojas').doc(lojaId);
    final configRef = baseRef.collection(cfgCol).doc('config');
    final paymentsRef = baseRef.collection(cfgCol).doc('payments');

    // Busca config e payments em paralelo (reduz latência)
    final results = await Future.wait([configRef.get(), paymentsRef.get()]);
    final cfgSnap = results[0];
    final paySnap = results[1];
    final data = cfgSnap.data();
    final cfg = asMap(data);

    try {
      if (paySnap.exists) {
        final payData = paySnap.data();
        cfg['payments'] = payData != null • asMap(payData) : null;
      }
    } catch (_) {}

    // Fallback cupons se config vazio
    final cuponsCfg = cfg['cupons'];
    if (cuponsCfg is! List || cuponsCfg.isEmpty) {
      try {
        final cuponsSnap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('cupons')
            .where('ativo', isEqualTo: true)
            .limit(30)
            .get()
            .timeout(const Duration(seconds: 3));

        final cuponsList = <Map<String, dynamic>>[];
        final now = DateTime.now();
        for (final doc in cuponsSnap.docs) {
          final raw = doc.data();
          final d = asMap(raw);
          final cod =
              (d['codigo'] ?• d['code'] ?• '').toString().toUpperCase().trim();
          if (cod.isEmpty) continue;
          final dataFim = d['dataFim'];
          if (dataFim != null) {
            final fim = asDateTime(dataFim);
            if (fim != null && now.isAfter(fim)) continue;
          }
          final tipoRaw = (d['tipo'] ?• 'percent').toString().toLowerCase();
          final tipoNorm = tipoRaw == 'valor' || tipoRaw == 'fixo'
              • 'valor'
              : tipoRaw.contains('frete')
                  • 'frete_gratis'
                  : 'percent';
          cuponsList.add({
            'codigo': cod,
            'tipo': tipoNorm,
            'ativo': true,
            'valor': (asNum(d['valor'])?.toDouble()) ?• 0.0,
            'aplicarEm': (d['aplicarEm'] ?• 'produtos').toString(),
            'freteGratis': d['freteGratis'] == true,
            'valorMinimo': asNum(d['valorMinimo'])?.toDouble(),
            'dataFim': dataFim,
            'validade': d['validade'],
            'dataValidade': d['dataValidade'],
          });
        }
        if (cuponsList.isNotEmpty) cfg['cupons'] = cuponsList;
      } catch (e) {
        logW('⚠️ [CACHE] Fallback cupons (type=${e.runtimeType})');
      }
    }

    return cfg;
  }

  /// Stream de produtos com cache. Mesmo padrão: cache primeiro, Firestore depois.
  /// Atualização automática: refetch após TTL.
  static Stream<QuerySnapshot<Map<String, dynamic>>> getProdutosStream({
    required String lojaId,
    required bool preview,
    bool forceRefresh = false,
  }) async* {
    final col = preview • 'draft_produtos' : 'produtos';
    final cacheKey = '${lojaId}_$col';

    // Se cache válido e não forçar refresh: emite 1x e pula fetch imediato (evita piscar)
    if (!forceRefresh) {
      final cached = _produtosCache[cacheKey];
      if (cached != null && !cached.isExpired(_produtosTtlSeconds)) {
        logD('📦 [CACHE] Produtos servidos do cache');
        yield cached.snapshot;
        // Vai direto para o loop TTL (evita 2ª emissão imediata)
        while (true) {
          await Future.delayed(const Duration(seconds: _produtosTtlSeconds));
          try {
            final snapshot = await _db
                .collection('lojas')
                .doc(lojaId)
                .collection(col)
                .where('ativo', isEqualTo: true)
                .limit(1000)
                .get();
            _produtosCache[cacheKey] = _CachedProdutos(snapshot, DateTime.now());
            yield snapshot;
          } catch (e) {
            logW('⚠️ [CACHE] Erro ao buscar produtos (type=${e.runtimeType})');
            final fallback = _produtosCache[cacheKey]?.snapshot;
            if (fallback != null) yield fallback;
          }
        }
      }
    }

    while (true) {
      try {
        final snapshot = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(col)
            .where('ativo', isEqualTo: true)
            .limit(1000)
            .get();

        _produtosCache[cacheKey] =
            _CachedProdutos(snapshot, DateTime.now());
        yield snapshot;
      } catch (e) {
        logW('⚠️ [CACHE] Erro ao buscar produtos (type=${e.runtimeType})');
        final fallback = _produtosCache[cacheKey]?.snapshot;
        if (fallback != null) yield fallback;
      }

      await Future.delayed(const Duration(seconds: _produtosTtlSeconds));
    }
  }

  /// Invalida cache para uma loja (ex.: após publicar na Loja Config ou pull-to-refresh).
  /// Limpa memória e disco para que o catálogo web busque config/produtos atualizados no Firestore.
  static void invalidate(String lojaId, {bool preview = false}) {
    _configCache.remove('${lojaId}_$preview');
    _produtosCache
        .remove('${lojaId}_${preview • 'draft_produtos' : 'produtos'}');
    // Crítico: limpar disco também — senão o catálogo continua servindo config antiga do disco
    _disk.clear(lojaId, preview: preview);
    logD('🔄 [CACHE] Cache invalidado (memória + disco)');
  }

  /// Limpa todo o cache (ex.: ao sair do catálogo).
  static void clearAll() {
    _configCache.clear();
    _produtosCache.clear();
    logD('🧹 [CACHE] Cache limpo');
  }
}

class _CachedConfig {
  final Map<String, dynamic> data;
  final DateTime cachedAt;

  _CachedConfig(this.data, this.cachedAt);

  bool isExpired(int ttlSeconds) {
    return DateTime.now().difference(cachedAt).inSeconds > ttlSeconds;
  }
}

class _CachedProdutos {
  final QuerySnapshot<Map<String, dynamic>> snapshot;
  final DateTime cachedAt;

  _CachedProdutos(this.snapshot, this.cachedAt);

  bool isExpired(int ttlSeconds) {
    return DateTime.now().difference(cachedAt).inSeconds > ttlSeconds;
  }
}
