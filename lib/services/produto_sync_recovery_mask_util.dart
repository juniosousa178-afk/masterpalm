// Mascaramento de dados sensíveis para UI/logs da recuperação assistida.

class ProdutoSyncRecoveryMaskUtil {
  ProdutoSyncRecoveryMaskUtil._();

  static String mascararUid(String? uid) {
    final u = uid?.trim() ?? '';
    if (u.isEmpty) return '—';
    if (u.length <= 6) return '***';
    return '${u.substring(0, 4)}…${u.substring(u.length - 2)}';
  }

  static String mascararNome(String? nome) {
    final n = nome?.trim() ?? '';
    if (n.isEmpty) return '(sem nome)';
    if (n.length <= 3) return '***';
    return '${n.substring(0, 2)}…';
  }

  static String mascararLojaId(String? lojaId) {
    final l = lojaId?.trim() ?? '';
    if (l.isEmpty) return '—';
    if (l.length <= 8) return l;
    return '${l.substring(0, 6)}…';
  }
}
