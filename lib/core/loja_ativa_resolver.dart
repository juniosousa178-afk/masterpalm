// lib/core/loja_ativa_resolver.dart
// Loja operacional ativa (vendas, fiado, contas a receber, financeiro).
// Prioridade: sessão Hive alinhada ao Auth → loja do usuário (StoreResolverService).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../services/public_store_link_helper.dart';
import '../services/store_resolver_service.dart';
import '../utils/role_utils.dart';
import 'loja_id_adapter.dart';
import 'logger.dart';

/// Mensagem exibida quando não há loja operacional selecionada.
const String kErroSemLojaAtiva =
    'Nenhuma loja ativa selecionada. Selecione uma loja antes de vender.';

class LojaAtivaResolver {
  LojaAtivaResolver._();

  /// Prioridade operacional: sessão/config (mesmo usuário) → owner store (Firestore).
  static Future<String?> resolve({String origem = 'app'}) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = (user?.email ?? '').trim().toLowerCase();
    final perfil = RoleUtils.isRootEmail(email)
        ? UserRole.programador.name
        : (await RoleUtils.loadFromSession()).name;

    final fromSession = await _readSessionStoreId();
    if (fromSession != null && fromSession.isNotEmpty) {
      logD(
        '[LOJA-CTX] usuario=${user?.uid ?? "null"} email=$email perfil=$perfil '
        'lojaIdAtivo=$fromSession origem=$origem fonte=sessao',
      );
      return fromSession;
    }

    final owner = await StoreResolverService.resolveOwnerStore();
    final trimmed = (owner ?? '').trim();
    if (trimmed.isNotEmpty) {
      logD(
        '[LOJA-CTX] usuario=${user?.uid ?? "null"} email=$email perfil=$perfil '
        'lojaIdAtivo=$trimmed origem=$origem fonte=owner_store',
      );
      return trimmed;
    }

    logW(
      '[LOJA-CTX] usuario=${user?.uid ?? "null"} email=$email perfil=$perfil '
      'lojaIdAtivo=null origem=$origem fonte=none',
    );
    return null;
  }

  /// Exige loja operacional; usado em venda fiada/financeiro.
  static Future<String> requireActive({String origem = 'app'}) async {
    final id = await resolve(origem: origem);
    if (id == null || id.trim().isEmpty) {
      throw StateError(kErroSemLojaAtiva);
    }
    return id.trim();
  }

  /// Lê `store_id` da sessão/config quando o principal coincide com o Auth.
  static Future<String?> _readSessionStoreId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final authEmail = (user.email ?? '').trim().toLowerCase();
    if (authEmail.isEmpty) return null;

    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      final cfg = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');

      final principalEmail = (sessao.get('usuario_logado_email') ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final principalLegacy = (sessao.get('usuario_logado') ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final principal =
          principalEmail.isNotEmpty ? principalEmail : principalLegacy;

      if (principal.isEmpty || principal != authEmail) return null;

      final fromSessao = normalizeFromBox(sessao);
      if (fromSessao != null &&
          fromSessao.isNotEmpty &&
          isValidForPublicLink(fromSessao) &&
          !_isBlockedPlaceholder(fromSessao)) {
        return fromSessao.trim();
      }

      final fromConfig = normalizeFromBox(cfg);
      if (fromConfig != null &&
          fromConfig.isNotEmpty &&
          isValidForPublicLink(fromConfig) &&
          !_isBlockedPlaceholder(fromConfig)) {
        return fromConfig.trim();
      }

      final lastLoja = (cfg.get('last_loja_id') ?? '').toString().trim();
      if (lastLoja.isNotEmpty &&
          isValidForPublicLink(lastLoja) &&
          !_isBlockedPlaceholder(lastLoja)) {
        return lastLoja;
      }
    } catch (e) {
      logW('[LOJA-CTX] leitura sessao falhou (type=${e.runtimeType})');
    }
    return null;
  }

  /// Testável: valida candidato de loja da sessão sem I/O.
  static String? sessionStoreIfValid({
    required String? storeIdFromSessao,
    required String? storeIdFromConfig,
    required String? lastLojaIdFromConfig,
    required String principalSessao,
    required String authEmail,
  }) {
    if (authEmail.trim().isEmpty || principalSessao.trim().isEmpty) return null;
    if (authEmail.trim().toLowerCase() != principalSessao.trim().toLowerCase()) {
      return null;
    }
    for (final raw in [
      storeIdFromSessao,
      storeIdFromConfig,
      lastLojaIdFromConfig,
    ]) {
      final t = (raw ?? '').trim();
      if (t.isEmpty) continue;
      if (!isValidForPublicLink(t)) continue;
      if (_isBlockedPlaceholder(t)) continue;
      return t;
    }
    return null;
  }

  static bool _isBlockedPlaceholder(String id) {
    const blocked = {'minha-loja', 'minha_loja', 'masterpalm'};
    return blocked.contains(id.trim().toLowerCase());
  }
}
