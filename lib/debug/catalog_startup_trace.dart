import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import 'catalog_startup_trace_web_sink.dart'
    if (dart.library.html) 'catalog_startup_trace_web_sink_web.dart'
    as web_sink;

/// Trace mecânico para startup do catálogo via link.
/// Apenas observabilidade: não altera fluxo/timeout/query.
class CatalogStartupTrace {
  CatalogStartupTrace._();

  static final Stopwatch _sw = Stopwatch()..start();
  static final Map<String, int> _openSpansMs = <String, int>{};
  static final List<Map<String, Object?>> _simpleEvents =
      <Map<String, Object?>>[];
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  static int _seq = 0;
  static bool _summaryPrinted = false;

  static int nowMs() => _sw.elapsedMilliseconds;
  static ValueListenable<int> get revisionListenable => _revision;
  static List<Map<String, Object?>> eventsSnapshot() =>
      List<Map<String, Object?>>.unmodifiable(_simpleEvents);

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
    _recordWebFallback(event: event, tMs: payload['t_ms'] as int);
    _maybePublishSummary(event: event);
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

  static void _recordWebFallback({
    required String event,
    required int tMs,
  }) {
    _simpleEvents.add(<String, Object?>{
      'event': event,
      't_ms': tMs,
    });
    _revision.value = _revision.value + 1;
    web_sink.publishCatStartTrace(_simpleEvents);
  }

  static void _maybePublishSummary({required String event}) {
    if (_summaryPrinted) return;
    if (event != 'CAT_START.catalog_interactive') return;
    _summaryPrinted = true;
    final summary = <String, Object?>{
      'count': _simpleEvents.length,
      'events': _simpleEvents,
    };
    web_sink.publishCatStartSummary(summary);
    if (kDebugMode) {
      logD('[CAT_START_SUMMARY] ${jsonEncode(summary)}');
    }
  }
}
