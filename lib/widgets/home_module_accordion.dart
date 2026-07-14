// M3.8 S2-R4 — accordion / favoritos / badges da Home.

import 'package:flutter/material.dart';

import '../core/app_module_definition.dart';
import '../core/home_module_registry.dart';
import '../design_system/mp_tokens.dart';
import '../services/home_category_insight_service.dart';
import '../services/home_ux_prefs_service.dart';
import '../utils/responsive.dart';

typedef HomeModuleTap = void Function(
  AppModuleDefinition module, {
  required bool planLocked,
});

/// Card compacto de atalho interno.
class HomeModuleShortcutCard extends StatelessWidget {
  const HomeModuleShortcutCard({
    super.key,
    required this.module,
    required this.onTap,
    this.planLocked = false,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  final AppModuleDefinition module;
  final VoidCallback onTap;
  final bool planLocked;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final accent = module.effectiveAccent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MpRadius.md),
        splashColor: accent.withOpacity(0.12),
        highlightColor: accent.withOpacity(0.06),
        child: Ink(
          decoration: BoxDecoration(
            color: MpColors.surface,
            borderRadius: BorderRadius.circular(MpRadius.md),
            border: Border.all(
              color: planLocked
                  ? MpColors.warning.withOpacity(0.45)
                  : MpColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: MpColors.ink.withOpacity(0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(MpRadius.sm),
                  ),
                  child: Icon(module.icon, size: 20, color: accent),
                ),
                const SizedBox(width: MpSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        module.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MpType.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (module.subtitle != null)
                        Text(
                          module.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MpType.caption,
                        ),
                    ],
                  ),
                ),
                if (onToggleFavorite != null)
                  IconButton(
                    tooltip: isFavorite ? 'Remover favorito' : 'Adicionar favorito',
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border,
                      size: 20,
                      color: isFavorite ? MpColors.warning : MpColors.inkMuted,
                    ),
                  ),
                if (planLocked)
                  const Icon(Icons.lock_outline,
                      size: 16, color: MpColors.warning)
                else
                  Icon(Icons.chevron_right,
                      size: 18, color: MpColors.inkMuted.withOpacity(0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeModuleSectionTile extends StatelessWidget {
  const HomeModuleSectionTile({
    super.key,
    required this.category,
    required this.expanded,
    required this.count,
    required this.onToggle,
    this.insights = const [],
  });

  final HomeModuleCategory category;
  final bool expanded;
  final int count;
  final VoidCallback onToggle;
  final List<HomeCategoryInsight> insights;

  @override
  Widget build(BuildContext context) {
    final accent = category.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(MpRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: expanded ? accent.withOpacity(0.07) : MpColors.surface,
            borderRadius: BorderRadius.circular(MpRadius.lg),
            border: Border.all(
              color: expanded ? accent.withOpacity(0.32) : MpColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: MpColors.ink.withOpacity(expanded ? 0.055 : 0.03),
                blurRadius: expanded ? 14 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(MpRadius.md),
                ),
                child: Icon(category.icon, color: accent, size: 22),
              ),
              const SizedBox(width: MpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${category.title} ($count)',
                      style: MpType.body.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (insights.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final i in insights.take(3))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  i.label,
                                  style: MpType.caption.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.expand_more, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accordion + favoritos (persistidos) da Home.
class HomeModuleAccordion extends StatefulWidget {
  const HomeModuleAccordion({
    super.key,
    required this.access,
    required this.onModuleTap,
    this.lojaId = '',
    this.excludeFavoriteIdsFromAccordion = true,
    this.excludeModuleIds = const {},
    this.initialOpenCategoryId,
  });

  final HomeModuleAccessContext access;
  final HomeModuleTap onModuleTap;
  final String lojaId;
  final bool excludeFavoriteIdsFromAccordion;
  /// Módulos já destacados fora do accordion (ex.: CTA Vendas).
  final Set<String> excludeModuleIds;
  final String? initialOpenCategoryId;

  @override
  State<HomeModuleAccordion> createState() => HomeModuleAccordionState();
}

class HomeModuleAccordionState extends State<HomeModuleAccordion> {
  String? _openId;
  List<String> _favoriteIds = [];
  Map<String, List<HomeCategoryInsight>> _insights = {};

  @override
  void initState() {
    super.initState();
    _openId = widget.initialOpenCategoryId;
    _bootPrefs();
  }

  @override
  void didUpdateWidget(covariant HomeModuleAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaId != widget.lojaId ||
        oldWidget.initialOpenCategoryId != widget.initialOpenCategoryId) {
      _openId = widget.initialOpenCategoryId ?? _openId;
      _bootPrefs();
    }
  }

  Future<void> _bootPrefs() async {
    final lojaId = widget.lojaId;
    final favs = await HomeUxPrefsService.getFavorites(lojaId);
    final open = await HomeUxPrefsService.getOpenCategoryId(lojaId);
    Map<String, List<HomeCategoryInsight>> insights = {};
    if (lojaId.isNotEmpty) {
      insights = await HomeCategoryInsightService.load(lojaId);
    }
    if (!mounted) return;
    setState(() {
      _favoriteIds = favs;
      if (open != null) _openId = open;
      _insights = insights;
    });
  }

  Future<void> _toggle(String categoryId) async {
    final next = _openId == categoryId ? null : categoryId;
    setState(() => _openId = next);
    await HomeUxPrefsService.setOpenCategoryId(widget.lojaId, next);
  }

  Future<void> _toggleFavorite(AppModuleDefinition m) async {
    try {
      final next =
          await HomeUxPrefsService.toggleFavorite(widget.lojaId, m.id);
      if (!mounted) return;
      setState(() => _favoriteIds = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Máximo de ${HomeUxPrefsService.maxFavorites} favoritos',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = HomeModuleRegistry.visibleForHome(widget.access)
        .where((m) => !widget.excludeModuleIds.contains(m.id))
        .toList();
    final counts = <HomeModuleCategory, int>{};
    for (final m in visible) {
      counts[m.category] = (counts[m.category] ?? 0) + 1;
    }
    final favSet = _favoriteIds.toSet();
    final favorites = HomeModuleRegistry.byIds(_favoriteIds, access: widget.access)
        .where((m) => !widget.excludeModuleIds.contains(m.id))
        .toList();
    final accordionModules = widget.excludeFavoriteIdsFromAccordion
        ? visible.where((m) => !favSet.contains(m.id)).toList()
        : visible;

    return ListView(
      padding: const EdgeInsets.only(bottom: MpSpacing.xxl),
      children: [
        _FavoritesSection(
          favorites: favorites,
          access: widget.access,
          onModuleTap: widget.onModuleTap,
          onToggleFavorite: _toggleFavorite,
          onAddHint: favorites.isEmpty,
        ),
        const SizedBox(height: MpSpacing.lg),
        Text('Categorias', style: MpType.section),
        const SizedBox(height: MpSpacing.sm),
        for (final cat in HomeModuleRegistry.categoriesOrdered) ...[
          Builder(builder: (context) {
            final mods =
                accordionModules.where((m) => m.category == cat).toList();
            // Se todos estão em favoritos, ainda mostra a categoria com os módulos
            // da categoria (via visible) para não sumir navegação.
            final display = mods.isNotEmpty
                ? mods
                : visible.where((m) => m.category == cat).toList();
            if (display.isEmpty) return const SizedBox.shrink();
            final expanded = _openId == cat.id;
            final count = counts[cat] ?? display.length;
            return Padding(
              padding: const EdgeInsets.only(bottom: MpSpacing.md),
              child: Column(
                children: [
                  HomeModuleSectionTile(
                    category: cat,
                    expanded: expanded,
                    count: count,
                    insights: _insights[cat.id] ?? const [],
                    onToggle: () => _toggle(cat.id),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? FadeTransition(
                            opacity: const AlwaysStoppedAnimation(1),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: MpSpacing.sm,
                                left: 2,
                                right: 2,
                              ),
                              child: _ShortcutGrid(
                                modules: display,
                                access: widget.access,
                                favoriteIds: favSet,
                                onModuleTap: widget.onModuleTap,
                                onToggleFavorite: _toggleFavorite,
                              ),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({
    required this.favorites,
    required this.access,
    required this.onModuleTap,
    required this.onToggleFavorite,
    required this.onAddHint,
  });

  final List<AppModuleDefinition> favorites;
  final HomeModuleAccessContext access;
  final HomeModuleTap onModuleTap;
  final void Function(AppModuleDefinition) onToggleFavorite;
  final bool onAddHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star, size: 16, color: MpColors.warning),
            const SizedBox(width: 6),
            Text('Favoritos', style: MpType.section),
            const Spacer(),
            Text(
              '${favorites.length}/${HomeUxPrefsService.maxFavorites}',
              style: MpType.caption,
            ),
          ],
        ),
        const SizedBox(height: MpSpacing.sm),
        if (onAddHint)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(MpSpacing.lg),
            decoration: BoxDecoration(
              color: MpColors.chipBg,
              borderRadius: BorderRadius.circular(MpRadius.md),
              border: Border.all(color: MpColors.border),
            ),
            child: Text(
              'Toque na estrela de um módulo para adicionar aos favoritos (até ${HomeUxPrefsService.maxFavorites}).',
              style: MpType.caption,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in favorites)
                _FavoriteChip(
                  module: m,
                  planLocked: HomeModuleRegistry.isPlanLocked(m, access),
                  onTap: () => onModuleTap(
                    m,
                    planLocked: HomeModuleRegistry.isPlanLocked(m, access),
                  ),
                  onRemove: () => onToggleFavorite(m),
                ),
            ],
          ),
      ],
    );
  }
}

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({
    required this.module,
    required this.onTap,
    required this.onRemove,
    this.planLocked = false,
  });

  final AppModuleDefinition module;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool planLocked;

  @override
  Widget build(BuildContext context) {
    final accent = module.effectiveAccent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MpRadius.xl),
        child: Ink(
          padding: const EdgeInsets.only(left: 12, right: 4, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(MpRadius.xl),
            border: Border.all(color: accent.withOpacity(0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(module.icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                module.title,
                style: MpType.caption.copyWith(
                  color: MpColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (planLocked) ...[
                const SizedBox(width: 4),
                const Icon(Icons.lock_outline,
                    size: 14, color: MpColors.warning),
              ],
              IconButton(
                tooltip: 'Remover favorito',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 14, color: MpColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({
    required this.modules,
    required this.access,
    required this.favoriteIds,
    required this.onModuleTap,
    required this.onToggleFavorite,
  });

  final List<AppModuleDefinition> modules;
  final HomeModuleAccessContext access;
  final Set<String> favoriteIds;
  final HomeModuleTap onModuleTap;
  final void Function(AppModuleDefinition) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final cols = responsiveGridCount(context, mobile: 1, tablet: 2, desktop: 2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 8.0;
        final itemW = cols == 1 ? width : (width - gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final m in modules)
              SizedBox(
                width: itemW,
                child: HomeModuleShortcutCard(
                  module: m,
                  planLocked: HomeModuleRegistry.isPlanLocked(m, access),
                  isFavorite: favoriteIds.contains(m.id),
                  onToggleFavorite: () => onToggleFavorite(m),
                  onTap: () => onModuleTap(
                    m,
                    planLocked: HomeModuleRegistry.isPlanLocked(m, access),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
