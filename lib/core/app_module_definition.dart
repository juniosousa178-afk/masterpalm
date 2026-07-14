// M3.8 S2-R4 — definição canônica de módulo (Home + menu + busca).

import 'package:flutter/material.dart';

import 'plan_matrix.dart';

enum HomeModuleCategory {
  operacoes,
  vendas,
  clientes,
  marketing,
  financeiro,
  configuracoes,
}

extension HomeModuleCategoryX on HomeModuleCategory {
  String get id {
    switch (this) {
      case HomeModuleCategory.operacoes:
        return 'operacoes';
      case HomeModuleCategory.vendas:
        return 'vendas';
      case HomeModuleCategory.clientes:
        return 'clientes';
      case HomeModuleCategory.marketing:
        return 'marketing';
      case HomeModuleCategory.financeiro:
        return 'financeiro';
      case HomeModuleCategory.configuracoes:
        return 'configuracoes';
    }
  }

  String get title {
    switch (this) {
      case HomeModuleCategory.operacoes:
        return 'Operações';
      case HomeModuleCategory.vendas:
        return 'Vendas';
      case HomeModuleCategory.clientes:
        return 'Clientes';
      case HomeModuleCategory.marketing:
        return 'Marketing';
      case HomeModuleCategory.financeiro:
        return 'Financeiro';
      case HomeModuleCategory.configuracoes:
        return 'Configurações';
    }
  }

  IconData get icon {
    switch (this) {
      case HomeModuleCategory.operacoes:
        return Icons.inventory_2_outlined;
      case HomeModuleCategory.vendas:
        return Icons.point_of_sale_outlined;
      case HomeModuleCategory.clientes:
        return Icons.people_outline;
      case HomeModuleCategory.marketing:
        return Icons.campaign_outlined;
      case HomeModuleCategory.financeiro:
        return Icons.account_balance_wallet_outlined;
      case HomeModuleCategory.configuracoes:
        return Icons.settings_outlined;
    }
  }

  Color get accent {
    switch (this) {
      case HomeModuleCategory.operacoes:
        return const Color(0xFF6366F1);
      case HomeModuleCategory.vendas:
        return const Color(0xFF22C55E);
      case HomeModuleCategory.clientes:
        return const Color(0xFF8B5CF6);
      case HomeModuleCategory.marketing:
        return const Color(0xFFEC4899);
      case HomeModuleCategory.financeiro:
        return const Color(0xFF0D9488);
      case HomeModuleCategory.configuracoes:
        return const Color(0xFF0EA5E9);
    }
  }

  int get order {
    switch (this) {
      case HomeModuleCategory.operacoes:
        return 10;
      case HomeModuleCategory.vendas:
        return 20;
      case HomeModuleCategory.clientes:
        return 30;
      case HomeModuleCategory.marketing:
        return 40;
      case HomeModuleCategory.financeiro:
        return 50;
      case HomeModuleCategory.configuracoes:
        return 60;
    }
  }
}

/// Módulo navegável do app (fonte única Home + menu lateral + busca).
class AppModuleDefinition {
  const AppModuleDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.route,
    required this.category,
    required this.order,
    this.subtitle,
    this.keywords = const [],
    this.permissionKey,
    this.planFeature,
    this.adminOrProgramadorOnly = false,
    this.showOnHome = true,
    this.showInDrawer = true,
    this.accent,
  });

  final String id;
  final String title;
  final IconData icon;
  final String route;
  final HomeModuleCategory category;
  final int order;
  final String? subtitle;
  /// Termos extras para a pesquisa global da Home.
  final List<String> keywords;
  final String? permissionKey;
  final PlanGateFeature? planFeature;
  final bool adminOrProgramadorOnly;
  final bool showOnHome;
  final bool showInDrawer;
  final Color? accent;

  Color get effectiveAccent => accent ?? category.accent;

  /// Texto indexável (título, subtítulo, categoria, rota, keywords).
  String get searchBlob => [
        title,
        subtitle ?? '',
        category.title,
        route,
        ...keywords,
      ].join(' ').toLowerCase();
}
