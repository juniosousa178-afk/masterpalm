// lib/debug/bootstrap_diagnostics.dart

import 'package:flutter/foundation.dart';

/// Utilitário bem simples para marcar checkpoints durante o boot
/// e imprimir um dump do que aconteceu (com timestamps relativos).
final boot = BootProfiler._();

class BootProfiler {
  BootProfiler._();

  final _events = <_BootEvent>[];
  final _t0 = DateTime.now();

  void mark(String tag, [Object? payload]) {
    _events.add(_BootEvent(
      tag: tag,
      at: DateTime.now(),
      payload: payload,
    ));
    // log enxuto no console
    // ignore: avoid_print
    debugPrint('⏱️ [BOOT] ${tag.padRight(20)} +${_deltaNowMs()}ms'
        '${payload == null ? '' : '  => $payload'}');
  }

  String dump() {
    final buf = StringBuffer()
      ..writeln('──────────────── BOOT TRACE ────────────────');
    for (final e in _events) {
      final dt = e.at.difference(_t0).inMilliseconds.toString().padLeft(5);
      buf.writeln(
          '[$dt ms] ${e.tag}${e.payload == null ? '' : '  :: ${e.payload}'}');
    }
    buf.writeln('────────────────────────────────────────────');
    return buf.toString();
  }

  int _deltaNowMs() => DateTime.now().difference(_t0).inMilliseconds;
}

class _BootEvent {
  final String tag;
  final DateTime at;
  final Object? payload;
  _BootEvent({required this.tag, required this.at, this.payload});
}

/// Guarda o estado "Firebase pronto" e ajuda a diagnosticar acessos antecipados.
class FirebaseGuard {
  static bool _ready = false;

  /// Marca que o Firebase terminou de inicializar no bootstrap.
  static void markReady() {
    _ready = true;
    // ignore: avoid_print
    debugPrint('✅ [FirebaseGuard] ready = true');
  }

  /// Lança uma exceção amigável se alguma parte do app tocar Firebase antes da hora.
  /// Use assim dentro de Singletons/Services:
  ///
  ///   FirebaseGuard.require('MinhaClasse');
  ///
  static void require(String who) {
    if (_ready) return;
    final msg =
        '🔒 [FirebaseGuard] $who tentou acessar Firebase antes de inicializar. '
        'Espere o bootstrap finalizar (veja logs ⏱️ [BOOT] no console).';
    // ignore: avoid_print
    debugPrint(msg);
    // Opcional: em debug, podemos jogar uma StateError para ver o stack
    assert(() {
      throw StateError(msg);
    }());
  }
}
