// M3.8 Sprint 2 — hub marketing (entrada dos dashboards).

import 'package:flutter/material.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import 'campanhas_dashboard_screen.dart';
import 'marketing_estatisticas_screen.dart';
import 'roleta_dashboard_screen.dart';
import 'roleta_historico_screen.dart';

class MarketingHubScreen extends StatelessWidget {
  const MarketingHubScreen({super.key, this.lojaId});

  final String? lojaId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        backgroundColor: MpColors.marketing,
        foregroundColor: Colors.white,
        title: const Text('Marketing'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MpSpacing.lg),
        children: [
          MpSectionHeader(
            title: 'Painéis',
            subtitle: 'Leitura de campanhas e roleta — sem alterar regras',
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
            crossAxisSpacing: MpSpacing.md,
            mainAxisSpacing: MpSpacing.md,
            childAspectRatio: 1.15,
            children: [
              MpModuleTile(
                icon: Icons.campaign_outlined,
                title: 'Campanhas',
                subtitle: 'Dashboard',
                color: MpColors.marketing,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CampanhasDashboardScreen(lojaId: lojaId),
                  ),
                ),
              ),
              MpModuleTile(
                icon: Icons.casino_outlined,
                title: 'Roleta',
                subtitle: 'Dashboard',
                color: MpColors.roleta,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoletaDashboardScreen(lojaId: lojaId),
                  ),
                ),
              ),
              MpModuleTile(
                icon: Icons.history,
                title: 'Histórico Roleta',
                subtitle: 'Giros e prêmios',
                color: MpColors.info,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoletaHistoricoScreen(lojaId: lojaId),
                  ),
                ),
              ),
              MpModuleTile(
                icon: Icons.bar_chart_rounded,
                title: 'Estatísticas',
                subtitle: 'Gráficos',
                color: MpColors.primary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MarketingEstatisticasScreen(lojaId: lojaId),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
