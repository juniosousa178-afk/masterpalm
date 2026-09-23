import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/client_build_identity.dart';
import 'diagnostic_enums.dart';
import 'diagnostic_sanitize.dart';

/// In-memory + optional sink operation trace (read-only diagnostic).
class DiagnosticTrace {
  DiagnosticTrace({
    required this.traceId,
    required this.storeId,
    required this.module,
    required this.operationType,
    DateTime? startedAt,
    Map<String, dynamic>? buildProof,
    List<Map<String, dynamic>>? stages,
  })  : startedAt = startedAt ?? DateTime.now().toUtc(),
        buildProof = Map<String, dynamic>.from(buildProof ?? clientBuildProofMap()),
        stages = stages ?? <Map<String, dynamic>>[];

  final String traceId;
  final String storeId;
  final DiagnosticModule module;
  final String operationType;
  final DateTime startedAt;
  final Map<String, dynamic> buildProof;
  final List<Map<String, dynamic>> stages;
  String? finalStage;
  bool aborted = false;
  bool completed = false;

  void stage(
    String name, {
    bool success = true,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? extra,
  }) {
    stages.add(sanitizeDiagnosticMap({
      'stage': name,
      'at': DateTime.now().toUtc().toIso8601String(),
      'success': success,
      if (error != null) 'errorType': error.runtimeType.toString(),
      if (error != null) 'error': error.toString(),
      if (stack != null) 'stackTop': truncateStack(stack, maxLines: 6),
      if (extra != null) 'extra': extra,
    }));
    finalStage = name;
  }

  void success(String name, {Map<String, dynamic>? extra}) =>
      stage(name, success: true, extra: extra);

  void error(
    String name,
    Object error, {
    StackTrace? stack,
    Map<String, dynamic>? extra,
  }) =>
      stage(name, success: false, error: error, stack: stack, extra: extra);

  void complete({bool aborted = false, String? stageName}) {
    this.aborted = aborted;
    completed = true;
    if (stageName != null) {
      stage(stageName, success: !aborted);
    }
  }

  Map<String, dynamic> toJson() => sanitizeDiagnosticMap({
        'traceId': traceId,
        'storeId': storeId,
        'module': module.wire,
        'operationType': operationType,
        'startedAt': startedAt.toIso8601String(),
        'finalStage': finalStage,
        'aborted': aborted,
        'completed': completed,
        'buildProof': buildProof,
        'stages': stages,
      });
}

/// Reusable tracing API: start / stage / success / error / complete.
class DiagnosticTraceService {
  DiagnosticTraceService._();

  static final Map<String, DiagnosticTrace> _byId = {};
  static final List<String> _order = [];
  static String? _activeTraceId;
  static const int _maxTraces = 100;

  @visibleForTesting
  static bool disablePersistence = false;

  static String? get activeTraceId => _activeTraceId;

  static DiagnosticTrace? get active =>
      _activeTraceId == null ? null : _byId[_activeTraceId!];

  static List<DiagnosticTrace> get tracesNewestFirst {
    final out = <DiagnosticTrace>[];
    for (var i = _order.length - 1; i >= 0; i--) {
      final t = _byId[_order[i]];
      if (t != null) out.add(t);
    }
    return out;
  }

  @visibleForTesting
  static void clearAll() {
    _byId.clear();
    _order.clear();
    _activeTraceId = null;
  }

  static DiagnosticTrace start({
    required String storeId,
    required DiagnosticModule module,
    required String operationType,
    String? traceId,
    Map<String, dynamic>? extra,
  }) {
    final id = (traceId != null && traceId.trim().isNotEmpty)
        ? traceId.trim()
        : const Uuid().v4();
    final t = DiagnosticTrace(
      traceId: id,
      storeId: storeId,
      module: module,
      operationType: operationType,
    );
    if (extra != null && extra.isNotEmpty) {
      t.stage('TRACE_START', extra: extra);
    }
    _upsert(t);
    _activeTraceId = id;
    if (kDebugMode) {
      debugPrint(
        '[DIAG-TRACE] start id=${id.substring(0, 8)} store=$storeId '
        'module=${module.wire} op=$operationType',
      );
    }
    return t;
  }

  static void stage(
    String name, {
    bool success = true,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? extra,
    String? traceId,
  }) {
    final t = _resolve(traceId);
    if (t == null) return;
    t.stage(name, success: success, error: error, stack: stack, extra: extra);
  }

  static void success(
    String name, {
    Map<String, dynamic>? extra,
    String? traceId,
  }) =>
      stage(name, success: true, extra: extra, traceId: traceId);

  static void error(
    String name,
    Object error, {
    StackTrace? stack,
    Map<String, dynamic>? extra,
    String? traceId,
  }) =>
      stage(
        name,
        success: false,
        error: error,
        stack: stack,
        extra: extra,
        traceId: traceId,
      );

  static void complete({
    bool aborted = false,
    String? stageName,
    String? traceId,
  }) {
    final t = _resolve(traceId);
    if (t == null) return;
    t.complete(aborted: aborted, stageName: stageName);
    if (_activeTraceId == t.traceId) _activeTraceId = null;
  }

  static List<Map<String, dynamic>> toDiagnosticSection({String? storeId}) {
    return tracesNewestFirst
        .where((t) => storeId == null || t.storeId == storeId)
        .map((t) => t.toJson())
        .toList();
  }

  static DiagnosticTrace? _resolve(String? traceId) {
    final id = traceId ?? _activeTraceId;
    if (id == null) return null;
    return _byId[id];
  }

  static void _upsert(DiagnosticTrace t) {
    if (!_byId.containsKey(t.traceId)) _order.add(t.traceId);
    _byId[t.traceId] = t;
    while (_order.length > _maxTraces) {
      final drop = _order.removeAt(0);
      _byId.remove(drop);
    }
  }
}
