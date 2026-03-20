// Salva a rota atual para restaurar quando o app voltar do segundo plano (cold start).
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String _keyLastRoute = 'last_route_before_background';

/// Rotas que podem ser restauradas ao reabrir o app (não restaura /login, /, etc.)
const Set<String> _restorableRoutes = {
  '/home',
  '/vendas',
  '/clientes',
  '/estoque',
  '/pedidos',
  '/pedidos_pendentes',
  '/configuracoes_catalogo',
  '/relatorios',
  '/relatorio_financeiro',
  '/relatorios_financeiros',
  '/relatorio_mais_vendidos',
  '/backup',
  '/fornecedores',
  '/catalogo',
  '/cadastro_catalogo',
  '/fretes_cupons',
  '/campanhas_sorteio',
  '/metas_comissoes',
  '/notas_fiscais',
  '/config/pagamentos',
  '/config-pagamentos',
  '/admin_sync',
  '/diagnostico',
  '/ajuda',
  '/plano',
  '/planos',
  '/vendedores',
  '/cadastro_usuarios',
  '/permissoes',
  '/permissao',
};

class LastRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>• previousRoute) {
    _saveRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>• previousRoute) {
    if (previousRoute != null) _saveRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>• newRoute, Route<dynamic>• oldRoute}) {
    if (newRoute != null) _saveRoute(newRoute);
  }

  void _saveRoute(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    if (!_restorableRoutes.contains(name)) return;
    try {
      if (Hive.isBoxOpen('sessao')) {
        Hive.box('sessao').put(_keyLastRoute, name);
      }
    } catch (_) {}
  }

  /// Limpa a última rota salva (chame no logout/login para evitar contaminação entre contas).
  static Future<void> clearLastRoute() async {
    try {
      await Hive.openBox('sessao');
      Hive.box('sessao').delete(_keyLastRoute);
    } catch (_) {}
  }

  /// Retorna a última rota salva (para restaurar no cold start) e opcionalmente remove.
  static Future<String?> getAndClearLastRoute() async {
    try {
      await Hive.openBox('sessao');
      final box = Hive.box('sessao');
      final route = (box.get(_keyLastRoute) as String?)?.trim();
      if (route != null && route.isNotEmpty && _restorableRoutes.contains(route)) {
        box.delete(_keyLastRoute);
        return route;
      }
      box.delete(_keyLastRoute);
    } catch (_) {}
    return null;
  }
}
