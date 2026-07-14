// M3.8 S2-R4 — pesquisa global de módulos da Home.

import 'package:diacritic/diacritic.dart';

import 'app_module_definition.dart';
import 'home_module_registry.dart';

abstract final class HomeModuleSearch {
  static String normalize(String input) => removeDiacritics(input)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Busca em título, subtítulo, categoria, rota e keywords.
  static List<AppModuleDefinition> search(
    String query, {
    required HomeModuleAccessContext access,
    int limit = 12,
  }) {
    final q = normalize(query);
    if (q.isEmpty) return const [];
    final visible = HomeModuleRegistry.visibleForHome(access);
    final scored = <({AppModuleDefinition m, int score})>[];
    for (final m in visible) {
      final blob = normalize(m.searchBlob);
      if (!blob.contains(q) && !normalize(m.title).startsWith(q)) {
        // match por palavra
        final words = q.split(' ');
        if (!words.every((w) => w.isEmpty || blob.contains(w))) continue;
      }
      var score = 0;
      if (normalize(m.title).contains(q)) score += 40;
      if (normalize(m.title).startsWith(q)) score += 20;
      if ((m.subtitle != null) && normalize(m.subtitle!).contains(q)) {
        score += 15;
      }
      if (normalize(m.category.title).contains(q)) score += 10;
      if (m.route.toLowerCase().contains(q)) score += 8;
      for (final k in m.keywords) {
        if (normalize(k).contains(q)) score += 12;
      }
      if (score == 0 && blob.contains(q)) score = 5;
      if (score > 0) scored.add((m: m, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.m).toList();
  }
}
