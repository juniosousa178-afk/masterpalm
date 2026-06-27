// Diagnóstico local e sanitizado de sync de catálogo (Hive apenas).

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'catalogo_sync_attempt_context.dart';
import 'catalogo_sync_diagnostic_mask_util.dart';

/// Handle de uma operação em andamento (sem estado global).
class CatalogoSyncOperationHandle {
  CatalogoSyncOperationHandle({
    required this.attemptId,
    required this.operationName,
    required this.startedAtUtc,
  });

  final String attemptId;
  final String operationName;
  final DateTime startedAtUtc;
}

class CatalogoSyncDiagnosticsService {
  CatalogoSyncDiagnosticsService._();

  static const String boxName = 'catalogo_sync_diagnostics_v1';
  static const String _indexKey = '_attempt_index';
  static const int maxAttempts = 30;
  static const Duration retention = Duration(hours: 24);

  @visibleForTesting
  static Box<String>? debugBoxOverride;

  @visibleForTesting
  static void resetForTests() {
    debugBoxOverride = null;
  }

  static Future<Box<String>> _box() async {
    if (debugBoxOverride != null) return debugBoxOverride!;
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  static Future<void> ensureAttemptShell(CatalogoSyncAttemptContext ctx) async {
    final box = await _box();
    if (box.containsKey(ctx.attemptId)) return;
    final record = _emptyRecord(ctx);
    await box.put(ctx.attemptId, jsonEncode(record));
    await _touchIndex(box, ctx.attemptId);
    await _prune(box);
  }

  static Future<CatalogoSyncOperationHandle> startOperation({
    required CatalogoSyncAttemptContext context,
    required String operationName,
    required String collectionName,
    required String storeId,
    required String produtoId,
    required String path,
    required String firestoreMethod,
    required CatalogoSyncMutationIntent mutationIntent,
    required CatalogoSyncDocumentStateHint documentStateHint,
    required String sourceMethod,
  }) async {
    final started = DateTime.now().toUtc();
    await ensureAttemptShell(context);
    await _upsertOperation(
      attemptId: context.attemptId,
      operationName: operationName,
      collectionName: collectionName,
      storeId: storeId,
      produtoId: produtoId,
      path: path,
      firestoreMethod: firestoreMethod,
      mutationIntent: mutationIntent,
      documentStateHint: documentStateHint,
      sourceMethod: sourceMethod,
      startedAtUtc: started,
      status: 'in_progress',
    );
    return CatalogoSyncOperationHandle(
      attemptId: context.attemptId,
      operationName: operationName,
      startedAtUtc: started,
    );
  }

  static Future<void> completeSuccess(CatalogoSyncOperationHandle handle) async {
    await _finalizeOperation(
      handle: handle,
      status: 'success',
      error: null,
    );
  }

  static Future<void> completeFailure(
    CatalogoSyncOperationHandle handle,
    Object error,
  ) async {
    await _finalizeOperation(
      handle: handle,
      status: 'failure',
      error: error,
    );
  }

  static Future<void> _upsertOperation({
    required String attemptId,
    required String operationName,
    required String collectionName,
    required String storeId,
    required String produtoId,
    required String path,
    required String firestoreMethod,
    required CatalogoSyncMutationIntent mutationIntent,
    required CatalogoSyncDocumentStateHint documentStateHint,
    required String sourceMethod,
    required DateTime startedAtUtc,
    required String status,
    DateTime? finishedAtUtc,
    String? firebaseErrorCode,
    String? firebaseErrorCategory,
    String? errorMessageSanitized,
  }) async {
    final box = await _box();
    final record = _readRecord(box, attemptId);
    final ops = List<Map<String, dynamic>>.from(
      (record['operacoes'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final idx = ops.indexWhere((o) => o['operationName'] == operationName);
    final opMap = _operationMap(
      operationName: operationName,
      collectionName: collectionName,
      storeId: storeId,
      produtoId: produtoId,
      path: path,
      firestoreMethod: firestoreMethod,
      mutationIntent: mutationIntent,
      documentStateHint: documentStateHint,
      sourceMethod: sourceMethod,
      startedAtUtc: startedAtUtc,
      finishedAtUtc: finishedAtUtc,
      status: status,
      firebaseErrorCode: firebaseErrorCode,
      firebaseErrorCategory: firebaseErrorCategory,
      errorMessageSanitized: errorMessageSanitized,
    );
    if (idx >= 0) {
      ops[idx] = opMap;
    } else {
      ops.add(opMap);
    }
    record['operacoes'] = ops;
    await box.put(attemptId, jsonEncode(record));
  }

  static Future<void> _finalizeOperation({
    required CatalogoSyncOperationHandle handle,
    required String status,
    Object? error,
  }) async {
    try {
      final box = await _box();
      final record = _readRecord(box, handle.attemptId);
      final ops = List<Map<String, dynamic>>.from(
        (record['operacoes'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );
      final idx =
          ops.indexWhere((o) => o['operationName'] == handle.operationName);
      if (idx < 0) return;

      final existing = Map<String, dynamic>.from(ops[idx]);
      existing['status'] = status;
      existing['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();

      if (error != null) {
        if (error is FirebaseException) {
          existing['firebaseErrorCode'] = error.code;
          existing['firebaseErrorCategory'] = _categoriaFirebase(error.code);
          existing['errorMessageSanitized'] =
              CatalogoSyncDiagnosticMaskUtil.sanitizarMensagemErro(error);
        } else if (error is FirebaseAuthException) {
          existing['firebaseErrorCode'] = error.code;
          existing['firebaseErrorCategory'] = _categoriaFirebase(error.code);
          existing['errorMessageSanitized'] =
              CatalogoSyncDiagnosticMaskUtil.sanitizarMensagemErro(error);
        } else {
          existing['errorMessageSanitized'] =
              CatalogoSyncDiagnosticMaskUtil.sanitizarMensagemErro(error);
        }
      }

      ops[idx] = existing;
      record['operacoes'] = ops;
      await box.put(handle.attemptId, jsonEncode(record));
    } catch (_) {}
  }

  static Map<String, dynamic> _operationMap({
    required String operationName,
    required String collectionName,
    required String storeId,
    required String produtoId,
    required String path,
    required String firestoreMethod,
    required CatalogoSyncMutationIntent mutationIntent,
    required CatalogoSyncDocumentStateHint documentStateHint,
    required String sourceMethod,
    required DateTime startedAtUtc,
    DateTime? finishedAtUtc,
    required String status,
    String? firebaseErrorCode,
    String? firebaseErrorCategory,
    String? errorMessageSanitized,
  }) {
    return {
      'operationName': operationName,
      'collectionName': collectionName,
      'storeIdMasked':
          CatalogoSyncDiagnosticMaskUtil.mascararLojaId(storeId),
      'produtoIdMasked':
          CatalogoSyncDiagnosticMaskUtil.mascararProdutoId(produtoId),
      'pathMasked': CatalogoSyncDiagnosticMaskUtil.mascararPath(path),
      'firestoreMethod': firestoreMethod,
      'mutationIntent': mutationIntent.name,
      'documentStateHint': documentStateHint.name,
      'startedAtUtc': startedAtUtc.toIso8601String(),
      if (finishedAtUtc != null)
        'finishedAtUtc': finishedAtUtc.toIso8601String(),
      'status': status,
      if (firebaseErrorCode != null) 'firebaseErrorCode': firebaseErrorCode,
      if (firebaseErrorCategory != null)
        'firebaseErrorCategory': firebaseErrorCategory,
      if (errorMessageSanitized != null && errorMessageSanitized.isNotEmpty)
        'errorMessageSanitized': errorMessageSanitized,
      'sourceMethod': sourceMethod,
    };
  }

  static Map<String, dynamic> _emptyRecord(CatalogoSyncAttemptContext ctx) =>
      {
        'attemptIdCurto': ctx.attemptIdCurto,
        'attemptId': ctx.attemptId,
        'timestampUtc': ctx.startedAtUtc.toIso8601String(),
        'origin': ctx.origin,
        'contextoSanitizado': ctx.toSanitizedMap(),
        'operacoes': <Map<String, dynamic>>[],
      };

  static Map<String, dynamic> _readRecord(Box<String> box, String attemptId) {
    final raw = box.get(attemptId);
    if (raw == null || raw.isEmpty) {
      return {
        'attemptId': attemptId,
        'operacoes': <Map<String, dynamic>>[],
      };
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> _touchIndex(Box<String> box, String attemptId) async {
    final list = List<String>.from(
      jsonDecode(box.get(_indexKey) ?? '[]') as List,
    );
    list.remove(attemptId);
    list.insert(0, attemptId);
    await box.put(_indexKey, jsonEncode(list));
  }

  static Future<void> _prune(Box<String> box) async {
    final now = DateTime.now().toUtc();
    final list = List<String>.from(
      jsonDecode(box.get(_indexKey) ?? '[]') as List,
    );
    final kept = <String>[];
    for (final id in list) {
      final raw = box.get(id);
      if (raw == null) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final ts = DateTime.tryParse(
              (map['timestampUtc'] ?? '').toString(),
            ) ??
            now;
        if (now.difference(ts) > retention) {
          await box.delete(id);
          continue;
        }
        kept.add(id);
      } catch (_) {
        await box.delete(id);
      }
    }
    while (kept.length > maxAttempts) {
      final drop = kept.removeLast();
      await box.delete(drop);
    }
    await box.put(_indexKey, jsonEncode(kept));
  }

  static String _categoriaFirebase(String code) {
    switch (code) {
      case 'permission-denied':
        return 'permission_denied';
      case 'unauthenticated':
        return 'unauthenticated';
      case 'app-check-token-invalid':
      case 'app-check-failed':
        return 'app_check';
      default:
        return code.isEmpty ? 'unknown' : code;
    }
  }

  static Future<List<Map<String, dynamic>>> listAttempts({
    int limit = maxAttempts,
  }) async {
    final box = await _box();
    await _prune(box);
    final list = List<String>.from(
      jsonDecode(box.get(_indexKey) ?? '[]') as List,
    );
    final out = <Map<String, dynamic>>[];
    for (final id in list.take(limit)) {
      final raw = box.get(id);
      if (raw == null) continue;
      try {
        out.add(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  static Future<Map<String, dynamic>?> latestAttempt() async {
    final list = await listAttempts(limit: 1);
    if (list.isEmpty) return null;
    return list.first;
  }

  static String buildSafeReport(Map<String, dynamic> record) {
    final buffer = StringBuffer();
    buffer.writeln('=== Diagnóstico sync catálogo (sanitizado) ===');
    buffer.writeln('Tentativa: ${record['attemptIdCurto'] ?? '—'}');
    buffer.writeln('Origem: ${record['origin'] ?? '—'}');
    buffer.writeln('Horário: ${record['timestampUtc'] ?? '—'}');
    final ctx = record['contextoSanitizado'] as Map<String, dynamic>?;
    if (ctx != null) {
      buffer.writeln('Build: ${ctx['buildId'] ?? '—'}');
      buffer.writeln('Host: ${ctx['host'] ?? '—'}');
      buffer.writeln('Projeto Firebase: ${ctx['firebaseProjectId'] ?? '—'}');
      buffer.writeln('Loja sessão: ${ctx['sessionStoreIdMasked'] ?? '—'}');
      buffer.writeln('Loja resolvida: ${ctx['resolvedStoreIdMasked'] ?? '—'}');
      buffer.writeln('UID: ${ctx['authUidMasked'] ?? '—'}');
      buffer.writeln('Auth: ${ctx['authState'] ?? '—'}');
      buffer.writeln('Token metadata: ${ctx['tokenMetadataState'] ?? '—'}');
    }
    buffer.writeln('--- Operações ---');
    final ops =
        (record['operacoes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final op in ops) {
      buffer.writeln(
        '${op['operationName']}: ${op['status']} '
        '(${op['firebaseErrorCode'] ?? '—'})',
      );
      buffer.writeln('  path: ${op['pathMasked'] ?? '—'}');
      buffer.writeln('  método: ${op['firestoreMethod'] ?? '—'} / '
          '${op['mutationIntent'] ?? '—'}');
      final err = op['errorMessageSanitized'];
      if (err != null && err.toString().isNotEmpty) {
        buffer.writeln('  msg: $err');
      }
    }
    return buffer.toString().trim();
  }
}
