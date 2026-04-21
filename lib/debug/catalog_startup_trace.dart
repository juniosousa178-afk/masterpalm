import 'dart:convert';

import '../core/logger.dart';

/// Trace mecânico para startup do catálogo via link.
/// Apenas observabilidade: não altera fluxo/timeout/query.
class CatalogStartupTrace {
  CatalogStartupTrace._();

  static final Stopwatch _sw = Stopwatch()..start();
  static final Map<String, int> _openSpansMs = <String, int>{};
  static int _seq = 0;

  static int nowMs() => _sw.elapsedMilliseconds;

  static void mark(
    String event, {
    Map<String, Object?>? data,
  }) {
    _seq += 1;
    final payload = <String, Object?>{
      'seq': _seq,
      'event': event,
      't_ms': nowMs(),
      if (data != null) ...data,
    };
    logD('[CAT_START] ${jsonEncode(payload)}');
  }

  static void spanStart(
    String name, {
    Map<String, Object?>? data,
  }) {
    final t0 = nowMs();
    _openSpansMs[name] = t0;
    mark('$name.start', data: data);
  }

  static void spanEnd(
    String name, {
    Map<String, Object?>? data,
  }) {
    final t1 = nowMs();
    final t0 = _openSpansMs.remove(name);
    mark(
      '$name.end',
      data: <String, Object?>{
        'dur_ms': t0 == null ? null : (t1 - t0),
        if (data != null) ...data,
      },
    );
  }
}
