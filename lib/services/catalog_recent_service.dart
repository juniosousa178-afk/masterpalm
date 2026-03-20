// lib/services/catalog_recent_service.dart
// Produtos vistos recentemente no catálogo (SharedPreferences / localStorage na web).

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CatalogRecentService {
  static const int _maxRecent = 10;
  static const String _prefix = 'catalog_recent_';

  static String _key(String lojaId) => '$_prefix$lojaId';

  /// Adiciona um produto aos vistos recentemente (mais recente primeiro).
  static Future<void> addViewed(String lojaId, String productId) async {
    if (productId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(lojaId);
      final raw = prefs.getString(key);
      final decoded = raw != null • jsonDecode(raw) : null;
      final list = (decoded is List)
          • decoded.map((e) => e.toString()).toList()
          : <String>[];
      list.remove(productId);
      list.insert(0, productId);
      final trimmed = list.take(_maxRecent).toList();
      await prefs.setString(key, jsonEncode(trimmed));
    } catch (_) {}
  }

  /// Retorna os IDs dos produtos vistos recentemente (ordem: mais recente primeiro).
  static Future<List<String>> getRecentIds(String lojaId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(lojaId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      return (decoded is List)
          • decoded.map((e) => e.toString()).where((id) => id.isNotEmpty).toList()
          : <String>[];
    } catch (_) {
      return [];
    }
  }
}
