// M3.8 S2-R5 — atalhos permanentes da Home (Vendas / Estoque / Carrinhos).

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

  static const _ids = ['vendas', 'estoque', 'carrinhos_abandonados'];

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    for (final id in _ids) {
      final m = HomeModuleRegistry.byId(id);
      if (m == null) continue;
      if (!HomeModuleRegistry.isAllowed(m, access)) continue;
      final locked = HomeModuleRegistry.isPlanLocked(m, access);
      final isVendas = id == 'vendas';
      actions.add(
        Expanded(
          flex: isVendas ? 3 : 2,
          child: _QuickActionChip(
            module: m,
            emphasized: isVendas,
            locked: locked,
            onTap: () => onModuleTap(m, planLocked: locked),
          ),
        ),
      );
      if (id != _ids.last) {
        actions.add(const SizedBox(width: 8));
      }
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: MpSpacing.md),
      child: Row(children: actions),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.module,
    required this.onTap,
    required this.emphasized,
    required this.locked,
  });

  final AppModuleDefinition module;
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
          height: emphasized ? 52 : 48,
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  module.icon,
                  size: emphasized ? 22 : 18,
                  color: emphasized ? Colors.white : accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    module.id == 'carrinhos_abandonados'
                        ? 'Carrinhos'
                        : module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: emphasized ? Colors.white : MpColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: emphasized ? 14 : 12,
                    ),
                  ),
                ),
                if (locked) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: emphasized ? Colors.white70 : MpColors.warning,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
