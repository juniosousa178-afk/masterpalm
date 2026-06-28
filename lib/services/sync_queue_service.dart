// lib/services/sync_queue_service.dart
//
// Fila de sincronização offline-first com retry e persistência.
// Garante consistência Hive ↔ Firestore sem perda de dados.
//
// Uso: Após gravar em Hive, chame enqueue(). O processamento ocorre
// em background ou quando a rede voltar.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:hive/hive.dart';

import '../core/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/fornecedor.dart';
import 'clientes_firestore_service.dart';
import 'vendas_firestore_service.dart';
import 'produto_sync_erro_util.dart';
import 'produtos_firestore_service.dart';
import 'fornecedores_firestore_service.dart';
import 'catalogo_live_inline_policy.dart';
import 'catalogo_queue_publish_plan.dart';
import 'catalogo_sync_attempt_context.dart';
import 'produto_cadastro_pos_save_service.dart';

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

  /// Após [SyncQueueService._maxAttempts] falhas: não processar em loop automático;
  /// item permanece na box para auditoria / [SyncQueueService.retryItem].
  final bool deadLetter;

  /// Última vez que houve tentativa falha (ms epoch). 0 = nunca registrado.
  final int lastAttemptAt;

  /// Plano de publicação do catálogo (retrocompat: ausente → legadoInline).
  final CatalogoQueuePublishPlan catalogoPublishPlan;

  /// Fase da máquina de estados canônica (retrocompat: ausente → aguardandoEstoque).
  final CatalogoQueuePublishPhase catalogoPublishPhase;

  /// Origem sanitizada do enfileiramento (ex.: produto_form.save).
  final String? catalogoQueueSourceOrigin;

  SyncQueueItem({
    required this.id,
    required this.type,
    required this.lojaId,
    required this.boxName,
    required this.entityKey,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastError,
    this.deadLetter = false,
    this.lastAttemptAt = 0,
    this.catalogoPublishPlan = CatalogoQueuePublishPlan.legadoInline,
    this.catalogoPublishPhase = CatalogoQueuePublishPhase.aguardandoEstoque,
    this.catalogoQueueSourceOrigin,
  });

  SyncQueueItem copyWith({
    int? attemptCount,
    String? lastError,
    bool? deadLetter,
    int? lastAttemptAt,
    CatalogoQueuePublishPlan? catalogoPublishPlan,
    CatalogoQueuePublishPhase? catalogoPublishPhase,
    String? catalogoQueueSourceOrigin,
  }) {
    return SyncQueueItem(
      id: id,
      type: type,
      lojaId: lojaId,
      boxName: boxName,
      entityKey: entityKey,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      deadLetter: deadLetter ?? this.deadLetter,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      catalogoPublishPlan: catalogoPublishPlan ?? this.catalogoPublishPlan,
      catalogoPublishPhase:
          catalogoPublishPhase ?? this.catalogoPublishPhase,
      catalogoQueueSourceOrigin:
          catalogoQueueSourceOrigin ?? this.catalogoQueueSourceOrigin,
    );
  }

  bool get isCatalogoCanonicoAposEstoque =>
      catalogoPublishPlan == CatalogoQueuePublishPlan.canonicoAposEstoque;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.index,
        'lojaId': lojaId,
        'boxName': boxName,
        'entityKey': entityKey,
        'createdAt': createdAt,
        'attemptCount': attemptCount,
        'lastError': lastError,
        'deadLetter': deadLetter,
        'lastAttemptAt': lastAttemptAt,
        'catalogoPublishPlan': catalogoPublishPlan.index,
        'catalogoPublishPhase': catalogoPublishPhase.index,
        if (catalogoQueueSourceOrigin != null)
          'catalogoQueueSourceOrigin': catalogoQueueSourceOrigin,
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
        deadLetter: m['deadLetter'] == true,
        lastAttemptAt: (m['lastAttemptAt'] as num?)?.toInt() ?? 0,
        catalogoPublishPlan: CatalogoQueuePublishPlan
            .values[(m['catalogoPublishPlan'] as int?) ?? 0],
        catalogoPublishPhase: CatalogoQueuePublishPhase
            .values[(m['catalogoPublishPhase'] as int?) ?? 0],
        catalogoQueueSourceOrigin:
            m['catalogoQueueSourceOrigin'] as String?,
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
  static int _deferProcessDepth = 0;
  static String? _pendingProcessScopeLojaId;
  static int _processRequestCount = 0;

  /// Contagem de [requestProcessWhenOnline] (somente testes).
  @visibleForTesting
  static int get debugProcessRequestCount => _processRequestCount;

  @visibleForTesting
  static int debugCanonicalPhaseEstoqueRuns = 0;

  @visibleForTesting
  static int debugCanonicalPhaseDraftRuns = 0;

  @visibleForTesting
  static int debugCanonicalPhaseLiveRuns = 0;

  @visibleForTesting
  static void resetCanonicalPhaseCountersForTests() {
    debugCanonicalPhaseEstoqueRuns = 0;
    debugCanonicalPhaseDraftRuns = 0;
    debugCanonicalPhaseLiveRuns = 0;
  }

  @visibleForTesting
  static void resetProcessRequestCountForTests() {
    _processRequestCount = 0;
    _pendingProcessScopeLojaId = null;
    _deferProcessDepth = 0;
  }

  /// Enfileira várias operações sem disparar processamento até o fim do lote.
  static Future<T> runWithDeferredQueueProcessing<T>(
    Future<T> Function() action,
  ) async {
    _deferProcessDepth++;
    try {
      return await action();
    } finally {
      _deferProcessDepth--;
    }
  }

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
    String? lastError,
    bool scheduleProcess = true,
    CatalogoQueuePublishPlan catalogoPublishPlan =
        CatalogoQueuePublishPlan.legadoInline,
    CatalogoQueuePublishPhase catalogoPublishPhase =
        CatalogoQueuePublishPhase.aguardandoEstoque,
    String? catalogoQueueSourceOrigin,
  }) async {
    await _instance._enqueue(
      type,
      lojaId,
      boxName,
      entityKey,
      lastError: lastError,
      scheduleProcess: scheduleProcess,
      catalogoPublishPlan: catalogoPublishPlan,
      catalogoPublishPhase: catalogoPublishPhase,
      catalogoQueueSourceOrigin: catalogoQueueSourceOrigin,
    );
  }

  /// Último [SyncQueueItem.lastError] de produto pendente para a entidade (cadastro/diagnóstico).
  static Future<String?> lastProdutoSyncErrorForEntity({
    required String lojaId,
    required int entityKey,
  }) async {
    await _instance._ensureBox();
    final box = _instance._box!;
    String? melhor;
    var melhorMs = 0;
    for (final k in box.keys) {
      final map = _instance._rawToMap(box.get(k));
      if (map == null) continue;
      final item = SyncQueueItem.fromMap(map);
      if (item.type != SyncOperationType.upsertProduto) continue;
      if (item.lojaId != lojaId) continue;
      if (item.entityKey != entityKey) continue;
      final err = item.lastError?.trim();
      if (err == null || err.isEmpty) continue;
      final ms =
          item.lastAttemptAt > 0 ? item.lastAttemptAt : item.createdAt;
      if (ms >= melhorMs) {
        melhorMs = ms;
        melhor = err;
      }
    }
    return melhor;
  }

  Future<void> _enqueue(
    SyncOperationType type,
    String lojaId,
    String boxName,
    int entityKey, {
    String? lastError,
    bool scheduleProcess = true,
    CatalogoQueuePublishPlan catalogoPublishPlan =
        CatalogoQueuePublishPlan.legadoInline,
    CatalogoQueuePublishPhase catalogoPublishPhase =
        CatalogoQueuePublishPhase.aguardandoEstoque,
    String? catalogoQueueSourceOrigin,
  }) async {
    await _ensureBox();
    final box = _box!;

    final id = '${type.name}_${lojaId}_${entityKey}_${DateTime.now().millisecondsSinceEpoch}';
    final errInicial = lastError != null && lastError.trim().isNotEmpty
        ? SyncQueueService._truncateError(lastError.trim())
        : null;
    final item = SyncQueueItem(
      id: id,
      type: type,
      lojaId: lojaId,
      boxName: boxName,
      entityKey: entityKey,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      deadLetter: false,
      lastAttemptAt: 0,
      lastError: errInicial,
      catalogoPublishPlan: catalogoPublishPlan,
      catalogoPublishPhase: catalogoPublishPhase,
      catalogoQueueSourceOrigin: catalogoQueueSourceOrigin,
    );

    await box.put(id, jsonEncode(item.toMap()));
    logD(
      '📋 [SYNC-QUEUE] Enfileirado: $type key=$entityKey'
      '${errInicial != null ? " lastError=$errInicial" : ""}',
    );

    if (scheduleProcess) {
      _maybeScheduleProcess();
    }
  }

  void _maybeScheduleProcess() {
    if (_deferProcessDepth > 0) return;
    _scheduleProcess();
  }

  /// Agenda processamento (debounce)
  void _scheduleProcess() {
    Future.delayed(const Duration(milliseconds: 800), () {
      processPending();
    });
  }

  /// Solicita processamento da fila após lote — escopo explícito de loja.
  static void requestProcessWhenOnline({required String lojaId}) {
    final scoped = lojaId.trim();
    if (scoped.isEmpty) return;
    _processRequestCount++;
    _pendingProcessScopeLojaId = scoped;
    _instance._scheduleScopedProcess();
  }

  void _scheduleScopedProcess() {
    Future.delayed(const Duration(milliseconds: 800), () async {
      final scope = _pendingProcessScopeLojaId;
      _pendingProcessScopeLojaId = null;
      await processPending(scopeLojaId: scope);
    });
  }

  /// Enfileira upsert de produto substituindo entradas anteriores da mesma entityKey.
  static Future<void> enqueueProdutoUnico({
    required String lojaId,
    required String boxName,
    required int entityKey,
    String? lastError,
    bool scheduleProcess = true,
  }) async {
    await _instance._ensureBox();
    final box = _instance._box!;
    final toDelete = <dynamic>[];
    for (final k in box.keys) {
      final map = _instance._rawToMap(box.get(k));
      if (map == null) continue;
      final item = SyncQueueItem.fromMap(map);
      if (item.type != SyncOperationType.upsertProduto) continue;
      if (item.lojaId != lojaId) continue;
      if (item.entityKey != entityKey) continue;
      toDelete.add(k);
    }
    for (final k in toDelete) {
      await box.delete(k);
    }
    await _instance._enqueue(
      SyncOperationType.upsertProduto,
      lojaId,
      boxName,
      entityKey,
      lastError: lastError,
      scheduleProcess: scheduleProcess,
    );
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

  /// Processa operações pendentes. Com [scopeLojaId], ignora itens de outras lojas.
  static Future<SyncQueueResult> processPending({String? scopeLojaId}) async {
    return _instance._processPending(scopeLojaId: scopeLojaId);
  }

  /// Verifica se existe item pendente/dead-letter para uma entidade específica.
  /// Usado como guard para evitar pull remoto sobrescrever alteração local ainda não confirmada.
  static Future<bool> hasPendingEntity({
    required SyncOperationType type,
    required String lojaId,
    required int entityKey,
    bool includeDeadLetter = true,
  }) async {
    await _instance._ensureBox();
    for (final k in _instance._box!.keys) {
      final map = _instance._rawToMap(_instance._box!.get(k));
      if (map == null) continue;
      final item = SyncQueueItem.fromMap(map);
      if (item.type != type) continue;
      if (item.lojaId != lojaId) continue;
      if (item.entityKey != entityKey) continue;
      if (!includeDeadLetter && item.deadLetter) continue;
      return true;
    }
    return false;
  }

  /// Atalho para o tipo mais crítico no estoque.
  static Future<bool> hasPendingProdutoSync({
    required String lojaId,
    required int entityKey,
    bool includeDeadLetter = true,
  }) {
    return hasPendingEntity(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaId,
      entityKey: entityKey,
      includeDeadLetter: includeDeadLetter,
    );
  }

  /// Existe qualquer sync pendente de produto para a loja.
  /// Usado para bloquear pull remoto até confirmar alterações locais.
  static Future<bool> hasPendingProdutoSyncForStore({
    required String lojaId,
    bool includeDeadLetter = true,
  }) async {
    await _instance._ensureBox();
    for (final k in _instance._box!.keys) {
      final map = _instance._rawToMap(_instance._box!.get(k));
      if (map == null) continue;
      final item = SyncQueueItem.fromMap(map);
      if (item.type != SyncOperationType.upsertProduto) continue;
      if (item.lojaId != lojaId) continue;
      if (!includeDeadLetter && item.deadLetter) continue;
      return true;
    }
    return false;
  }

  Future<SyncQueueResult> _processPending({String? scopeLojaId}) async {
    if (_isProcessing) {
      // Outro ciclo em andamento: reagendar para não perder itens recém-enfileirados (ex.: cadastro web).
      _scheduleProcess();
      return SyncQueueResult(
        processed: 0,
        failed: 0,
        skipped: 0,
        deadLetterSkipped: 0,
      );
    }

    await _ensureBox();
    final box = _box!;

    if (box.isEmpty) {
      return SyncQueueResult(
        processed: 0,
        failed: 0,
        skipped: 0,
        deadLetterSkipped: 0,
      );
    }

    _isProcessing = true;
    int processed = 0;
    int failed = 0;
    int skipped = 0;
    int deadLetterSkipped = 0;

    try {
      final keys = box.keys.map((k) => k.toString()).toList();
      logD('[SYNC_QUEUE] process_start keys=${keys.length}');
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
          if (scopeLojaId != null &&
              scopeLojaId.isNotEmpty &&
              item.lojaId != scopeLojaId) {
            skipped++;
            continue;
          }
          if (item.deadLetter) {
            deadLetterSkipped++;
            logD(
              '[SYNC_QUEUE] item_preserved_for_retry (dead-letter, skip auto) operationId=${item.operationId}',
            );
            continue;
          }

          final result = await _executeItem(item);

          if (result) {
            await box.delete(key);
            logD(
              '[SYNC_QUEUE] item_removed_after_success operationId=${item.operationId}',
            );
            processed++;
          } else {
            skipped++;
          }
        } catch (e, st) {
          logE(
            '[SYNC_QUEUE] process_error (type=${e.runtimeType})',
            error: e,
            st: st,
          );
          failed++;
        }
      }

      return SyncQueueResult(
        processed: processed,
        failed: failed,
        skipped: skipped,
        deadLetterSkipped: deadLetterSkipped,
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

  static String _truncateError(String error) {
    final t = error.trim();
    if (t.length <= 220) return t;
    return '${t.substring(0, 220)}…';
  }

  Future<void> _incrementAttempt(SyncQueueItem item, String error) async {
    await _ensureBox();
    if (item.deadLetter) return;

    final next = (item.attemptCount + 1).clamp(0, _maxAttempts);
    final justMarkedDead = next >= _maxAttempts;
    final err = _truncateError(error);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final updated = item.copyWith(
      attemptCount: next,
      lastError: err,
      deadLetter: justMarkedDead,
      lastAttemptAt: nowMs,
    );
    await _box!.put(item.id, jsonEncode(updated.toMap()));
    if (justMarkedDead) {
      logE(
        '[SYNC_QUEUE] max_attempts_reached operationId=${item.operationId} attempts=$next',
      );
      logE(
        '[SYNC_QUEUE] item_marked_failed id=${item.id} type=${item.type.name} — preservado (dead-letter). Reativar: SyncQueueService.retryDeadLetter',
      );
    }
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

    if (item.isCatalogoCanonicoAposEstoque) {
      return _executeUpsertProdutoCanonico(item, produto);
    }
    return _executeUpsertProdutoLegado(item, produto);
  }

  Future<bool> _executeUpsertProdutoLegado(
    SyncQueueItem item,
    Produto produto,
  ) async {
    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      produto,
      lojaId: item.lojaId,
      bumpHiveTimestamp: false,
      writeOrigin: 'sync_queue.upsert_produto',
      enqueueOnFailure: false,
    );
    return _tratarStatusEstoqueFila(item, status);
  }

  Future<bool> _executeUpsertProdutoCanonico(
    SyncQueueItem item,
    Produto produto,
  ) async {
    final diagContext = await CatalogoSyncAttemptContext.captureForQueueRetry(
      lojaId: item.lojaId,
    );

    var current = item;

    if (current.catalogoPublishPhase ==
        CatalogoQueuePublishPhase.aguardandoEstoque) {
      debugCanonicalPhaseEstoqueRuns++;
      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        produto,
        lojaId: item.lojaId,
        bumpHiveTimestamp: false,
        writeOrigin: 'sync_queue.upsert_produto.canonical',
        enqueueOnFailure: false,
        catalogoLiveInlinePolicy:
            CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
        catalogoDiagContext: diagContext,
      );
      final ok = await _tratarStatusEstoqueFila(current, status);
      if (!ok) return false;
      current = await _persistCatalogoPhase(
        current,
        CatalogoQueuePublishPhase.aguardandoDraft,
      );
    }

    if (current.catalogoPublishPhase ==
        CatalogoQueuePublishPhase.aguardandoDraft) {
      debugCanonicalPhaseDraftRuns++;
      ProdutosFirestoreService.limparFalhasUpsertCatalogo();
      final draft = await ProdutoCadastroPosSaveService.sincronizarDraftCanonical(
        produto: produto,
        lojaId: item.lojaId,
        catalogoDiagContext: diagContext,
      );
      if (!draft.sucesso) {
        await _incrementAttempt(
          current,
          draft.erroSanitizado ?? 'upsert_draft_produtos falhou',
        );
        logW(
          '⚠️ [SYNC-QUEUE] draft canônico pendente (phase=aguardandoDraft, operationId=${item.operationId})',
        );
        return false;
      }
      current = await _persistCatalogoPhase(
        current,
        CatalogoQueuePublishPhase.aguardandoLive,
      );
    }

    if (current.catalogoPublishPhase ==
        CatalogoQueuePublishPhase.aguardandoLive) {
      debugCanonicalPhaseLiveRuns++;
      ProdutosFirestoreService.limparFalhasUpsertCatalogo();
      final live = await ProdutoCadastroPosSaveService.sincronizarLiveCanonical(
        produto: produto,
        lojaId: item.lojaId,
        catalogoDiagContext: diagContext,
      );
      if (!live.sucesso) {
        await _incrementAttempt(
          current,
          live.erroSanitizado ?? 'upsert_produtos_live falhou',
        );
        logW(
          '⚠️ [SYNC-QUEUE] live canônico pendente (phase=aguardandoLive, operationId=${item.operationId})',
        );
        return false;
      }
      logD(
        '[SYNC-QUEUE] canonical_catalog_publish_complete operationId=${item.operationId} '
        'source=${item.catalogoQueueSourceOrigin ?? "—"}',
      );
      return true;
    }

    return false;
  }

  Future<bool> _tratarStatusEstoqueFila(
    SyncQueueItem item,
    ProdutoSyncRemotoStatus status,
  ) async {
    if (status == ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone) {
      final tombErr = ProdutoSyncErroUtil.sanitizar(
        null,
        status: ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone,
      );
      await _incrementAttempt(
        item,
        tombErr ?? 'identificador-excluido (tombstone)',
      );
      logD(
        '[TOMBSTONE_BLOCK] fila manteve item (entityKey=${item.entityKey}) — tombstone',
        tag: 'TOMBSTONE',
      );
      return false;
    }
    if (status == ProdutoSyncRemotoStatus.recuperacaoManualNecessaria) {
      final msg = ProdutosFirestoreService.ultimoErroSyncSanitizado ??
          'recuperacao-manual-necessaria';
      await _incrementAttempt(item, msg);
      logW(
        '⚠️ [SYNC-QUEUE] Produto requer recuperação manual (entityKey=${item.entityKey})',
      );
      return false;
    }
    if (status != ProdutoSyncRemotoStatus.confirmado &&
        status != ProdutoSyncRemotoStatus.semMudancas) {
      final detalhe = ProdutosFirestoreService.ultimoErroSyncSanitizado ??
          ProdutoSyncErroUtil.sanitizar(null, status: status) ??
          'syncProdutoComStatus=$status';
      await _incrementAttempt(item, detalhe);
      logW(
        '⚠️ [SYNC-QUEUE] Produto pendente sem ACK remoto (status=$status, operationId=${item.operationId})',
      );
      return false;
    }
    return true;
  }

  Future<SyncQueueItem> _persistCatalogoPhase(
    SyncQueueItem item,
    CatalogoQueuePublishPhase phase,
  ) async {
    await _ensureBox();
    final updated = item.copyWith(catalogoPublishPhase: phase);
    await _box!.put(item.id, jsonEncode(updated.toMap()));
    logD(
      '[SYNC-QUEUE] catalogo_phase=$phase operationId=${item.operationId}',
    );
    return updated;
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

  /// Pendentes ainda elegíveis ao processamento automático (não dead-letter).
  static Future<int> activePendingCount() async {
    final m = await getMetrics();
    return m.activePending;
  }

  /// Itens em dead-letter (falha após max tentativas), ainda persistidos.
  static Future<int> deadLetterCount() async {
    final m = await getMetrics();
    return m.deadLetter;
  }

  /// Contagens separadas: ativos, falhas preservadas, total.
  static Future<SyncQueueMetrics> getMetrics() async {
    await _instance._ensureBox();
    final box = _instance._box!;
    var active = 0;
    var dead = 0;
    for (final k in box.keys) {
      final map = _instance._rawToMap(box.get(k));
      if (map == null) continue;
      final it = SyncQueueItem.fromMap(map);
      if (it.deadLetter) {
        dead++;
      } else {
        active++;
      }
    }
    return SyncQueueMetrics(
      activePending: active,
      deadLetter: dead,
      total: box.length,
    );
  }

  /// Lista resumida para diagnóstico (ordenada: mais recentes primeiro).
  static Future<List<SyncQueueDiagnosticEntry>> listDiagnosticEntries() async {
    await _instance._ensureBox();
    final box = _instance._box!;
    final out = <SyncQueueDiagnosticEntry>[];
    for (final k in box.keys) {
      final id = k.toString();
      final map = _instance._rawToMap(box.get(k));
      if (map == null) continue;
      final it = SyncQueueItem.fromMap(map);
      out.add(
        SyncQueueDiagnosticEntry(
          id: id,
          type: it.type,
          lojaId: it.lojaId,
          entityKey: it.entityKey,
          attemptCount: it.attemptCount,
          deadLetter: it.deadLetter,
          lastError: it.lastError,
          createdAtMs: it.createdAt,
          lastAttemptAtMs: it.lastAttemptAt,
        ),
      );
    }
    out.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return out;
  }

  Map<String, dynamic>? _rawToMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return null;
      }
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Reprocessar um item: zera tentativas, remove dead-letter e reagenda sync.
  /// Funciona para falha preservada ou pendente com erros anteriores.
  static Future<bool> retryItem(String id) async {
    await _instance._ensureBox();
    final raw = _instance._box!.get(id);
    final map = _instance._rawToMap(raw);
    if (map == null) return false;
    final item = SyncQueueItem.fromMap(map);
    final reset = item.copyWith(
      attemptCount: 0,
      lastError: null,
      deadLetter: false,
      lastAttemptAt: 0,
    );
    await _instance._box!.put(id, jsonEncode(reset.toMap()));
    logD(
      '[SYNC_QUEUE] retry_manual_iniciado id=$id operationId=${item.operationId} era_dead=${item.deadLetter}',
    );
    _instance._scheduleProcess();
    return true;
  }

  /// Compatível com código anterior: mesmo comportamento que [retryItem].
  static Future<bool> retryDeadLetter(String id) => retryItem(id);

  /// Reprocessa todos os itens em dead-letter (sem duplicar chaves).
  static Future<int> retryAllDeadLetters() async {
    await _instance._ensureBox();
    logD('[SYNC_QUEUE] retry_lote_iniciado (dead-letters)');
    final ids = <String>[];
    for (final k in _instance._box!.keys) {
      final map = _instance._rawToMap(_instance._box!.get(k));
      if (map == null) continue;
      if (SyncQueueItem.fromMap(map).deadLetter) {
        ids.add(k.toString());
      }
    }
    var n = 0;
    for (final id in ids) {
      if (await retryItem(id)) n++;
    }
    logD('[SYNC_QUEUE] retry_lote_concluido reativados=$n');
    return n;
  }

  /// Espelha [_incrementAttempt] sem I/O — regressão de dead-letter / max tentativas.
  @visibleForTesting
  static SyncQueueItem simulateStateAfterFailedAttempt(
    SyncQueueItem item, {
    int maxAttempts = 5,
  }) {
    if (item.deadLetter) return item;
    final next = (item.attemptCount + 1).clamp(0, maxAttempts);
    final justMarkedDead = next >= maxAttempts;
    return SyncQueueItem(
      id: item.id,
      type: item.type,
      lojaId: item.lojaId,
      boxName: item.boxName,
      entityKey: item.entityKey,
      createdAt: item.createdAt,
      attemptCount: next,
      lastError: item.lastError,
      deadLetter: justMarkedDead,
      lastAttemptAt: item.lastAttemptAt,
      catalogoPublishPlan: item.catalogoPublishPlan,
      catalogoPublishPhase: item.catalogoPublishPhase,
      catalogoQueueSourceOrigin: item.catalogoQueueSourceOrigin,
    );
  }

  /// Remove um item da fila (só a entrada de sync; não apaga venda/cliente no Hive).
  static Future<bool> removeItem(String id) async {
    await _instance._ensureBox();
    if (!_instance._box!.containsKey(id)) return false;
    await _instance._box!.delete(id);
    logW('[SYNC_QUEUE] limpeza_manual_item id=$id');
    return true;
  }

  /// Remove apenas entradas em dead-letter (confirmação na UI).
  static Future<int> clearDeadLetterItems() async {
    await _instance._ensureBox();
    logW('[SYNC_QUEUE] limpeza_manual_dead_letters_iniciada');
    final ids = <String>[];
    for (final k in _instance._box!.keys) {
      final map = _instance._rawToMap(_instance._box!.get(k));
      if (map == null) continue;
      if (SyncQueueItem.fromMap(map).deadLetter) {
        ids.add(k.toString());
      }
    }
    for (final id in ids) {
      await _instance._box!.delete(id);
    }
    logW('[SYNC_QUEUE] limpeza_manual_dead_letters removidos=${ids.length}');
    return ids.length;
  }

  /// Limpa a fila (usar com cuidado)
  static Future<void> clearQueue() async {
    await _instance._ensureBox();
    logW('[SYNC_QUEUE] limpeza_manual_fila_completa');
    await _instance._box!.clear();
  }

  /// Localiza item de produto na fila (somente testes/diagnóstico).
  @visibleForTesting
  static Future<SyncQueueItem?> findProdutoQueueItem({
    required String lojaId,
    required int entityKey,
  }) async {
    await _instance._ensureBox();
    for (final k in _instance._box!.keys) {
      final map = _instance._rawToMap(_instance._box!.get(k));
      if (map == null) continue;
      final it = SyncQueueItem.fromMap(map);
      if (it.type != SyncOperationType.upsertProduto) continue;
      if (it.lojaId != lojaId) continue;
      if (it.entityKey != entityKey) continue;
      return it;
    }
    return null;
  }
}

/// Contagens para painel de diagnóstico.
class SyncQueueMetrics {
  final int activePending;
  final int deadLetter;
  final int total;

  const SyncQueueMetrics({
    required this.activePending,
    required this.deadLetter,
    required this.total,
  });
}

/// Linha resumida para UI (sem payload de entidade).
class SyncQueueDiagnosticEntry {
  final String id;
  final SyncOperationType type;
  final String lojaId;
  final int entityKey;
  final int attemptCount;
  final bool deadLetter;
  final String? lastError;
  final int createdAtMs;
  final int lastAttemptAtMs;

  const SyncQueueDiagnosticEntry({
    required this.id,
    required this.type,
    required this.lojaId,
    required this.entityKey,
    required this.attemptCount,
    required this.deadLetter,
    required this.lastError,
    required this.createdAtMs,
    required this.lastAttemptAtMs,
  });

  String get typeLabel => type.name;
}

/// Resultado do processamento
class SyncQueueResult {
  final int processed;
  final int failed;
  final int skipped;

  /// Itens em dead-letter ignorados neste ciclo (não são erro; permanecem na box).
  final int deadLetterSkipped;

  SyncQueueResult({
    required this.processed,
    required this.failed,
    required this.skipped,
    this.deadLetterSkipped = 0,
  });

  @override
  String toString() =>
      'SyncQueueResult(processed: $processed, failed: $failed, skipped: $skipped, deadLetterSkipped: $deadLetterSkipped)';
}
