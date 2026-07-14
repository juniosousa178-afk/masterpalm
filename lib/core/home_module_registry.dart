// M3.8 S2 — registry único de módulos (Home portal + telas por categoria + menu).

import 'package:flutter/material.dart';

import '../design_system/mp_tokens.dart';
import 'app_module_definition.dart';
import 'plan_matrix.dart';

/// Contexto de acesso para filtrar módulos.
class HomeModuleAccessContext {
  const HomeModuleAccessContext({
    required this.tipoUsuario,
    required this.permissoes,
    required this.planTier,
    required this.applyPlanGate,
  });

  final String tipoUsuario;
  final Map<String, bool> permissoes;
  final PlanAccessTier planTier;
  final bool applyPlanGate;

  bool get isAdminOrProgramador =>
      tipoUsuario == 'admin' || tipoUsuario == 'programador';
}

abstract final class HomeModuleRegistry {
  static const List<AppModuleDefinition> all = [
    // —— Operações ——
    AppModuleDefinition(
      id: 'estoque',
      title: 'Estoque',
      subtitle: 'Produtos',
      icon: Icons.inventory_2,
      route: '/estoque',
      category: HomeModuleCategory.operacoes,
      order: 10,
      permissionKey: 'estoque',
      keywords: ['inventario', 'produtos', 'estoque', 'sku'],
    ),
    AppModuleDefinition(
      id: 'fornecedores',
      title: 'Fornecedores',
      subtitle: 'Parceiros',
      icon: Icons.local_shipping,
      route: '/fornecedores',
      category: HomeModuleCategory.operacoes,
      order: 20,
      permissionKey: 'fornecedores',
      planFeature: PlanGateFeature.fornecedores,
      accent: Color(0xFFF59E0B),
    ),
    AppModuleDefinition(
      id: 'catalogo_interno',
      title: 'Catálogo interno',
      subtitle: 'Produtos / estoque',
      icon: Icons.menu_book_outlined,
      // Admin = Estoque (não CatalogoScreen legado).
      route: '/catalogo_interno',
      category: HomeModuleCategory.operacoes,
      order: 30,
      permissionKey: 'catalogo',
      keywords: ['catalogo interno', 'produtos', 'estoque', 'admin'],
    ),

    // —— Vendas ——
    AppModuleDefinition(
      id: 'vendas',
      title: 'Vendas',
      subtitle: 'PDV / histórico',
      icon: Icons.point_of_sale,
      route: '/vendas',
      category: HomeModuleCategory.vendas,
      order: 10,
      permissionKey: 'vendas',
      accent: Color(0xFF22C55E),
      keywords: ['pdv', 'nova venda', 'caixa', 'historico'],
    ),
    AppModuleDefinition(
      id: 'carrinhos_abandonados',
      title: 'Carrinhos abandonados',
      subtitle: 'Recuperação',
      icon: Icons.shopping_cart_outlined,
      route: '/carrinhos_abandonados',
      category: HomeModuleCategory.vendas,
      order: 20,
      planFeature: PlanGateFeature.carrinhosAbandonados,
      accent: Color(0xFFF59E0B),
      keywords: ['carrinho', 'abandonado', 'recuperacao', 'cart'],
    ),
    AppModuleDefinition(
      id: 'pre_pedidos',
      title: 'Pré-pedidos',
      subtitle: 'Pedidos',
      icon: Icons.receipt_long_outlined,
      route: '/pedidos',
      category: HomeModuleCategory.vendas,
      order: 30,
      planFeature: PlanGateFeature.pedidosPrePedidos,
    ),
    AppModuleDefinition(
      id: 'contas_receber',
      title: 'Contas a receber',
      subtitle: 'Fiado',
      icon: Icons.request_quote_outlined,
      route: '/contas_receber',
      category: HomeModuleCategory.vendas,
      order: 40,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.contasReceber,
    ),

    // —— Clientes ——
    AppModuleDefinition(
      id: 'clientes',
      title: 'Clientes',
      subtitle: 'Cadastros',
      icon: Icons.people,
      route: '/clientes',
      category: HomeModuleCategory.clientes,
      order: 10,
      permissionKey: 'clientes',
      accent: Color(0xFF8B5CF6),
      keywords: ['cliente', 'cadastro', 'crm'],
    ),
    AppModuleDefinition(
      id: 'historico_compras',
      title: 'Histórico de compras',
      subtitle: 'Clientes',
      icon: Icons.history,
      route: '/historico_cliente',
      category: HomeModuleCategory.clientes,
      order: 20,
      permissionKey: 'clientes',
      keywords: ['historico', 'compras', 'cliente'],
    ),
    AppModuleDefinition(
      id: 'insights_crm',
      title: 'Insights',
      subtitle: 'CRM leve',
      icon: Icons.lightbulb_outline,
      route: '/dashboard_insights',
      category: HomeModuleCategory.clientes,
      order: 30,
      planFeature: PlanGateFeature.insights,
      keywords: ['crm', 'insights', 'aniversario', 'cliente'],
    ),

    // —— Marketing ——
    AppModuleDefinition(
      id: 'marketing_hub',
      title: 'Painel Marketing',
      subtitle: 'Hub',
      icon: Icons.campaign_outlined,
      route: '/marketing_hub',
      category: HomeModuleCategory.marketing,
      order: 10,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.campanhasSorteios,
      accent: MpColors.marketing,
    ),
    AppModuleDefinition(
      id: 'campanhas_dashboard',
      title: 'Campanhas',
      subtitle: 'Dashboard',
      icon: Icons.insights,
      route: '/campanhas_dashboard',
      category: HomeModuleCategory.marketing,
      order: 20,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.campanhasSorteios,
      accent: MpColors.marketing,
      keywords: ['campanha', 'sorteio', 'dashboard', 'marketing'],
    ),
    AppModuleDefinition(
      id: 'roleta_dashboard',
      title: 'Roleta',
      subtitle: 'Dashboard',
      icon: Icons.casino_outlined,
      route: '/roleta_dashboard',
      category: HomeModuleCategory.marketing,
      order: 30,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.campanhasSorteios,
      accent: MpColors.roleta,
      keywords: ['roleta', 'premio', 'sorteio', 'giro'],
    ),
    AppModuleDefinition(
      id: 'roleta_historico',
      title: 'Histórico da roleta',
      subtitle: 'Logs',
      icon: Icons.history_toggle_off,
      route: '/roleta_historico',
      category: HomeModuleCategory.marketing,
      order: 35,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.campanhasSorteios,
      accent: MpColors.roleta,
      keywords: ['roleta', 'historico', 'logs'],
    ),
    AppModuleDefinition(
      id: 'marketing_estatisticas',
      title: 'Estatísticas',
      subtitle: 'Gráficos',
      icon: Icons.bar_chart_rounded,
      route: '/marketing_estatisticas',
      category: HomeModuleCategory.marketing,
      order: 40,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.campanhasSorteios,
      accent: MpColors.primary,
      keywords: ['estatisticas', 'graficos', 'campanha', 'conversao', 'receita'],
    ),
    AppModuleDefinition(
      id: 'catalogo_loja',
      title: 'Catálogo da loja',
      subtitle: 'Vitrine pública',
      icon: Icons.storefront_outlined,
      // Sentinel: abre /loja/{slug} via Home (não CatalogoScreen legado).
      route: '/catalogo_loja',
      category: HomeModuleCategory.marketing,
      order: 45,
      permissionKey: 'catalogo',
      keywords: [
        'catalogo',
        'publico',
        'vitrine',
        'loja online',
        'visualizar loja',
      ],
    ),
    AppModuleDefinition(
      id: 'campanhas_sorteio',
      title: 'Campanhas & Sorteios',
      subtitle: 'Gestão',
      icon: Icons.emoji_events_outlined,
      route: '/campanhas_sorteio',
      category: HomeModuleCategory.marketing,
      order: 50,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.campanhasSorteios,
      accent: Color(0xFFEC4899),
    ),
    AppModuleDefinition(
      id: 'fretes_cupons',
      title: 'Cupons & Fretes',
      subtitle: 'Cupons',
      icon: Icons.local_offer,
      route: '/fretes_cupons',
      category: HomeModuleCategory.marketing,
      order: 60,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.fretesCupons,
      accent: MpColors.info,
    ),
    AppModuleDefinition(
      id: 'motor_crescimento',
      title: 'Catálogo / Motor',
      subtitle: 'Crescimento',
      icon: Icons.rocket_launch_outlined,
      route: '/motor_crescimento',
      category: HomeModuleCategory.marketing,
      order: 70,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.motorCrescimento,
    ),

    // —— Financeiro ——
    AppModuleDefinition(
      id: 'financeiro',
      title: 'Financeiro',
      subtitle: 'Lançamentos',
      icon: Icons.payments_outlined,
      route: '/financeiro',
      category: HomeModuleCategory.financeiro,
      order: 10,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.financeiroLancamentos,
      accent: Color(0xFF0D9488),
    ),
    AppModuleDefinition(
      id: 'relatorio_financeiro',
      title: 'Relatórios',
      subtitle: 'Financeiro',
      icon: Icons.analytics,
      route: '/relatorio_financeiro',
      category: HomeModuleCategory.financeiro,
      order: 20,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.relatorioFinanceiroDetalhado,
      accent: Color(0xFFEC4899),
    ),
    AppModuleDefinition(
      id: 'resumo_metas',
      title: 'Resumo & Metas',
      subtitle: 'Hub',
      icon: Icons.trending_up,
      route: '/relatorios_financeiros',
      category: HomeModuleCategory.financeiro,
      order: 30,
      planFeature: PlanGateFeature.relatoriosFinanceirosHub,
      accent: Color(0xFF10B981),
    ),
    AppModuleDefinition(
      id: 'contas_pagar',
      title: 'Contas a pagar',
      subtitle: 'Despesas',
      icon: Icons.money_off_csred_outlined,
      route: '/contas_pagar',
      category: HomeModuleCategory.financeiro,
      order: 40,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.financeiroLancamentos,
    ),

    // —— Configurações ——
    AppModuleDefinition(
      id: 'loja_config',
      title: 'Configuração do catálogo',
      subtitle: 'Loja',
      icon: Icons.storefront_outlined,
      route: '/configuracoes_catalogo',
      category: HomeModuleCategory.configuracoes,
      order: 10,
      permissionKey: 'minha_loja',
      adminOrProgramadorOnly: true,
    ),
    AppModuleDefinition(
      id: 'config_carrinhos_abandonados',
      title: 'Carrinhos abandonados',
      subtitle: 'Tempo de abandono',
      icon: Icons.timer_outlined,
      route: '/config_carrinhos_abandonados',
      category: HomeModuleCategory.configuracoes,
      order: 20,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.carrinhosAbandonados,
      accent: Color(0xFFF59E0B),
    ),
    AppModuleDefinition(
      id: 'config_pagamentos',
      title: 'Integrações / Pagamentos',
      subtitle: 'Checkout',
      icon: Icons.credit_card,
      route: '/config/pagamentos',
      category: HomeModuleCategory.configuracoes,
      order: 30,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.configurarPagamentosOnline,
    ),
    AppModuleDefinition(
      id: 'planos',
      title: 'Planos',
      subtitle: 'Assinatura',
      icon: Icons.workspace_premium_outlined,
      route: '/planos',
      category: HomeModuleCategory.configuracoes,
      order: 40,
      adminOrProgramadorOnly: true,
      showInDrawer: true,
    ),
    AppModuleDefinition(
      id: 'vendedores',
      title: 'Usuários / Vendedores',
      subtitle: 'Equipe',
      icon: Icons.badge_outlined,
      route: '/vendedores',
      category: HomeModuleCategory.configuracoes,
      order: 50,
      adminOrProgramadorOnly: true,
      planFeature: PlanGateFeature.vendedores,
    ),
  ];

  static AppModuleDefinition? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<AppModuleDefinition> byCategory(HomeModuleCategory category) {
    final list = all.where((m) => m.category == category).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static List<HomeModuleCategory> get categoriesOrdered {
    final cats = HomeModuleCategory.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return cats;
  }

  /// Visível na Home (accordion), respeitando permissão/plano.
  static List<AppModuleDefinition> visibleForHome(HomeModuleAccessContext ctx) {
    return all.where((m) => m.showOnHome && isAllowed(m, ctx)).toList()
      ..sort((a, b) {
        final c = a.category.order.compareTo(b.category.order);
        if (c != 0) return c;
        return a.order.compareTo(b.order);
      });
  }

  /// Itens do drawer que existem no registry (mesma fonte da Home).
  static List<AppModuleDefinition> visibleForDrawer(HomeModuleAccessContext ctx) {
    return all.where((m) => m.showInDrawer && isAllowed(m, ctx)).toList()
      ..sort((a, b) {
        final c = a.category.order.compareTo(b.category.order);
        if (c != 0) return c;
        return a.order.compareTo(b.order);
      });
  }


  static List<AppModuleDefinition> byIds(
    Iterable<String> ids, {
    required HomeModuleAccessContext access,
  }) {
    final map = {for (final m in visibleForHome(access)) m.id: m};
    return [
      for (final id in ids)
        if (map.containsKey(id)) map[id]!,
    ];
  }

  /// Contagem de atalhos visíveis por categoria (badge "Vendas (6)").
  static Map<HomeModuleCategory, int> countVisibleByCategory(
    HomeModuleAccessContext ctx,
  ) {
    final map = <HomeModuleCategory, int>{};
    for (final m in visibleForHome(ctx)) {
      map[m.category] = (map[m.category] ?? 0) + 1;
    }
    return map;
  }

  static bool isAllowed(AppModuleDefinition m, HomeModuleAccessContext ctx) {
    if (m.adminOrProgramadorOnly && !ctx.isAdminOrProgramador) {
      if (m.permissionKey == null || ctx.permissoes[m.permissionKey!] != true) {
        return false;
      }
    }
    if (m.permissionKey != null &&
        !ctx.isAdminOrProgramador &&
        ctx.permissoes[m.permissionKey!] != true) {
      return false;
    }
    return true;
  }

  /// Bloqueado por plano (ainda visível, abre /planos).
  static bool isPlanLocked(AppModuleDefinition m, HomeModuleAccessContext ctx) {
    if (!ctx.applyPlanGate || m.planFeature == null) return false;
    return !PlanMatrix.allows(ctx.planTier, m.planFeature!);
  }

  /// Rotas com mais de um id no registry (deve ser vazio).
  static List<String> duplicateRoutes() {
    final byRoute = <String, List<String>>{};
    for (final m in all) {
      byRoute.putIfAbsent(m.route, () => []).add(m.id);
    }
    return byRoute.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toList();
  }

}
