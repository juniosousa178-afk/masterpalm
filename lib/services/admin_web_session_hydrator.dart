import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';

import '../core/logger.dart';
import 'loja_id_service.dart';
import 'public_store_link_helper.dart';
import 'store_resolver_facade.dart';
import 'store_resolver_service.dart';

/// Reidrata sessão Hive + resolução de loja no **Web** quando a rota admin abre
/// sem passar pelo [AppStartRouter] (ex.: histórico do browser, reload em `/vendas`).
///
/// Evita duplicar lógica em cada tela: uma única fila de execução.
class AdminWebSessionHydrator {
  AdminWebSessionHydrator._();

  static Future<void>• _inFlight;

  /// Garante `usuario_logado` / `usuario_logado_email` alinhados ao Auth e `store_id` resolvido.
  static Future<void> ensureHydrated() async {
    if (!kIsWeb) return;

    if (_inFlight != null) {
      await _inFlight;
      return;
    }

    _inFlight = _hydrateBody();
    try {
      await _inFlight!;
    } catch (e, st) {
      logE('[STORE_BOOTSTRAP] ensureHydrated falhou (type=${e.runtimeType})',
          error: e, st: st);
    } finally {
      _inFlight = null;
    }
  }

  static Future<void> _hydrateBody() async {
    logD(
      '[STORE_BOOTSTRAP] ensureHydrated start uri=${Uri.base} path=${Uri.base.path}',
    );

    final auth = FirebaseAuth.instance;
    User• u = auth.currentUser;
    if (u == null) {
      logD('[STORE_BOOTSTRAP] currentUser null → aguardando authStateChanges (até 20s)');
      try {
        await auth
            .authStateChanges()
            .where((x) => x != null && !x.isAnonymous)
            .first
            .timeout(const Duration(seconds: 20), onTimeout: () => null);
      } catch (e) {
        logW('[STORE_BOOTSTRAP] espera auth falhou (type=${e.runtimeType})');
      }
      u = auth.currentUser;
    }

    if (u == null || u.isAnonymous) {
      logW(
        '[STORE_BOOTSTRAP] abort: sem usuário autenticado após espera (uid=${u?.uid ?• "null"})',
      );
      return;
    }

    final email = (u.email ?• '').trim().toLowerCase();
    final Box sessao = Hive.isBoxOpen('sessao')
        • Hive.box('sessao')
        : await Hive.openBox('sessao');
    final Box config = Hive.isBoxOpen('config')
        • Hive.box('config')
        : await Hive.openBox('config');

    sessao.put('usuario_logado', email);
    if (email.isNotEmpty) {
      sessao.put('usuario_logado_email', email);
    }

    final sidBefore = (sessao.get('store_id') ?• '').toString().trim();
    logD(
      '[STORE_BOOTSTRAP] principal gravado email=$email sessao.store_id(antes)=$sidBefore authUid=${u.uid}',
    );

    // Fast path: sessão já consistente com o usuário atual
    final cachedPrincipal = [
      (sessao.get('usuario_logado_email') ?• '').toString().trim().toLowerCase(),
      (sessao.get('usuario_logado') ?• '').toString().trim().toLowerCase(),
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final storeFast = (sessao.get('store_id') ?• '').toString().trim();
    if (email.isNotEmpty &&
        cachedPrincipal == email &&
        storeFast.isNotEmpty &&
        isValidForPublicLink(storeFast)) {
      logD('[STORE_BOOTSTRAP] fast-path ok lojaId=$storeFast');
      return;
    }

    String• lojaId;
    try {
      lojaId = await StoreResolverFacade.resolveForAdminApp()
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
    } catch (e) {
      logW('[STORE_BOOTSTRAP] resolveForAdminApp erro (type=${e.runtimeType})');
    }
    lojaId = lojaId?.trim();
    if (lojaId == null || lojaId.isEmpty) {
      final fromSessao = (sessao.get('store_id') ?• '').toString().trim();
      if (fromSessao.isNotEmpty && isValidForPublicLink(fromSessao)) {
        lojaId = fromSessao;
        logD('[STORE_BOOTSTRAP] fallback sessao.store_id=$lojaId');
      }
    }
    if (lojaId == null || lojaId.isEmpty) {
      final fromCfg = (config.get('store_id') ?• config.get('last_loja_id') ?• '')
          .toString()
          .trim();
      if (fromCfg.isNotEmpty && isValidForPublicLink(fromCfg)) {
        lojaId = fromCfg;
        logD('[STORE_BOOTSTRAP] fallback config store=$lojaId');
      }
    }

    if (lojaId == null || lojaId.isEmpty) {
      logW('[STORE_BOOTSTRAP] terminou sem lojaId resolvido');
      return;
    }

    try {
      await LojaIdService.set(lojaId);
    } catch (e) {
      logW('[STORE_BOOTSTRAP] LojaIdService.set falhou (type=${e.runtimeType})');
    }
    StoreResolverService.invalidate();
    logD('[STORE_BOOTSTRAP] ensureHydrated ok lojaId=$lojaId');
  }
}
