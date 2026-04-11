// Preferências de UI do módulo financeiro (SharedPreferences), escopadas por usuário + loja.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../financeiro/financeiro_constants.dart';

/// Dados restaurados ao abrir a gestão financeira (sem mês — mês sempre civil atual no cold start).
class FinanceiroUiPrefsData {
  const FinanceiroUiPrefsData({
    required this.visaoCompetencia,
    this.filtroStatus,
    this.filtroTipoGrupo,
  });

  /// `true` = lista por competência; `false` = por pagamento (padrão).
  final bool visaoCompetencia;
  final String? filtroStatus;
  final String? filtroTipoGrupo;

  static const FinanceiroUiPrefsData padrao = FinanceiroUiPrefsData(
    visaoCompetencia: false,
  );
}

abstract final class FinanceiroUiPrefsService {
  static const String _kVisao = 'visao';
  static const String _kStatus = 'status';
  static const String _kTipo = 'tipo';

  /// Mesmo valor usado no dropdown da gestão financeira (equipe + pró-labore).
  static const String filtroGrupoEquipe = '__equipe__';

  /// Identificador estável para escopo de prefs (Firebase uid ou sessão).
  static Future<String> resolveUserKey() async {
    try {
      final u = FirebaseAuth.instance.currentUser?.uid;
      if (u != null && u.isNotEmpty) {
        return 'fb_${u.trim()}';
      }
    } catch (_) {}
    try {
      final box =
          Hive.isBoxOpen('sessao') ? Hive.box<dynamic>('sessao') : await Hive.openBox<dynamic>('sessao');
      final s = (box.get('usuario_logado') ?? '').toString().trim();
      if (s.isNotEmpty) {
        return 's_${_safeKeyPart(s)}';
      }
    } catch (_) {}
    return 'unknown';
  }

  static String _safeKeyPart(String s) {
    if (s.isEmpty) return 'x';
    return s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  /// Prefixo nulo se [lojaId] vazio — não persistir nem ler.
  static String? _prefix({required String lojaId, required String userKey}) {
    final l = lojaId.trim();
    if (l.isEmpty) return null;
    final u = userKey.trim().isEmpty ? 'unknown' : _safeKeyPart(userKey);
    return 'fin_ui_v2_${u}_${_safeKeyPart(l)}';
  }

  static Future<FinanceiroUiPrefsData> load({
    required String lojaId,
    String? userKey,
  }) async {
    try {
      final uk = userKey ?? await resolveUserKey();
      final prefix = _prefix(lojaId: lojaId, userKey: uk);
      if (prefix == null) return FinanceiroUiPrefsData.padrao;

      final p = await SharedPreferences.getInstance();
      final visao = p.getBool('$prefix$_kVisao') ?? false;

      String? st = p.getString('$prefix$_kStatus');
      if (st != null &&
          st != FinanceiroStatusLancamento.pago &&
          st != FinanceiroStatusLancamento.pendente) {
        st = null;
      }

      String? tipo = p.getString('$prefix$_kTipo');
      if (tipo != null &&
          tipo != filtroGrupoEquipe &&
          !FinanceiroTipoLancamento.todos.contains(tipo)) {
        tipo = null;
      }

      return FinanceiroUiPrefsData(
        visaoCompetencia: visao,
        filtroStatus: st,
        filtroTipoGrupo: tipo,
      );
    } catch (_) {
      return FinanceiroUiPrefsData.padrao;
    }
  }

  static Future<void> save({
    required bool visaoCompetencia,
    String? filtroStatus,
    String? filtroTipoGrupo,
    required String lojaId,
    String? userKey,
  }) async {
    try {
      final uk = userKey ?? await resolveUserKey();
      final prefix = _prefix(lojaId: lojaId, userKey: uk);
      if (prefix == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$prefix$_kVisao', visaoCompetencia);
      if (filtroStatus == null) {
        await prefs.remove('$prefix$_kStatus');
      } else {
        await prefs.setString('$prefix$_kStatus', filtroStatus);
      }
      if (filtroTipoGrupo == null || filtroTipoGrupo.isEmpty) {
        await prefs.remove('$prefix$_kTipo');
      } else {
        await prefs.setString('$prefix$_kTipo', filtroTipoGrupo);
      }
    } catch (_) {}
  }
}
