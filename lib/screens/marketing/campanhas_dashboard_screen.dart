import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import '../../services/loja_id_service.dart';
import '../../services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import '../../services/marketing_dashboard/marketing_dashboard_repository.dart';
import '../../services/marketing_dashboard/marketing_period_filter.dart';
import '../../services/store_resolver_facade.dart';
import 'campanha_detalhe_dashboard_screen.dart';
import '../campanhas_sorteio_screen.dart';

class CampanhasDashboardScreen extends StatefulWidget {
  const CampanhasDashboardScreen({super.key, this.lojaId});

  final String? lojaId;

  @override
  State<CampanhasDashboardScreen> createState() =>
      _CampanhasDashboardScreenState();
}

class _CampanhasDashboardScreenState extends State<CampanhasDashboardScreen> {
  final _repo = MarketingDashboardRepository();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  String? _lojaId;
  bool _loading = true;
  String? _erro;
  MarketingPeriodFilter _periodo = MarketingPeriodFilter.mes;
  CampanhaDashboardSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      var id = widget.lojaId?.trim() ?? '';
      if (id.isEmpty) {
        id = (await LojaIdService.get()) ?? '';
      }
      if (id.isEmpty) {
        id = (await StoreResolverFacade.resolveForAdminApp()) ?? '';
      }
      _lojaId = id;
      if (id.isEmpty) {
        setState(() {
          _erro = 'Loja não resolvida';
          _loading = false;
        });
        return;
      }
      final snap = await _repo.carregarDashboardCampanhas(
        lojaId: id,
        periodo: _periodo,
      );
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        backgroundColor: MpColors.marketing,
        foregroundColor: Colors.white,
        title: const Text('Dashboard de Campanhas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Gerenciar campanhas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CampanhasSorteioScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _boot,
          ),
        ],
      ),
      body: _loading
          ? const MpLoadingState()
          : _erro != null
              ? MpErrorState(message: _erro!, onRetry: _boot)
              : _body(),
    );
  }

  Widget _body() {
    final k = _snap!.kpis;
    return RefreshIndicator(
      onRefresh: _boot,
      color: MpColors.marketing,
      child: ListView(
        padding: const EdgeInsets.all(MpSpacing.lg),
        children: [
          MpFilterChips<MarketingPeriodFilter>(
            options: MarketingPeriodFilter.values,
            value: _periodo,
            labelOf: (e) => e.label,
            onChanged: (v) {
              setState(() => _periodo = v);
              _boot();
            },
          ),
          const SizedBox(height: MpSpacing.md),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth > 900
                  ? 4
                  : c.maxWidth > 600
                      ? 3
                      : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: MpSpacing.sm,
                mainAxisSpacing: MpSpacing.sm,
                childAspectRatio: 1.45,
                children: [
                  MpStatCard(
                    label: 'Ativas',
                    value: '${k.ativas}',
                    icon: Icons.play_circle_outline,
                    accent: MpColors.success,
                  ),
                  MpStatCard(
                    label: 'Encerradas',
                    value: '${k.encerradas}',
                    icon: Icons.stop_circle_outlined,
                    accent: MpColors.inkMuted,
                  ),
                  MpStatCard(
                    label: 'Participantes',
                    value: '${k.participantes}',
                    icon: Icons.people_outline,
                    accent: MpColors.primary,
                  ),
                  MpStatCard(
                    label: 'Números gerados',
                    value: '${k.numerosGerados}',
                    icon: Icons.confirmation_number_outlined,
                    accent: MpColors.warning,
                  ),
                  MpStatCard(
                    label: 'Receita gerada',
                    value: _money.format(k.receitaGerada),
                    icon: Icons.payments_outlined,
                    accent: MpColors.financeiro,
                  ),
                  MpStatCard(
                    label: 'Ticket médio',
                    value: _money.format(k.ticketMedio),
                    icon: Icons.trending_up,
                    accent: MpColors.info,
                  ),
                  MpStatCard(
                    label: 'Clientes',
                    value: '${k.clientesUnicos}',
                    icon: Icons.person_outline,
                    accent: MpColors.roleta,
                  ),
                  MpStatCard(
                    label: 'Conversão*',
                    value: '${k.conversaoPercent.toStringAsFixed(0)}%',
                    icon: Icons.insights,
                    accent: MpColors.marketing,
                    subtitle: 'participantes / campanhas',
                  ),
                ],
              );
            },
          ),
          MpSectionHeader(
            title: 'Top campanhas',
            subtitle: 'Por receita no filtro selecionado',
          ),
          if (_snap!.topCampanhas.isEmpty)
            const MpEmptyState(
              title: 'Sem dados no período',
              subtitle: 'Ajuste o filtro ou aguarde participações.',
              icon: Icons.campaign_outlined,
            )
          else
            ..._snap!.topCampanhas.map(_campanhaTile),
          MpSectionHeader(title: 'Todas'),
          ..._snap!.campanhas.map(_campanhaTile),
        ],
      ),
    );
  }

  Widget _campanhaTile(CampanhaResumoItem e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MpSpacing.sm),
      child: MpCard(
        onTap: () {
          final loja = _lojaId;
          if (loja == null || loja.isEmpty) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CampanhaDetalheDashboardScreen(
                lojaId: loja,
                campanhaId: e.id,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.nome, style: MpType.body),
                  const SizedBox(height: 4),
                  Text(
                    '${e.participantes} part. · ${e.numeros} nº · ${_money.format(e.receita)}',
                    style: MpType.caption,
                  ),
                ],
              ),
            ),
            MpBadge(
              label: e.ativa ? 'Ativa' : 'Encerrada',
              tone: e.ativa ? MpBadgeTone.success : MpBadgeTone.neutral,
            ),
            const Icon(Icons.chevron_right, color: MpColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
