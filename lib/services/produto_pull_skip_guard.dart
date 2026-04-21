// lib/services/produto_pull_skip_guard.dart
//
// Quando a exclusão local falha ao gravar `pendingSoftDelete` no Firestore (offline, erro
// de rede) ou o produto não tinha [idFirebase] preenchido, o pull recriaria o item.
// Este guard persiste docIds/slugs a ignorar no [syncFirestoreToHive] até o doc sumir
// da nuvem ou o usuário desfazer a exclusão. Web e Android usam o mesmo prefs.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';

class _LojaSkip {
  final Set<String> docIds;
  final Set<String> slugs;

  _LojaSkip({required this.docIds, required this.slugs});

  Map<String, dynamic> toJson() => {
        'docIds': docIds.toList(),
        'slugs': slugs.toList(),
      };

  static _LojaSkip fromJson(Map<String, dynamic> m) {
    final ids = <String>{};
    final slugs = <String>{};
    final rawIds = m['docIds'];
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) ids.add(s);
      }
    }
    final rawSlugs = m['slugs'];
    if (rawSlugs is List) {
      for (final e in rawSlugs) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) slugs.add(s);
      }
    }
    return _LojaSkip(docIds: ids, slugs: slugs);
  }
}

/// Evita que o Firestore → Hive recrie produtos recém-excluídos localmente quando o
/// tombstone remoto não foi aplicado.
class ProdutoPullSkipGuard {
  ProdutoPullSkipGuard._();

  static const _prefsKey = 'produto_pull_skip_guard_v1';

  static Future<Map<String, _LojaSkip>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, _LojaSkip>{};
      decoded.forEach((k, v) {
        final loja = k?.toString() ?? '';
        if (loja.isEmpty) return;
        if (v is Map) {
          out[loja] = _LojaSkip.fromJson(Map<String, dynamic>.from(v));
        }
      });
      return out;
    } catch (e) {
      if (kDebugMode) {
        logW('⚠️ [PULL-SKIP-GUARD] JSON inválido: $e');
      }
      return {};
    }
  }

  static Future<void> _saveAll(Map<String, _LojaSkip> all) async {
    final prefs = await SharedPreferences.getInstance();
    if (all.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    final enc = <String, dynamic>{};
    all.forEach((k, v) {
      if (v.docIds.isNotEmpty || v.slugs.isNotEmpty) {
        enc[k] = v.toJson();
      }
    });
    if (enc.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(enc));
    }
  }

  static Future<void> addDocId(String lojaId, String docId) async {
    final id = docId.trim();
    if (lojaId.trim().isEmpty || id.isEmpty) return;
    final all = await _loadAll();
    final loja = lojaId.trim();
    final cur = all[loja] ?? _LojaSkip(docIds: {}, slugs: {});
    cur.docIds.add(id);
    all[loja] = cur;
    await _saveAll(all);
  }

  static Future<void> addSlug(String lojaId, String slug) async {
    final s = slug.trim();
    if (lojaId.trim().isEmpty || s.isEmpty) return;
    final all = await _loadAll();
    final loja = lojaId.trim();
    final cur = all[loja] ?? _LojaSkip(docIds: {}, slugs: {});
    cur.slugs.add(s);
    all[loja] = cur;
    await _saveAll(all);
  }

  /// Remove entradas após exclusão remota confirmada ou desfazer exclusão.
  static Future<void> removeForProduct({
    required String lojaId,
    String? docId,
    String? slug,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    final all = await _loadAll();
    final cur = all[loja];
    if (cur == null) return;
    final d = docId?.trim();
    if (d != null && d.isNotEmpty) cur.docIds.remove(d);
    final sl = slug?.trim();
    if (sl != null && sl.isNotEmpty) cur.slugs.remove(sl);
    if (cur.docIds.isEmpty && cur.slugs.isEmpty) {
      all.remove(loja);
    } else {
      all[loja] = cur;
    }
    await _saveAll(all);
  }

  static Future<bool> shouldSkipDoc({
    required String lojaId,
    required String docId,
  }) async {
    final id = docId.trim();
    if (lojaId.trim().isEmpty || id.isEmpty) return false;
    final all = await _loadAll();
    return all[lojaId.trim()]?.docIds.contains(id) ?? false;
  }

  /// Só para ramo “criar novo Hive a partir do doc” (evita fantasma sem id local).
  static Future<bool> shouldSkipNewBySlug({
    required String lojaId,
    required String slug,
  }) async {
    final s = slug.trim();
    if (lojaId.trim().isEmpty || s.isEmpty) return false;
    final all = await _loadAll();
    return all[lojaId.trim()]?.slugs.contains(s) ?? false;
  }

  /// Remove docIds cujo documento já não existe no snapshot remoto; remove slugs que
  /// não aparecem em nenhum doc retornado.
  static Future<void> pruneAfterPull({
    required String lojaId,
    required Set<String> remoteDocIds,
    required Iterable<Map<String, dynamic>> remoteDocData,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    final all = await _loadAll();
    final cur = all[loja];
    if (cur == null) return;

    cur.docIds.removeWhere((id) => !remoteDocIds.contains(id));

    final slugsPresentes = <String>{};
    for (final m in remoteDocData) {
      final sl = m['slug']?.toString().trim() ?? '';
      if (sl.isNotEmpty) slugsPresentes.add(sl);
    }
    cur.slugs.removeWhere((s) => !slugsPresentes.contains(s));

    if (cur.docIds.isEmpty && cur.slugs.isEmpty) {
      all.remove(loja);
    } else {
      all[loja] = cur;
    }
    await _saveAll(all);
  }
}
