import 'package:flutter/foundation.dart';

/// Logs discretos de tempo (`[BOOT]` / `[PRODUTO_FOTO]`).
/// Ativos em debug; em release web com `?diag=1`.
class BootPerfLog {
  BootPerfLog._();

  static final Stopwatch _boot = Stopwatch()..start();
  static final Map<String, int> _fotoStartMs = <String, int>{};

  static bool get _enabled =>
      kDebugMode ||
      (kIsWeb && Uri.base.queryParameters['diag'] == '1');

  static void resetBoot() {
    _boot
      ..reset()
      ..start();
    markBoot('main_start');
  }

  static void markBoot(String phase, {String? detail}) {
    if (!_enabled) return;
    debugPrint(
      '[BOOT][$phase] +${_boot.elapsedMilliseconds}ms'
      '${detail != null ? ' $detail' : ''}',
    );
  }

  static void fotoStart(String phase, {String? detail}) {
    if (!_enabled) return;
    _fotoStartMs[phase] = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[PRODUTO_FOTO][$phase]${detail != null ? ' $detail' : ''}');
  }

  static void fotoEnd(String phase, {String? detail}) {
    if (!_enabled) return;
    final t0 = _fotoStartMs.remove(phase);
    final elapsed = t0 == null
        ? '?'
        : '${DateTime.now().millisecondsSinceEpoch - t0}';
    debugPrint(
      '[PRODUTO_FOTO][$phase] ${elapsed}ms'
      '${detail != null ? ' $detail' : ''}',
    );
  }

  /// Evento pontual (sem par start/end), ex.: aviso de demora progressiva.
  static void fotoMark(String phase, {String? detail}) {
    if (!_enabled) return;
    debugPrint(
      '[PRODUTO_FOTO][$phase]'
      '${detail != null ? ' $detail' : ''}',
    );
  }
}
