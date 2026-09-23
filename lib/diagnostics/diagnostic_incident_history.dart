import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'diagnostic_enums.dart';
import 'diagnostic_incident.dart';

const String kDiagnosticIncidentHiveBox = 'diagnostic_incidents_v1';
const int kDiagnosticIncidentMax = 200;
const Duration kDiagnosticIncidentRetention = Duration(days: 30);
const Duration kDiagnosticCriticalRetention = Duration(days: 90);

/// Bounded local incident history (Hive). Never writes Firestore.
class DiagnosticIncidentHistory {
  DiagnosticIncidentHistory._();

  static final List<DiagnosticIncident> _memory = [];
  static bool _hydrated = false;
  static bool _hiveReady = false;

  @visibleForTesting
  static bool disableHive = false;

  @visibleForTesting
  static void clearAll() {
    _memory.clear();
    _hydrated = false;
    _hiveReady = false;
  }

  static Future<void> ensureHydrated() async {
    if (_hydrated) return;
    _hydrated = true;
    if (disableHive) return;
    try {
      if (!Hive.isBoxOpen(kDiagnosticIncidentHiveBox)) {
        await Hive.openBox(kDiagnosticIncidentHiveBox);
      }
      final box = Hive.box(kDiagnosticIncidentHiveBox);
      _hiveReady = true;
      final raw = box.get('incidents');
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
          _memory.add(DiagnosticIncident.fromJson(map));
        }
      }
      _prune();
    } catch (e) {
      _hiveReady = false;
      debugPrint('[DIAG-HISTORY] hydrate skipped type=${e.runtimeType}');
    }
  }

  static Future<void> record(DiagnosticIncident incident) async {
    await ensureHydrated();
    _memory.add(incident);
    _prune();
    await _persist();
  }

  static List<DiagnosticIncident> recent({
    String? storeId,
    int limit = 50,
  }) {
    final list = _memory.reversed
        .where((i) => storeId == null || i.storeId == storeId)
        .take(limit)
        .toList();
    return list;
  }

  static List<Map<String, dynamic>> toJsonList({String? storeId}) =>
      recent(storeId: storeId, limit: kDiagnosticIncidentMax)
          .map((i) => i.toJson(includeStack: false))
          .toList();

  static void _prune() {
    final now = DateTime.now().toUtc();
    _memory.removeWhere((i) {
      final age = now.difference(i.timestamp);
      if (i.severity == DiagnosticSeverity.critical) {
        return age > kDiagnosticCriticalRetention;
      }
      return age > kDiagnosticIncidentRetention;
    });
    while (_memory.length > kDiagnosticIncidentMax) {
      // Drop oldest non-critical first when possible.
      final idx = _memory.indexWhere((i) => i.severity != DiagnosticSeverity.critical);
      if (idx >= 0) {
        _memory.removeAt(idx);
      } else {
        _memory.removeAt(0);
      }
    }
  }

  static Future<void> _persist() async {
    if (disableHive || !_hiveReady) return;
    try {
      if (!Hive.isBoxOpen(kDiagnosticIncidentHiveBox)) {
        await Hive.openBox(kDiagnosticIncidentHiveBox);
      }
      final box = Hive.box(kDiagnosticIncidentHiveBox);
      await box.put(
        'incidents',
        _memory.map((i) => i.toJson(includeStack: false)).toList(),
      );
    } catch (e) {
      debugPrint('[DIAG-HISTORY] persist skipped type=${e.runtimeType}');
    }
  }
}
