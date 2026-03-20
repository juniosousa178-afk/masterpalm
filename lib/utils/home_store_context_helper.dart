// lib/utils/home_store_context_helper.dart
// Helper local para a Home e atalhos inteligentes: separa lojaId interno e slug público.
// ✅ Mesma lógica da loja modelo: StoreResolver PRIMEIRO, Hive só como fallback (offline).
// No Web, Hive/IndexedDB é compartilhado; usar StoreResolver evita loja errada entre usuários.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../core/loja_id_adapter.dart';
import '../services/public_store_link_helper.dart';
import '../services/store_resolver_facade.dart';

/// Resultado do contexto de loja para a Home/atalhos.
/// [lojaIdInterno] = identificador para Hive, Firestore, Motor, Campanhas, Painel (admin).
/// [slugPublico] = identificador válido para link público e catálogo (pode ser igual ao interno).
class HomeStoreContext {
  final String lojaIdInterno;
  final String slugPublico;

  const HomeStoreContext({
    required this.lojaIdInterno,
    required this.slugPublico,
  });

  bool get temLojaInterno => lojaIdInterno.trim().isNotEmpty;
  bool get temSlugPublico => isValidForPublicLink(slugPublico);
}

/// Resolve contexto da loja ativa para a Home (leitura apenas).
/// Ordem: 1) StoreResolverFacade (Firestore users/usuarios), 2) Hive sessao (fallback offline).
Future<HomeStoreContext> resolveHomeStoreContext() async {
  String lojaIdInterno = '';
  try {
    final id = await StoreResolverFacade.resolveForAdminApp();
    final trimmed = (id ?• '').trim();
    if (isValidForPublicLink(trimmed)) {
      lojaIdInterno = trimmed;
      logD('[CATALOGO-CONTEXT] resolveHomeStoreContext: StoreResolver → $lojaIdInterno');
    }
  } catch (_) {}

  if (lojaIdInterno.isEmpty) {
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null) {
        // Sem auth: não usar Hive (pode ser loja de outra conta)
        return HomeStoreContext(lojaIdInterno: '', slugPublico: '');
      }
      final Box sessao = Hive.isBoxOpen('sessao')
          • Hive.box('sessao')
          : await Hive.openBox('sessao');
      final cachedUser = (sessao.get('usuario_logado') ?• '').toString().trim().toLowerCase();
      final currentEmail = (current.email ?• '').trim().toLowerCase();
      if (cachedUser.isEmpty || currentEmail != cachedUser) {
        // Sessão de outra conta: não usar
        return HomeStoreContext(lojaIdInterno: '', slugPublico: '');
      }
      final raw = normalizeFromBox(sessao);
      final trimmed = (raw ?• '').trim();
      if (isValidForPublicLink(trimmed)) {
        lojaIdInterno = trimmed;
        logD('[CATALOGO-CONTEXT] resolveHomeStoreContext: Hive fallback (user match) → $lojaIdInterno');
      }
    } catch (_) {}
  }

  String slugPublico = lojaIdInterno;
  if (!isValidForPublicLink(slugPublico)) slugPublico = '';

  return HomeStoreContext(
    lojaIdInterno: lojaIdInterno,
    slugPublico: slugPublico,
  );
}
