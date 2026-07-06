// Journal local mínimo: recupera operationId após interrupção pré-Hive.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';

/// Interrupção abrupta simulada em testes — sem rollback de estoque.
class VendaOperationInterruptedException implements Exception {
  const VendaOperationInterruptedException();

  @override
  String toString() => 'VendaOperationInterruptedException';
}

/// Journal incompatível com operationId ou hash exigido (M3.2-B).
class VendaOperationJournalIdentityConflictException implements Exception {
  VendaOperationJournalIdentityConflictException(this.message);
  final String message;

  @override
  String toString() =>
      'VendaOperationJournalIdentityConflictException: $message';
}

/// Entrada pendente no journal local (privacy-minimal).
class VendaOperationJournalEntry {
  const VendaOperationJournalEntry({
    required this.operationId,
    required this.lojaId,
    required this.operationKey,
    required this.stockEffectHash,
    required this.createdAt,
    required this.updatedAt,
    this.critical = false,
  });

  final String operationId;
  final String lojaId;
  final String operationKey;
  final String stockEffectHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool critical;

  Map<String, dynamic> toMap() => {
        'operationId': operationId,
        'lojaId': lojaId,
        'operationKey': operationKey,
        'stockEffectHash': stockEffectHash,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'critical': critical,
      };

  static VendaOperationJournalEntry? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final opId = (m['operationId'] ?? '').toString().trim();
    final loja = (m['lojaId'] ?? '').toString().trim();
    final key = (m['operationKey'] ?? '').toString().trim();
    final hash = (m['stockEffectHash'] ?? '').toString().trim();
    if (opId.isEmpty || loja.isEmpty || key.isEmpty || hash.isEmpty) {
      return null;
    }
    final createdMs = (m['createdAt'] as num?)?.toInt();
    final updatedMs = (m['updatedAt'] as num?)?.toInt();
    if (createdMs == null || updatedMs == null) return null;
    return VendaOperationJournalEntry(
      operationId: opId,
      lojaId: loja,
      operationKey: key,
      stockEffectHash: hash,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      critical: m['critical'] == true,
    );
  }
}

abstract final class VendaOperationJournalService {
  VendaOperationJournalService._();

  @visibleForTesting
  static Box<Map>? debugBoxOverride;

  @visibleForTesting
  static void debugClearOverride() {
    debugBoxOverride = null;
  }

  static String buildOperationKey({
    required String lojaId,
    required String stockEffectHash,
  }) {
    final loja = lojaId.trim();
    final hash = stockEffectHash.trim();
    return '$loja|$hash';
  }

  static Future<Box<Map>> _openBox(String lojaId) async {
    if (debugBoxOverride != null) return debugBoxOverride!;
    final name = HiveBoxNames.vendaOperationJournal(lojaId);
    if (Hive.isBoxOpen(name)) {
      return Hive.box<Map>(name);
    }
    return Hive.openBox<Map>(name);
  }

  static Future<VendaOperationJournalEntry?> findPending({
    required String lojaId,
    required String operationKey,
  }) async {
    final loja = lojaId.trim();
    final key = operationKey.trim();
    if (loja.isEmpty || key.isEmpty) return null;
    final box = await _openBox(loja);
    final raw = box.get(key);
    return VendaOperationJournalEntry.fromMap(raw);
  }

  /// Reserva UUID novo ou recupera pendente compatível. Persiste ANTES da baixa remota.
  static Future<VendaOperationJournalEntry> reserveOrRecover({
    required String lojaId,
    required String operationKey,
    required String stockEffectHash,
    String? explicitOperationId,
    String? requiredOperationId,
  }) async {
    final loja = lojaId.trim();
    final key = operationKey.trim();
    final hash = stockEffectHash.trim();
    if (loja.isEmpty || key.isEmpty || hash.isEmpty) {
      throw ArgumentError('Journal: lojaId, operationKey e stockEffectHash obrigatórios.');
    }

    final box = await _openBox(loja);
    final now = DateTime.now();

    final required = (requiredOperationId ?? '').trim();
    if (required.isNotEmpty) {
      final existing = VendaOperationJournalEntry.fromMap(box.get(key));
      if (existing != null) {
        if (existing.stockEffectHash != hash || existing.lojaId != loja) {
          throw VendaOperationJournalIdentityConflictException(
            'stockEffectHash divergente no journal para operationKey=$key.',
          );
        }
        if (existing.operationId != required) {
          throw VendaOperationJournalIdentityConflictException(
            'operationId divergente no journal para operationKey=$key.',
          );
        }
        final touched = VendaOperationJournalEntry(
          operationId: existing.operationId,
          lojaId: existing.lojaId,
          operationKey: existing.operationKey,
          stockEffectHash: existing.stockEffectHash,
          createdAt: existing.createdAt,
          updatedAt: now,
          critical: existing.critical,
        );
        await box.put(key, touched.toMap());
        return touched;
      }
      final entry = VendaOperationJournalEntry(
        operationId: required,
        lojaId: loja,
        operationKey: key,
        stockEffectHash: hash,
        createdAt: now,
        updatedAt: now,
      );
      await box.put(key, entry.toMap());
      return entry;
    }

    final explicit = (explicitOperationId ?? '').trim();
    if (explicit.isNotEmpty) {
      final entry = VendaOperationJournalEntry(
        operationId: explicit,
        lojaId: loja,
        operationKey: key,
        stockEffectHash: hash,
        createdAt: now,
        updatedAt: now,
      );
      await box.put(key, entry.toMap());
      return entry;
    }

    final existing = VendaOperationJournalEntry.fromMap(box.get(key));
    if (existing != null &&
        existing.stockEffectHash == hash &&
        existing.lojaId == loja) {
      final touched = VendaOperationJournalEntry(
        operationId: existing.operationId,
        lojaId: existing.lojaId,
        operationKey: existing.operationKey,
        stockEffectHash: existing.stockEffectHash,
        createdAt: existing.createdAt,
        updatedAt: now,
        critical: existing.critical,
      );
      await box.put(key, touched.toMap());
      return touched;
    }

    final operationId = const Uuid().v4();
    final entry = VendaOperationJournalEntry(
      operationId: operationId,
      lojaId: loja,
      operationKey: key,
      stockEffectHash: hash,
      createdAt: now,
      updatedAt: now,
    );
    await box.put(key, entry.toMap());
    return entry;
  }

  static Future<void> complete({
    required String lojaId,
    required String operationKey,
  }) async {
    final loja = lojaId.trim();
    final key = operationKey.trim();
    if (loja.isEmpty || key.isEmpty) return;
    final box = await _openBox(loja);
    await box.delete(key);
  }

  static Future<void> revert({
    required String lojaId,
    required String operationKey,
  }) async {
    await complete(lojaId: lojaId, operationKey: operationKey);
  }

  static Future<void> markCritical({
    required String lojaId,
    required String operationKey,
  }) async {
    final loja = lojaId.trim();
    final key = operationKey.trim();
    if (loja.isEmpty || key.isEmpty) return;
    final box = await _openBox(loja);
    final existing = VendaOperationJournalEntry.fromMap(box.get(key));
    if (existing == null) return;
    await box.put(
      key,
      VendaOperationJournalEntry(
        operationId: existing.operationId,
        lojaId: existing.lojaId,
        operationKey: existing.operationKey,
        stockEffectHash: existing.stockEffectHash,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
        critical: true,
      ).toMap(),
    );
  }
}
