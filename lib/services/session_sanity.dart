import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../utils/last_route_observer.dart';
import 'loja_id_service.dart';
import 'store_resolver_service.dart';
import 'store_context.dart';

class SessionSanity {
  static Future<void> fixIfNoFirebaseUser() async {
    // ✅ Verificar se Firebase foi inicializado antes de acessar Auth
    try {
      Firebase.app();
    } catch (e) {
      // Firebase não inicializado, não há usuário para verificar
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    // Se não tem usuário autenticado, não pode existir sessão "logada" local
    if (user == null) {
      debugPrint('🧹 [SESSION SANITY] Sem usuário Firebase - limpando sessão local');

      // ✅ CRÍTICO: Limpar caches em memória para evitar mistura multi-tenant
      StoreResolverService.invalidate();
      StoreContext.invalidate();

      final sessao = await Hive.openBox('sessao');
      final config = await Hive.openBox('config');

      // limpa APENAS o que causa "troca de loja/tipo"
      await sessao.delete('store_id');
      await sessao.delete('usuario_logado');
      await sessao.delete('tipo_usuario');
      await sessao.delete('is_root');

      await config.delete('store_id');
      await config.delete('store_slug');
      await config.delete('loja_slug');
      await config.delete('last_loja_id');

      await LojaIdService.clear();
      await LastRouteObserver.clearLastRoute();

      debugPrint('✅ [SESSION SANITY] Sessão local limpa');
    }
  }

  /// ✅ Limpa COMPLETAMENTE a sessão e cache local
  /// Use após consolidação de lojas ou quando precisar forçar nova resolução
  static Future<void> clearAllStoreCache() async {
    try {
      debugPrint('🧹 [SESSION SANITY] Limpando TODOS os caches de loja...');

      // ✅ CRÍTICO: Limpar caches em memória
      StoreResolverService.invalidate();
      await StoreResolverService.clear();
      StoreContext.invalidate();
      await StoreContext.clear();

      final sessao = await Hive.openBox('sessao');
      final config = await Hive.openBox('config');

      // Limpar todos os dados de loja
      await sessao.delete('store_id');
      await sessao.delete('usuario_logado');
      await sessao.delete('tipo_usuario');
      await sessao.delete('is_root');

      await config.delete('store_id');
      await config.delete('store_slug');
      await config.delete('loja_slug');
      await config.delete('last_loja_id');

      await LojaIdService.clear();
      await LastRouteObserver.clearLastRoute();

      debugPrint('✅ [SESSION SANITY] Cache de loja completamente limpo');
    } catch (e) {
      debugPrint('❌ [SESSION SANITY] Erro ao limpar cache (type=${e.runtimeType})');
    }
  }
}
