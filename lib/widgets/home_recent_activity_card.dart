// M3.8 S2-R4 — card discreto de atividades recentes.

import 'package:flutter/material.dart';

import '../design_system/mp_tokens.dart';
import '../services/home_recent_activity_service.dart';

class HomeRecentActivityCard extends StatelessWidget {
  const HomeRecentActivityCard({super.key, required this.lojaId});

  final String lojaId;

  @override
  Widget build(BuildContext context) {
    if (lojaId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<HomeRecentActivityItem>>(
      future: HomeRecentActivityService.load(lojaId),
      builder: (context, snap) {
        final items = snap.data ?? const <HomeRecentActivityItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(MpSpacing.lg),
          decoration: BoxDecoration(
            color: MpColors.surface,
            borderRadius: BorderRadius.circular(MpRadius.lg),
            border: Border.all(color: MpColors.border),
            boxShadow: [
              BoxShadow(
                color: MpColors.ink.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Últimas atividades', style: MpType.section),
              const SizedBox(height: MpSpacing.sm),
              for (final a in items) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        a.icon == 'venda'
                            ? Icons.check_circle_outline
                            : Icons.person_outline,
                        size: 16,
                        color: MpColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(a.label, style: MpType.caption.copyWith(
                          color: MpColors.ink,
                          fontWeight: FontWeight.w600,
                        )),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
