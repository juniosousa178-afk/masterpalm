// M3.8 Sprint 2 — grid da Home com seções (Operação, Vendas, Marketing…).

import 'package:flutter/material.dart';

import '../design_system/mp_components.dart';
import '../design_system/mp_tokens.dart';
import '../utils/responsive.dart';

class HomeModuleSection {
  const HomeModuleSection({
    required this.title,
    required this.cards,
  });

  final String title;
  final List<Widget> cards;
}

class HomeModulesSectionedGrid extends StatelessWidget {
  const HomeModulesSectionedGrid({super.key, required this.sections});

  final List<HomeModuleSection> sections;

  @override
  Widget build(BuildContext context) {
    final cols = responsiveGridCount(context, mobile: 2, tablet: 3, desktop: 4);
    final desktopWeb = MediaQuery.sizeOf(context).width >= 900;
    final visible = sections.where((s) => s.cards.isNotEmpty).toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in visible) ...[
          MpSectionHeader(title: section.title),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: desktopWeb ? 1.4 : 1.35,
            children: section.cards,
          ),
          const SizedBox(height: MpSpacing.sm),
        ],
      ],
    );
  }
}
