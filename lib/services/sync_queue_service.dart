// lib/services/sync_queue_service.dart
//
// Fila de sincronização offline-first com retry e persistência.
// Garante consistência Hive ↔ Firestore sem perda de dados.
//
// Uso: Após gravar em Hive, chame enqueue(). O processamento ocorre
// em background ou quando a rede voltar.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';

import '../core/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/fornecedor.dart';
import 'clientes_firestore_service.dart';
import 'vendas_firestore_service.dart';
import 'produtos_firestore_service.dart';
import 'fornecedores_firestore_service.dart';

/// Tipos de operação suportados
enum SyncOperationType {
  upsertCliente,
  upsertVenda,
  upsertProduto,
  upsertFornecedor,
}

/// Item da fila de sincronização (persistido no Hive)
class SyncQueueItem {
  final String id;
  final SyncOperationType type;
  final String lojaId;
  final String boxName;
  final int entityKey;
  final int createdAt;
  final int attemptCount;
  final String? lastError;

  SyncQueueItem({
    required this.id,
    required this.type,
    required this.lojaId,
    required this.boxName,
    required this.entityKey,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastError,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.index,
        'lojaId': lojaId,
        'boxName': boxName,
        'entityKey': entityKey,
        'createdAt': createdAt,
        'attemptCount': attemptCount,
        'lastError': lastError,
      };

  factory SyncQueueItem.fromMap(Map<String, dynamic> m) => SyncQueueItem(
        id: m['id'] as String,
        type: SyncOperationType.values[(m['type'] as int?) ?? 0],
        lojaId: m['lojaId'] as String,
        boxName: m['boxName'] as String,
        entityKey: m['entityKey'] as int,
        createdAt: m['createdAt'] as int,
        attemptCount: m['attemptCount'] as int? ?? 0,
        lastError: m['lastError'] as String?,
      );

  /// operationId para idempotência
  String get operationId => '${type.name}_${lojaId}_$entityKey';
}

/// Serviço de fila de sincronização com retry
class SyncQueueService {
  static const String _boxName = 'sync_queue';
  static const int _maxAttempts = 5;
  static const Duration _baseDelay = Duration(milliseconds: 500);
  static const Duration _maxDelay = Duration(seconds: 30);

  static final SyncQueueService _instance = SyncQueueService._internal();
  factory SyncQueueService() => _instance;
  SyncQueueService._internal();

  Box? _box;
  bool _isProcessing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Inicializa o serviço (chamar no app startup)
  static Future<void> init() async {
    await _instance._ensureBox();
  }

  Future<void> _ensureBox() async {
    if (_box != null && _box!.isOpen) return;
    _box = Hive.isBoxOpen(_boxName)
        ? Hive.box(_boxName)
        : await Hive.openBox(_boxName);
  }

  /// Enfileira operação para sincronização
  static Future<void> enqueue({
    required SyncOperationType type,
    required String lojaId,
    required String boxName,
    required int entityKey,
  }) async {
    await _instance._enqueue(type, lojaId, boxName, entityKey);
  }

  Future<void> _enqueue(
    SyncOperationType type,
    String lojaId,
    String boxName,
    int entityKey,
  ) async {
    await _ensureBox();
    final box = _box!;

    final id = '${type.name}_${lojaId}_${entityKey}_${DateTime.now().millisecondsSinceEpoch}';
    final item = SyncQueueItem(
      id: id,
      type: type,
      lojaId: lojaId,
      boxName: boxName,
      entityKey: entityKey,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await box.put(id, jsonEncode(item.toMap()));
    logD('📋 [SYNC-QUEUE] Enfileirado: $type key=$entityKey');

    _scheduleProcess();
  }

  /// Agenda processamento (debounce)
  void _scheduleProcess() {
    Future.delayed(const Duration(milliseconds: 800), () {
      processPending();
    });
  }

  static void Function()? _onReconnectCallback;

  /// Define callback executado quando a rede voltar (ex: AutoSyncService.syncEmBackground)
  static void setOnReconnect(void Function()? callback) {
    _onReconnectCallback = callback;
  }

  /// Inicia listener de conectividade para processar quando a rede voltar.
  /// Web: usa Connectivity (navigator.onLine via connectivity_plus_web).
  static void startConnectivityListener() {
    _instance._connectivitySub?.cancel();
    _instance._connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final hasConnection = results.any((r) =>
          r != ConnectivityResult.none);
      if (hasConnection) {
        logD('🌐 [SYNC-QUEUE] Rede detectada, processando fila...');
        processPending();
        _onReconnectCallback?.call();
      }
    });
    if (kIsWeb) {
      logD('🌐 [SYNC-QUEUE] Listener de conectividade ativo (web).');
    }
  }

  /// Para o listener
  static void stopConnectivityListener() {
    _instance._connectivitySub?.cancel();
    _instance._connectivitySub = null;
  }

  /// Processa todas as operações pendentes
  static Future<SyncQueueResult> processPending() async {
    return _instance._processPending();
  }

  Future<SyncQueueResult> _processPending() async {
    if (_isProcessing) {
      return SyncQueueResult(processed: 0, failed: 0, skipped: 0);
    }

    await _ensureBox();
    final box = _box!;

    if (box.isEmpty) {
      return SyncQueueResult(processed: 0, failed: 0, skipped: 0);
    }

    _isProcessing = true;
    int processed = 0;
    int failed = 0;
    int skipped = 0;

    try {
      final keys = box.keys.map((k) => k.toString()).toList();
      for (final key in keys) {
        try {
          final raw = box.get(key);
          if (raw == null) {
            await box.delete(key);
            continue;
          }
          final map = raw is String
              ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
              : raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : null;
          if (map == null) {
            await box.delete(key);
            continue;
          }

          final item = SyncQueueItem.fromMap(map);
          final result = await _executeItem(item);

          if (result) {
            await box.delete(key);
            processed++;
          } else if (item.attemptCount >= _maxAttempts) {
            logE('❌ [SYNC-QUEUE] Máximo de tentativas: ${item.operationId}');
            await box.delete(key);
            failed++;
          } else {
            skipped++;
          }
        } catch (e, st) {
          logE('❌ [SYNC-QUEUE] Erro ao processar (type=${e.runtimeType})', error: e, st: st);
          failed++;
        }
      }

      return SyncQueueResult(
        processed: processed,
        failed: failed,
        skipped: skipped,
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _executeItem(SyncQueueItem item) async {
    final delay = _backoff(item.attemptCount);
    await Future<void>.delayed(delay);

    try {
      switch (item.type) {
        case SyncOperationType.upsertCliente:
          return await _executeUpsertCliente(item);
        case SyncOperationType.upsertVenda:
          return await _executeUpsertVenda(item);
        case SyncOperationType.upsertProduto:
          return await _executeUpsertProduto(item);
        case SyncOperationType.upsertFornecedor:
          return await _executeUpsertFornecedor(item);
      }
    } catch (e, st) {
      logE('❌ [SYNC-QUEUE] Erro (type=${e.runtimeType})', error: e, st: st);
      await _incrementAttempt(item, e.toString());
      return false;
    }
  }

  Duration _backoff(int attempt) {
    final ms = _baseDelay.inMilliseconds * (1 << attempt.clamp(0, 6));
    return Duration(milliseconds: ms.clamp(0, _maxDelay.inMilliseconds));
  }

  Future<void> _incrementAttempt(SyncQueueItem item, String error) async {
    await _ensureBox();
    final updated = SyncQueueItem(
      id: item.id,
      type: item.type,
      lojaId: item.lojaId,
      boxName: item.boxName,
      entityKey: item.entityKey,
      createdAt: item.createdAt,
      attemptCount: item.attemptCount + 1,
      lastError: error,
    );
    await _box!.put(item.id, jsonEncode(updated.toMap()));
  }

  Future<bool> _executeUpsertCliente(SyncQueueItem item) async {
    final box = await Hive.openBox<Cliente>(item.boxName);
    final cliente = box.get(item.entityKey);

    if (cliente == null) {
      logW('⚠️ [SYNC-QUEUE] Cliente key=${item.entityKey} não encontrado no Hive');
      return true; // Remove da fila - entidade foi deletada
    }

    await ClientesFirestoreService.syncCliente(cliente, lojaId: item.lojaId);
    return true;
  }

  Future<bool> _executeUpsertVenda(SyncQueueItem item) async {
    final box = await Hive.openBox<Venda>(item.boxName);
    final venda = box.get(item.entityKey);

    if (venda == null) {
      logW('⚠️ [SYNC-QUEUE] Venda key=${item.entityKey} não encontrada no Hive');
      return true;
    }

    logD('📤 [SYNC-DEBUG] SyncQueue processando venda pendente → lojaId=${item.lojaId} | key=${item.entityKey} | cliente=${venda.clienteNome}');
    final ok = await VendasFirestoreService.syncVenda(venda, lojaId: item.lojaId, enqueueOnFailure: false);
    if (!ok) {
      // Falha de syncVenda: manter item na fila e registrar tentativa para backoff
      await _incrementAttempt(item, 'syncVenda retornou false para vendaKey=${item.entityKey}');
      logW('⚠️ [SYNC-QUEUE] syncVenda falhou para venda pendente (operationId=${item.operationId})');
      return false;
    }

    logD('✅ [SYNC-QUEUE] Venda pendente sincronizada com sucesso (operationId=${item.operationId})');
    return true;
  }

  Future<bool> _executeUpsertProduto(SyncQueueItem item) async {
    final box = await Hive.openBox<Produto>(item.boxName);
    final produto = box.get(item.entityKey);

    if (produto == null) {
      logW('⚠️ [SYNC-QUEUE] Produto key=${item.entityKey} não encontrado no Hive');
      return true;
    }

    await ProdutosFirestoreService.syncProduto(produto, lojaId: item.lojaId);
    return true;
  }

  Future<bool> _executeUpsertFornecedor(SyncQueueItem item) async {
    final box = await Hive.openBox<Fornecedor>(item.boxName);
    final fornecedor = box.get(item.entityKey);

    if (fornecedor == null) {
      logW('⚠️ [SYNC-QUEUE] Fornecedor key=${item.entityKey} não encontrado no Hive');
      return true;
    }

    await FornecedoresFirestoreService.syncFornecedor(fornecedor, lojaId: item.lojaId);
    return true;
  }

  /// Retorna quantidade de itens pendentes
  static Future<int> pendingCount() async {
    await _instance._ensureBox();
    return _instance._box!.length;
  }

  /// Limpa a fila (usar com cuidado)
  static Future<void> clearQueue() async {
    await _instance._ensureBox();
    await _instance._box!.clear();
  }
}

/// Resultado do processamento
class SyncQueueResult {
  final int processed;
  final int failed;
  final int skipped;

  SyncQueueResult({
    required this.processed,
    required this.failed,
    required this.skipped,
  });

  @override
  String toString() =>
      'SyncQueueResult(processed: $processed, failed: $failed, skipped: $skipped)';
}
