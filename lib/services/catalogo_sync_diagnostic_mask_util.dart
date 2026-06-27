// Mascaramento para diagnóstico local de sync de catálogo (sem PII).

class CatalogoSyncDiagnosticMaskUtil {
  CatalogoSyncDiagnosticMaskUtil._();

  static String mascararUid(String? uid) {
    final u = uid?.trim() ?? '';
    if (u.isEmpty) return '—';
    if (u.length <= 6) return '***';
    return '${u.substring(0, 4)}…${u.substring(u.length - 2)}';
  }

  static String mascararLojaId(String? lojaId) {
    final l = lojaId?.trim() ?? '';
    if (l.isEmpty) return '—';
    if (l.length <= 8) return '${l.substring(0, 2)}…';
    return '${l.substring(0, 6)}…';
  }

  static String mascararProdutoId(String? produtoId) {
    final p = produtoId?.trim() ?? '';
    if (p.isEmpty) return '—';
    if (p.length <= 10) return '${p.substring(0, 3)}…';
    return '${p.substring(0, 8)}…${p.substring(p.length - 2)}';
  }

  static String mascararPath(String? path) {
    final raw = path?.trim() ?? '';
    if (raw.isEmpty) return '—';
    final parts = raw.split('/');
    if (parts.length < 4) return raw;
    // lojas/{loja}/coleção/{produto}
    final masked = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final seg = parts[i];
      if (i == 1) {
        masked.add(mascararLojaId(seg));
      } else if (i == 3) {
        masked.add(mascararProdutoId(seg));
      } else {
        masked.add(seg);
      }
    }
    return masked.join('/');
  }

  static String attemptIdCurto(String attemptId) {
    final a = attemptId.trim();
    if (a.length <= 8) return a;
    return a.substring(0, 8);
  }

  static String sanitizarMensagemErro(Object? error) {
    if (error == null) return '';
    final raw = error.toString().trim();
    if (raw.isEmpty) return '';
    var msg = raw
        .replaceAll(RegExp(r'Bearer\s+\S+', caseSensitive: false), '[token]')
        .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
            '[jwt]');
    if (msg.length > 160) msg = '${msg.substring(0, 160)}…';
    return msg;
  }
}
