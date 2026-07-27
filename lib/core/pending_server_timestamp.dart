// Fake de duas fases para `FieldValue.serverTimestamp` (testes R8.3).

import 'package:cloud_firestore/cloud_firestore.dart';

/// Placeholder pendente até readback resolver o timestamp do servidor.
class PendingServerTimestamp {
  const PendingServerTimestamp();

  @override
  String toString() => 'PendingServerTimestamp';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PendingServerTimestamp;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Resolve placeholder → [Timestamp] após simular readback Firestore.
DateTime? resolvePendingServerTimestamp(
  dynamic value, {
  DateTime? resolvedAt,
}) {
  if (value is PendingServerTimestamp) {
    return resolvedAt ?? DateTime.utc(2026, 6, 15, 15, 10);
  }
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

/// Simula escrita com serverTimestamp pendente e readback posterior.
class TwoPhaseServerTimestampHarness {
  TwoPhaseServerTimestampHarness({DateTime? resolvedAt})
      : resolvedAt = resolvedAt ?? DateTime.utc(2026, 6, 15, 15, 10);

  final DateTime resolvedAt;
  final Map<String, dynamic> pendingWrites = {};
  final Map<String, dynamic> resolvedReads = {};

  void writePending(String docPath, Map<String, dynamic> data) {
    pendingWrites[docPath] = Map<String, dynamic>.from(data);
    resolvedReads.remove(docPath);
  }

  Map<String, dynamic> readback(String docPath) {
    final pending = pendingWrites[docPath];
    if (pending == null) return Map<String, dynamic>.from(resolvedReads[docPath] ?? {});
    final resolved = <String, dynamic>{};
    pending.forEach((k, v) {
      if (v is PendingServerTimestamp || v == FieldValue.serverTimestamp()) {
        resolved[k] = Timestamp.fromDate(resolvedAt);
      } else {
        resolved[k] = v;
      }
    });
    resolvedReads[docPath] = resolved;
    return Map<String, dynamic>.from(resolved);
  }

  dynamic valueBeforeReadback(String docPath, String field) {
    return pendingWrites[docPath]?[field];
  }

  dynamic valueAfterReadback(String docPath, String field) {
    readback(docPath);
    return resolvedReads[docPath]?[field];
  }
}
