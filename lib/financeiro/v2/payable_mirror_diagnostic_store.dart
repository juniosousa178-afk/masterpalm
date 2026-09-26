// Diagnóstico local do espelho de contas a pagar.
// Não grava Firestore. Não guarda descrição, observação nem nome de fornecedor.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive/src/hive_impl.dart';

import '../../core/client_build_identity.dart';
import '../../core/hive_box_names.dart';

abstract final class PayableMirrorAction {
  static const createFromPurchase = 'CREATE_FROM_PURCHASE';
  static const save = 'SAVE';
  static const markPaid = 'MARK_PAID';
  static const cancel = 'CANCEL';
  static const updateDueDate = 'UPDATE_DUE_DATE';
}

abstract final class PayableMirrorDiagnosticResult {
  static const skippedFlagFalse = 'MIRROR_SKIPPED_FLAG_FALSE';
  static const skippedStoreMismatch = 'MIRROR_SKIPPED_STORE_MISMATCH';
  static const flagReadAttempt = 'MIRROR_FLAG_READ_ATTEMPT';
  static const flagReadFailed = 'MIRROR_FLAG_READ_FAILED';
  static const attempt = 'MIRROR_ATTEMPT';
  static const success = 'MIRROR_SUCCESS';
  static const noChange = 'MIRROR_NO_CHANGE';
  static const rejectedTerminal = 'MIRROR_REJECTED_TERMINAL';
  static const rejectedOlder = 'MIRROR_REJECTED_OLDER';
  static const permissionDenied = 'MIRROR_PERMISSION_DENIED';
  static const unauthenticated = 'MIRROR_UNAUTHENTICATED';
  static const networkFailure = 'MIRROR_NETWORK_FAILURE';
  static const invalidArgument = 'MIRROR_INVALID_ARGUMENT';
  static const unknownFailure = 'MIRROR_UNKNOWN_FAILURE';
}

class PayableMirrorDiagnosticRecord {
  const PayableMirrorDiagnosticRecord({
    required this.timestamp,
    required this.storeId,
    required this.payableId,
    required this.action,
    required this.stage,
    required this.result,
    required this.buildId,
    required this.appVersion,
    required this.gitCommit,
    this.errorCode,
    this.flagState,
    this.localUpdatedAt,
  });

  final DateTime timestamp;
  final String storeId;
  final String payableId;
  final String action;
  final String stage;
  final String result;
  final String? errorCode;
  final String? flagState;
  final int? localUpdatedAt;
  final String buildId;
  final String appVersion;
  final String gitCommit;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'storeId': storeId,
        'payableId': payableId,
        'action': action,
        'stage': stage,
        'result': result,
        'errorCode': errorCode,
        'flagState': flagState,
        'localUpdatedAt': localUpdatedAt,
        'buildId': buildId,
        'appVersion': appVersion,
        'gitCommit': gitCommit,
      };

  factory PayableMirrorDiagnosticRecord.fromJson(Map<String, dynamic> json) {
    return PayableMirrorDiagnosticRecord(
      timestamp: DateTime.tryParse('${json['timestamp']}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      storeId: '${json['storeId'] ?? ''}',
      payableId: '${json['payableId'] ?? ''}',
      action: '${json['action'] ?? ''}',
      stage: '${json['stage'] ?? ''}',
      result: '${json['result'] ?? ''}',
      errorCode: json['errorCode']?.toString(),
      flagState: json['flagState']?.toString(),
      localUpdatedAt: json['localUpdatedAt'] is int
          ? json['localUpdatedAt'] as int
          : int.tryParse('${json['localUpdatedAt']}'),
      buildId: '${json['buildId'] ?? ''}',
      appVersion: '${json['appVersion'] ?? ''}',
      gitCommit: '${json['gitCommit'] ?? ''}',
    );
  }
}

abstract final class PayableMirrorDiagnosticStore {
  static const int remoteDiagnosticWrites = 0;
  static const int maxEvents = 200;

  static bool get _diskReady {
    final hive = Hive;
    return hive is HiveImpl && (hive.homePath?.isNotEmpty ?? false);
  }

  static Future<void> append({
    required String storeId,
    required String payableId,
    required String action,
    required String stage,
    required String result,
    String? errorCode,
    String? flagState,
    int? localUpdatedAt,
  }) async {
    final store = storeId.trim();
    if (store.isEmpty || !_diskReady) return;
    final record = PayableMirrorDiagnosticRecord(
      timestamp: DateTime.now().toUtc(),
      storeId: store,
      payableId: payableId.trim(),
      action: action,
      stage: stage,
      result: result,
      errorCode: errorCode,
      flagState: flagState,
      localUpdatedAt: localUpdatedAt,
      buildId: kClientBuildId,
      appVersion: kClientAppVersion,
      gitCommit: kClientGitCommit,
    );
    try {
      final name = HiveBoxNames.payableMirrorDiagnostics(store);
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox(name);
      }
      final box = Hive.box(name);
      final list = _decode(box.get('events'));
      list.add(record.toJson());
      while (list.length > maxEvents) {
        list.removeAt(0);
      }
      await box.put('events', list);
    } catch (e) {
      debugPrint('[CP-MIRROR-DIAG] persist skipped ${e.runtimeType}');
    }
  }

  static Future<List<PayableMirrorDiagnosticRecord>> read(String storeId) async {
    final store = storeId.trim();
    if (store.isEmpty || !_diskReady) return const [];
    try {
      final name = HiveBoxNames.payableMirrorDiagnostics(store);
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox(name);
      }
      return _decode(Hive.box(name).get('events'))
          .map(PayableMirrorDiagnosticRecord.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[CP-MIRROR-DIAG] read skipped ${e.runtimeType}');
      return const [];
    }
  }

  static Future<String> exportJson(String storeId) async {
    final events = await read(storeId);
    return jsonEncode({
      'appVersion': kClientAppVersion,
      'buildId': kClientBuildId,
      'gitCommit': kClientGitCommit,
      'storeId': storeId.trim(),
      'remoteDiagnosticWrites': remoteDiagnosticWrites,
      'events': events.map((e) => e.toJson()).toList(),
    });
  }

  static List<Map<String, dynamic>> _decode(dynamic raw) {
    if (raw is! List) return [];
    final list = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) list.add(Map<String, dynamic>.from(item));
    }
    return list;
  }
}
