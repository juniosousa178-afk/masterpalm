// Rastreio do fluxo normal do catálogo (não confundir com netTest em main.dart).
// Web: grava `mp_catalog_normal_trace` (JSON) e alimenta UI com ?diag=1&traceCatalog=1

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;

/// Eventos e campos do carregamento público do [PublicCatalogScreen].
class CatalogNormalTrace {
  CatalogNormalTrace._();

  static final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  static final Map<String, Object?> _fields = <String, Object?>{};

  /// Limpa e inicia trilha (chamar no início de sessão de catálogo).
  static void beginSession(String lojaIdRaw, {bool preview = false}) {
    if (!kIsWeb) return;
    _events.clear();
    _fields.clear();
    mark('catalog.normal.start', <String, Object?>{
      'loja_id_raw': lojaIdRaw,
      'preview': preview,
    });
  }

  static void mark(String event, [Map<String, Object?>? data]) {
    if (!kIsWeb) return;
    _events.add(<String, Object?>{
      't': DateTime.now().toIso8601String(),
      'e': event,
      if (data != null && data.isNotEmpty) 'd': data,
    });
    while (_events.length > 120) {
      _events.removeAt(0);
    }
    persist();
  }

  static void setField(String key, Object? value) {
    if (!kIsWeb) return;
    if (value == null) {
      _fields.remove(key);
    } else {
      _fields[key] = value;
    }
    persist();
  }

  static Object? getField(String key) => _fields[key];

  static void persist() {
    if (!kIsWeb) return;
    try {
      final out = <String, Object?>{
        'events': _events,
        for (final e in _fields.entries) e.key: e.value,
      };
      plat.Web.localStorageSet('mp_catalog_normal_trace', jsonEncode(out));
    } catch (_) {}
  }

  /// Resumo monoespaçado para overlay / fallback (evitar PII: só IDs/ contagens/ flags).
  static String toDiagnosticString() {
    final b = StringBuffer();
    b.writeln('— campos —');
    final keys = _fields.keys.toList()..sort();
    for (final k in keys) {
      b.writeln('$k: ${_fields[k]}');
    }
    b.writeln('— últimos eventos —');
    final tail = _events.length > 18 ? _events.sublist(_events.length - 18) : _events;
    for (final e in tail) {
      b.write(e['t']);
      b.write(' ');
      b.write(e['e']);
      if (e['d'] != null) b.write('  d=${e['d']}');
      b.writeln();
    }
    return b.toString();
  }
}
