// M3.8 S2-R5 — grid de cards-portal por categoria (substitui accordion).

import 'package:flutter/material.dart';

import '../core/app_module_definition.dart';
import '../core/home_module_registry.dart';
import '../design_system/mp_tokens.dart';
import '../utils/responsive.dart';

/// Grid responsivo: cada card abre a tela do módulo (portal).
class HomePortalGrid extends StatelessWidget {
  const HomePortalGrid({
    super.key,
    required this.access,
    required this.onOpenCategory,
  });

  final HomeModuleAccessContext access;
  final void Function(HomeModuleCategory category) onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final cats = HomeModuleRegistry.categoriesOrdered.where((cat) {
      return HomeModuleRegistry.visibleForHome(access)
          .any((m) => m.category == cat);
    }).toList();

    final wide = MediaQuery.sizeOf(context).width >= 720;
    final cols = wide ? 3 : (isMobile(context) ? 1 : 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final w = constraints.maxWidth;
        final tileW = cols == 1
            ? w
            : (w - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final cat in cats)
              SizedBox(
                width: tileW,
                child: _PortalCategoryCard(
                  category: cat,
                  count: HomeModuleRegistry.visibleForHome(access)
                      .where((m) => m.category == cat)
                      .length,
                  onTap: () => onOpenCategory(cat),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PortalCategoryCard extends StatefulWidget {
  const _PortalCategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final HomeModuleCategory category;
  final int count;
  final VoidCallback onTap;

  @override
  State<_PortalCategoryCard> createState() => _PortalCategoryCardState();
}

class _PortalCategoryCardState extends State<_PortalCategoryCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final accent = cat.accent;
    final lift = _pressed ? 0.0 : (_hovered ? 4.0 : 2.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(MpRadius.lg),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MpColors.surface,
                borderRadius: BorderRadius.circular(MpRadius.lg),
                border: Border.all(
                  color: _hovered
                      ? accent.withOpacity(0.45)
                      : MpColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: MpColors.ink.withOpacity(_hovered ? 0.08 : 0.045),
                    blurRadius: _hovered ? 16 : 10,
                    offset: Offset(0, lift),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(MpRadius.md),
                    ),
                    child: Icon(cat.icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.title,
                          style: MpType.body.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cat.portalDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MpType.caption,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.count == 1
                              ? '1 funcionalidade'
                              : '${widget.count} funcionalidades',
                          style: MpType.caption.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: accent.withOpacity(0.85),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
