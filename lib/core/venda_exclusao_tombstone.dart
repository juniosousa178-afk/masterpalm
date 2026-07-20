// Tombstone de vendas excluídas (soft-delete) para métricas/meta/comissão.
// Evita que venda reapareça via sync/Hive e continue contando.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/venda.dart';

abstract final class VendaExclusaoTombstone {
  VendaExclusaoTombstone._();

  static const _prefix = 'venda_excl_tombstone_v1_';

  @visibleForTesting
  static final Map<String, Set<String>> debugMemory = {};

  static String _key(String lojaId) => '$_prefix${lojaId.trim()}';

  static String? idCanonico(Venda v) {
    final fb = (v.idFirebase ?? '').trim();
    if (fb.isNotEmpty) return fb;
    final k = v.key;
    if (k is int && k >= 0) return 'hive_$k';
    return null;
  }

  static Future<void> registrar({
    required String lojaId,
    String? idFirebase,
    int? hiveKey,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    final ids = <String>{
      if ((idFirebase ?? '').trim().isNotEmpty) idFirebase!.trim(),
      if (hiveKey != null && hiveKey >= 0) 'hive_$hiveKey',
    };
    if (ids.isEmpty) return;

    debugMemory.putIfAbsent(lid, () => {}).addAll(ids);

    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getStringList(_key(lid)) ?? const <String>[];
      final merged = {...prev, ...ids}.toList();
      await prefs.setStringList(_key(lid), merged);
    } catch (_) {}
  }

  static Future<void> remover({
    required String lojaId,
    String? idFirebase,
    int? hiveKey,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;
    final ids = <String>{
      if ((idFirebase ?? '').trim().isNotEmpty) idFirebase!.trim(),
      if (hiveKey != null && hiveKey >= 0) 'hive_$hiveKey',
    };
    debugMemory[lid]?.removeAll(ids);
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getStringList(_key(lid)) ?? const <String>[];
      final next = prev.where((e) => !ids.contains(e)).toList();
      await prefs.setStringList(_key(lid), next);
    } catch (_) {}
  }

  static Future<Set<String>> idsParaLoja(String lojaId) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return {};
    final mem = debugMemory[lid] ?? {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final disk = prefs.getStringList(_key(lid)) ?? const <String>[];
      return {...mem, ...disk};
    } catch (_) {
      return {...mem};
    }
  }

  /// true se a venda está tombstoned (excluída).
  static bool vendaEstaTombstoned(Venda v, Set<String> tombstones) {
    if (tombstones.isEmpty) return false;
    final id = idCanonico(v);
    if (id != null && tombstones.contains(id)) return true;
    final fb = (v.idFirebase ?? '').trim();
    if (fb.isNotEmpty && tombstones.contains(fb)) return true;
    return false;
  }

  @visibleForTesting
  static void resetForTests() => debugMemory.clear();
}
