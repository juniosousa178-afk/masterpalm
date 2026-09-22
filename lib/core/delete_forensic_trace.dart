// LOCAL-ONLY post-restore delete/restore stage tracer.
// Diagnostic only — does not change stock/delete business semantics.
// Never writes Firestore / Cloud Logging with PII.

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'client_build_identity.dart';
import 'sale_forensic_trace.dart'
    show forensicStackTop, sanitizeForensicDetails;

const int kDeleteForensicMaxTraces = 20;
const String kDeleteForensicHiveBox = 'delete_forensic_traces_v1';

/// Required / known stage names for post-restore delete tracing.
abstract final class DeleteTraceStage {
  static const deleteStart = 'DELETE_START';
  static const restoreSourceResolved = 'RESTORE_SOURCE_RESOLVED';
  static const restoreCommandStart = 'RESTORE_COMMAND_START';
  static const restoreCommandHttpSuccess = 'RESTORE_COMMAND_HTTP_SUCCESS';
  static const restoreResultParsed = 'RESTORE_RESULT_PARSED';
  static const restoreResultApplied = 'RESTORE_RESULT_APPLIED';
  static const restoreResultNewlyApplied = 'RESTORE_RESULT_NEWLY_APPLIED';
  static const restoreResultIdempotentAlreadyApplied =
      'RESTORE_RESULT_IDEMPOTENT_ALREADY_APPLIED';
  static const localHiveApplyStart = 'LOCAL_HIVE_APPLY_START';
  static const localHiveApplySuccess = 'LOCAL_HIVE_APPLY_SUCCESS';
  static const localHiveApplyError = 'LOCAL_HIVE_APPLY_ERROR';
  static const remoteRefreshStart = 'REMOTE_REFRESH_START';
  static const remoteRefreshSuccess = 'REMOTE_REFRESH_SUCCESS';
  static const remoteRefreshError = 'REMOTE_REFRESH_ERROR';
  static const saleSoftDeleteStart = 'SALE_SOFT_DELETE_START';
  static const saleSoftDeleteSuccess = 'SALE_SOFT_DELETE_SUCCESS';
  static const saleSoftDeleteError = 'SALE_SOFT_DELETE_ERROR';
  static const deleteComplete = 'DELETE_COMPLETE';
  static const deleteAbort = 'DELETE_ABORT';
}

class DeleteForensicTrace {
  DeleteForensicTrace({
    required this.deleteTraceId,
    required this.startedAt,
    Map<String, dynamic>? buildProof,
    this.sourceOperationId = '',
    this.restoreOperationId = '',
    this.lojaId = '',
    List<Map<String, dynamic>>? stages,
  })  : buildProof = Map<String, dynamic>.from(
          buildProof ?? clientBuildProofMap(),
        ),
        stages = stages ?? <Map<String, dynamic>>[];

  final String deleteTraceId;
  final String startedAt;
  final Map<String, dynamic> buildProof;
  String sourceOperationId;
  String restoreOperationId;
  String lojaId;
  final List<Map<String, dynamic>> stages;
  String? finalStage;
  bool aborted = false;

  String get shortCode =>
      deleteTraceId.length >= 8 ? deleteTraceId.substring(0, 8) : deleteTraceId;

  void recordStage(
    String stage, {
    bool success = true,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? extra,
  }) {
    final started = DateTime.now().toUtc().toIso8601String();
    String? errorType;
    String? errorCode;
    String? errorMessage;
    String stackTop = '';
    if (error != null) {
      errorType = error.runtimeType.toString();
      if (error is FirebaseFunctionsException) {
        errorCode = error.code;
        errorMessage = sanitizeForensicDetails(error.message)?.toString();
      } else if (error is FirebaseException) {
        errorCode = error.code;
        errorMessage = sanitizeForensicDetails(error.message)?.toString();
      } else {
        errorMessage = sanitizeForensicDetails(error.toString())?.toString();
      }
      stackTop = forensicStackTop(stack);
    }
    final row = <String, dynamic>{
      'DELETE_TRACE_ID': deleteTraceId,
      'SOURCE_OPERATION_ID': sourceOperationId,
      'RESTORE_OPERATION_ID': restoreOperationId,
      'STAGE': stage,
      'STARTED_AT': started,
      'SUCCESS': success,
      if (errorType != null) 'ERROR_TYPE': errorType,
      if (errorCode != null) 'ERROR_CODE': errorCode,
      if (errorMessage != null) 'ERROR_MESSAGE_SANITIZED': errorMessage,
      if (stackTop.isNotEmpty) 'STACK_TOP_FRAMES': stackTop,
      if (extra != null) 'EXTRA': sanitizeForensicDetails(extra),
    };
    stages.add(row);
    finalStage = stage;
    if (!success ||
        stage == DeleteTraceStage.deleteAbort ||
        stage == DeleteTraceStage.localHiveApplyError ||
        stage == DeleteTraceStage.remoteRefreshError ||
        stage == DeleteTraceStage.saleSoftDeleteError) {
      if (stage == DeleteTraceStage.deleteAbort) aborted = true;
    }
    debugPrint(
      '[DELETE-TRACE] id=$shortCode stage=$stage success=$success'
      '${errorType != null ? ' type=$errorType' : ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'DELETE_TRACE_ID': deleteTraceId,
        'startedAt': startedAt,
        'SOURCE_OPERATION_ID': sourceOperationId,
        'RESTORE_OPERATION_ID': restoreOperationId,
        'lojaId': lojaId,
        'finalStage': finalStage,
        'aborted': aborted,
        ...buildProof,
        'stages': List<Map<String, dynamic>>.from(stages),
      };

  static DeleteForensicTrace fromJson(Map<String, dynamic> map) {
    final stagesRaw = map['stages'];
    final stages = <Map<String, dynamic>>[];
    if (stagesRaw is List) {
      for (final s in stagesRaw) {
        if (s is Map) stages.add(Map<String, dynamic>.from(s));
      }
    }
    return DeleteForensicTrace(
      deleteTraceId: (map['DELETE_TRACE_ID'] ?? map['deleteTraceId'] ?? '')
          .toString(),
      startedAt: (map['startedAt'] ?? '').toString(),
      buildProof: {
        'CLIENT_BUILD_ID': map['CLIENT_BUILD_ID'],
        'CLIENT_GIT_COMMIT': map['CLIENT_GIT_COMMIT'],
        'APP_VERSION': map['APP_VERSION'],
        'BUILD_METADATA_MISSING': map['BUILD_METADATA_MISSING'],
      },
      sourceOperationId: (map['SOURCE_OPERATION_ID'] ?? '').toString(),
      restoreOperationId: (map['RESTORE_OPERATION_ID'] ?? '').toString(),
      lojaId: (map['lojaId'] ?? '').toString(),
      stages: stages,
    )
      ..finalStage = map['finalStage']?.toString()
      ..aborted = map['aborted'] == true;
  }
}

class DeleteForensicTraceStore {
  DeleteForensicTraceStore._();

  static final Map<String, DeleteForensicTrace> _byId = {};
  static final List<String> _order = [];
  static String? _activeTraceId;
  static bool _hiveHydrated = false;
  static bool _hiveReady = false;

  @visibleForTesting
  static bool disableHive = false;

  static String? get activeTraceId => _activeTraceId;

  static DeleteForensicTrace? get active =>
      _activeTraceId == null ? null : _byId[_activeTraceId!];

  @visibleForTesting
  static void clearAll() {
    _byId.clear();
    _order.clear();
    _activeTraceId = null;
    _hiveHydrated = false;
    _hiveReady = false;
  }

  static Future<void> ensureHydrated() async {
    if (_hiveHydrated) return;
    _hiveHydrated = true;
    if (disableHive) return;
    try {
      if (!Hive.isBoxOpen(kDeleteForensicHiveBox)) {
        await Hive.openBox(kDeleteForensicHiveBox);
      }
      final box = Hive.box(kDeleteForensicHiveBox);
      _hiveReady = true;
      final raw = box.get('traces');
      if (raw is List) {
        for (final item in raw) {
          Map<String, dynamic>? map;
          if (item is Map) {
            map = Map<String, dynamic>.from(item);
          } else if (item is String) {
            final decoded = jsonDecode(item);
            if (decoded is Map) map = Map<String, dynamic>.from(decoded);
          }
          if (map == null) continue;
          final t = DeleteForensicTrace.fromJson(map);
          if (t.deleteTraceId.isEmpty) continue;
          _upsertMemory(t);
        }
      }
    } catch (e) {
      _hiveReady = false;
      debugPrint(
        '[DELETE-TRACE] hive hydrate skipped type=${e.runtimeType}',
      );
    }
  }

  static Future<void> _persist() async {
    if (disableHive || !_hiveReady) return;
    try {
      if (!Hive.isBoxOpen(kDeleteForensicHiveBox)) {
        await Hive.openBox(kDeleteForensicHiveBox);
      }
      final box = Hive.box(kDeleteForensicHiveBox);
      final list =
          tracesNewestFirst.map((t) => t.toJson()).toList(growable: false);
      await box.put('traces', list);
    } catch (e) {
      debugPrint(
        '[DELETE-TRACE] hive persist skipped type=${e.runtimeType}',
      );
    }
  }

  static void _upsertMemory(DeleteForensicTrace t) {
    final id = t.deleteTraceId;
    if (!_byId.containsKey(id)) {
      _order.add(id);
    }
    _byId[id] = t;
    while (_order.length > kDeleteForensicMaxTraces) {
      final drop = _order.removeAt(0);
      _byId.remove(drop);
    }
  }

  static Future<DeleteForensicTrace> start({
    String? deleteTraceId,
    String? lojaId,
  }) async {
    await ensureHydrated();
    final id = (deleteTraceId ?? const Uuid().v4()).trim();
    final t = DeleteForensicTrace(
      deleteTraceId: id,
      startedAt: DateTime.now().toUtc().toIso8601String(),
      lojaId: (lojaId ?? '').trim(),
    );
    _activeTraceId = id;
    _upsertMemory(t);
    t.recordStage(DeleteTraceStage.deleteStart);
    // ignore: discarded_futures
    _persist();
    return t;
  }

  static void setSourceOperationId(String id) {
    final t = active;
    if (t == null) return;
    t.sourceOperationId = id.trim();
  }

  static void setRestoreOperationId(String id) {
    final t = active;
    if (t == null) return;
    t.restoreOperationId = id.trim();
  }

  static void stage(
    String name, {
    bool success = true,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? extra,
  }) {
    final t = active;
    if (t == null) return;
    t.recordStage(
      name,
      success: success,
      error: error,
      stack: stack,
      extra: extra,
    );
    // ignore: discarded_futures
    _persist();
  }

  /// Record error without replacing caller rethrow behavior.
  static void captureError(
    String stageName,
    Object error,
    StackTrace stack, {
    Map<String, dynamic>? extra,
  }) {
    stage(
      stageName,
      success: false,
      error: error,
      stack: stack,
      extra: extra,
    );
  }

  static void endActive({bool aborted = false}) {
    final t = active;
    if (t == null) return;
    if (aborted) {
      t.recordStage(DeleteTraceStage.deleteAbort, success: false);
      t.aborted = true;
    } else if (t.finalStage != DeleteTraceStage.deleteComplete) {
      t.recordStage(DeleteTraceStage.deleteComplete);
    }
    _activeTraceId = null;
    // ignore: discarded_futures
    _persist();
  }

  static List<DeleteForensicTrace> get tracesNewestFirst {
    final ids = _order.reversed.toList(growable: false);
    return [
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!,
    ];
  }

  static Map<String, dynamic> toDiagnosticSection() {
    final proof = clientBuildProofMap();
    return {
      'clientBuildId': proof['CLIENT_BUILD_ID'],
      'clientGitCommit': proof['CLIENT_GIT_COMMIT'],
      'appVersion': proof['APP_VERSION'],
      'READ_ONLY_EXPORT': true,
      'traceCount': _byId.length,
      'traces':
          tracesNewestFirst.map((t) => t.toJson()).toList(growable: false),
    };
  }

  /// Sanitized restore response fields for forensics (no PII).
  static Map<String, dynamic> sanitizeRestoreResponse(
    Map<String, dynamic> response,
  ) {
    final products = response['products'];
    return {
      'operationId': response['operationId']?.toString(),
      'status': response['status']?.toString(),
      'alreadyApplied': response['alreadyApplied'] == true,
      'applied': response['applied'] == true,
      'sourceOperationId': response['sourceOperationId']?.toString(),
      'productCount': products is List ? products.length : null,
      'RESTORE_RESPONSE_FIELDS_AVAILABLE': [
        if (response.containsKey('operationId')) 'operationId',
        if (response.containsKey('status')) 'status',
        if (response.containsKey('alreadyApplied')) 'alreadyApplied',
        if (response.containsKey('applied')) 'applied',
        if (response.containsKey('sourceOperationId')) 'sourceOperationId',
        if (response.containsKey('products')) 'products',
      ],
    };
  }
}
