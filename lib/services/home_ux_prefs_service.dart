// M3.8 S2-R4 — preferências locais da Home (Hive + memória p/ testes).

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';

/// Favoritos + última categoria aberta — por loja.
class HomeUxPrefsService {
  HomeUxPrefsService._();

  static const int maxFavorites = 6;
  static const String _kFavorites = 'favoriteModuleIds';
  static const String _kOpenCategory = 'openCategoryId';

  /// Store em memória para testes (sem tocar Hive).
  static final Map<String, Map<String, dynamic>> debugMemory = {};

  static bool useDebugMemory = false;

  static void resetDebugMemory() {
    debugMemory.clear();
    useDebugMemory = false;
  }

  static Future<Box> _box(String lojaId) async {
    final name = HiveBoxNames.homeUx(lojaId);
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }

  static Map<String, dynamic> _mem(String lojaId) =>
      debugMemory.putIfAbsent(lojaId, () => <String, dynamic>{});

  static Future<List<String>> getFavorites(String lojaId) async {
    if (lojaId.trim().isEmpty) return const [];
    try {
      if (useDebugMemory) {
        final raw = _mem(lojaId)[_kFavorites];
        if (raw is! List) return const [];
        return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
      final box = await _box(lojaId);
      final raw = box.get(_kFavorites);
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> setFavorites(
    String lojaId,
    List<String> ids,
  ) async {
    final unique = <String>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (!unique.contains(id)) unique.add(id);
      if (unique.length >= maxFavorites) break;
    }
    if (useDebugMemory) {
      _mem(lojaId)[_kFavorites] = unique;
      return unique;
    }
    final box = await _box(lojaId);
    await box.put(_kFavorites, unique);
    return unique;
  }

  static Future<List<String>> toggleFavorite(
    String lojaId,
    String moduleId,
  ) async {
    final current = List<String>.from(await getFavorites(lojaId));
    if (current.contains(moduleId)) {
      current.remove(moduleId);
    } else {
      if (current.length >= maxFavorites) {
        throw StateError('Limite de $maxFavorites favoritos');
      }
      current.add(moduleId);
    }
    return setFavorites(lojaId, current);
  }

  static Future<bool> isFavorite(String lojaId, String moduleId) async {
    final list = await getFavorites(lojaId);
    return list.contains(moduleId);
  }

  static Future<String?> getOpenCategoryId(String lojaId) async {
    if (lojaId.trim().isEmpty) return null;
    try {
      if (useDebugMemory) {
        final v = _mem(lojaId)[_kOpenCategory]?.toString().trim() ?? '';
        return v.isEmpty ? null : v;
      }
      final box = await _box(lojaId);
      final v = box.get(_kOpenCategory);
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setOpenCategoryId(String lojaId, String? categoryId) async {
    if (lojaId.trim().isEmpty) return;
    if (useDebugMemory) {
      if (categoryId == null || categoryId.isEmpty) {
        _mem(lojaId).remove(_kOpenCategory);
      } else {
        _mem(lojaId)[_kOpenCategory] = categoryId;
      }
      return;
    }
    final box = await _box(lojaId);
    if (categoryId == null || categoryId.isEmpty) {
      await box.delete(_kOpenCategory);
    } else {
      await box.put(_kOpenCategory, categoryId);
    }
  }
}
