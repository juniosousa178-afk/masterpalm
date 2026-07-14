// M3.8 S2-R5 — tela exclusiva de um módulo/categoria (portal).

import 'package:flutter/material.dart';

import '../core/app_module_definition.dart';
import '../core/home_module_registry.dart';
import '../design_system/mp_tokens.dart';
import '../widgets/home_module_accordion.dart'
    show HomeModuleShortcutCard, HomeModuleTap;

/// Lista os atalhos de uma [HomeModuleCategory] em tela própria.
class HomePortalCategoryScreen extends StatelessWidget {
  const HomePortalCategoryScreen({
    super.key,
    required this.category,
    required this.access,
    required this.onOpenModule,
  });

  final HomeModuleCategory category;
  final HomeModuleAccessContext access;
  final HomeModuleTap onOpenModule;

  @override
  Widget build(BuildContext context) {
    final modules = HomeModuleRegistry.visibleForHome(access)
        .where((m) => m.category == category)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final accent = category.accent;

    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        backgroundColor: MpColors.surface,
        foregroundColor: MpColors.ink,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(MpRadius.sm),
              ),
              child: Icon(category.icon, color: accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    category.portalDescription,
                    style: MpType.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: modules.isEmpty
          ? const Center(child: Text('Nenhuma funcionalidade disponível'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: modules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = modules[i];
                final locked = HomeModuleRegistry.isPlanLocked(m, access);
                return HomeModuleShortcutCard(
                  module: m,
                  planLocked: locked,
                  onTap: () => onOpenModule(m, planLocked: locked),
                );
              },
            ),
    );
  }
}
