// M3.8 S2-R5/R6 — atalhos permanentes da Home (Vendas / Estoque / Carrinhos / Catálogo).

import 'package:flutter/material.dart';

import '../core/app_module_definition.dart';
import '../core/home_module_registry.dart';
import '../design_system/mp_tokens.dart';
import 'home_module_accordion.dart' show HomeModuleTap;

/// Botões rápidos sempre visíveis no topo operacional da Home.
class HomeQuickActionsRow extends StatelessWidget {
  const HomeQuickActionsRow({
    super.key,
    required this.access,
    required this.onModuleTap,
  });

  final HomeModuleAccessContext access;
  final HomeModuleTap onModuleTap;

  static const ids = [
    'vendas',
    'estoque',
    'carrinhos_abandonados',
    'catalogo_loja',
  ];

  static String shortTitle(AppModuleDefinition m) {
    switch (m.id) {
      case 'carrinhos_abandonados':
        return 'Carrinhos';
      case 'catalogo_loja':
        return 'Catálogo';
      default:
        return m.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = <AppModuleDefinition>[];
    for (final id in ids) {
      final m = HomeModuleRegistry.byId(id);
      if (m == null) continue;
      if (!HomeModuleRegistry.isAllowed(m, access)) continue;
      modules.add(m);
    }
    if (modules.isEmpty) return const SizedBox.shrink();

    Widget chipFor(AppModuleDefinition m) {
      final locked = HomeModuleRegistry.isPlanLocked(m, access);
      final isVendas = m.id == 'vendas';
      final isCatalogo = m.id == 'catalogo_loja';
      return _QuickActionChip(
        module: m,
        label: shortTitle(m),
        emphasized: isVendas || isCatalogo,
        locked: locked,
        onTap: () => onModuleTap(m, planLocked: locked),
      );
    }

    // Mobile: duas linhas (Vendas+Estoque / Carrinhos+Catálogo).
    final narrow = MediaQuery.sizeOf(context).width < 560;
    if (narrow && modules.length >= 3) {
      final row1 = modules.take(2).toList();
      final row2 = modules.skip(2).toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: MpSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < row1.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: chipFor(row1[i])),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < row2.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: chipFor(row2[i])),
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: MpSpacing.sm),
      child: Row(
        children: [
          for (var i = 0; i < modules.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              flex: modules[i].id == 'vendas' ? 3 : 2,
              child: chipFor(modules[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.module,
    required this.label,
    required this.onTap,
    required this.emphasized,
    required this.locked,
  });

  final AppModuleDefinition module;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final accent = module.effectiveAccent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MpRadius.md),
        child: Ink(
          height: emphasized ? 48 : 44,
          decoration: BoxDecoration(
            color: emphasized ? accent : MpColors.surface,
            borderRadius: BorderRadius.circular(MpRadius.md),
            border: Border.all(
              color: emphasized ? accent : MpColors.border,
            ),
            boxShadow: emphasized
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: MpColors.ink.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  locked ? Icons.lock_outline : module.icon,
                  size: emphasized ? 20 : 17,
                  color: emphasized ? Colors.white : accent,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: emphasized ? Colors.white : MpColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: emphasized ? 13 : 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
