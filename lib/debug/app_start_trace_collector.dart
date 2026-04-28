import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:master_palm/web/platform_stub.dart' if (dart.library.html) 'package:master_palm/web/platform_web.dart' as web_plat;

/// Fases do arranque do app web — `?diag=1&appStartTrace=1` (não depender do console).
class AppStartTraceCollector {
  AppStartTraceCollector._();

  static int _t0 = DateTime.now().millisecondsSinceEpoch;
  static final List<Map<String, Object?>> _entries = <Map<String, Object?>>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void clear() {
    _t0 = DateTime.now().millisecondsSinceEpoch;
    _entries.clear();
    revision.value = revision.value + 1;
  }

  static void mark(String phase, {String? detail, String? finalDecision}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _entries.add(<String, Object?>{
      'tMs': now - _t0,
      'phase': phase,
      if (detail != null) 'detail': detail,
      if (finalDecision != null) 'finalDecision': finalDecision,
    });
    if (kIsWeb) {
      try {
        final lines = <String>[];
        for (final e in _entries) {
          lines.add(
            'appStart.phase=${e['phase']} +${e['tMs']}ms'
            '${e['detail'] != null ? ' ${e['detail']}' : ''}'
            '${e['finalDecision'] != null ? ' => ${e['finalDecision']}' : ''}',
          );
        }
        web_plat.Web.localStorageSet('mp_app_start_trace', lines.join('\n'));
      } catch (_) {}
    }
    revision.value = revision.value + 1;
  }

  static void persistError(String source, Object error, StackTrace st) {
    if (!kIsWeb) return;
    try {
      final payload = jsonEncode(<String, Object?>{
        'source': source,
        'error': error.toString(),
        'stack': st.toString(),
        'trace': _entries,
      });
      web_plat.Web.localStorageSet('mp_last_runtime_error', payload);
    } catch (_) {}
  }

  static String dumpText() {
    if (_entries.isEmpty) return 'appStart=(sem eventos ainda)';
    final b = StringBuffer();
    for (final e in _entries) {
      b.writeln(
        'appStart.phase=${e['phase']} +${e['tMs']}ms'
        '${e['detail'] != null ? ' | ${e['detail']}' : ''}'
        '${e['finalDecision'] != null ? ' => final=${e['finalDecision']}' : ''}',
      );
    }
    return b.toString().trimRight();
  }
}
