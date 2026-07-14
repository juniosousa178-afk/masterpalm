import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import '../../services/loja_id_service.dart';
import '../../services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import '../../services/marketing_dashboard/marketing_dashboard_repository.dart';
import '../../services/marketing_dashboard/marketing_period_filter.dart';
import '../../services/store_resolver_facade.dart';

/// Gráficos modernos somente leitura — não altera regras de negócio.
class MarketingEstatisticasScreen extends StatefulWidget {
  const MarketingEstatisticasScreen({super.key, this.lojaId});

  final String? lojaId;

  @override
  State<MarketingEstatisticasScreen> createState() =>
      _MarketingEstatisticasScreenState();
}

class _MarketingEstatisticasScreenState
    extends State<MarketingEstatisticasScreen> {
  final _repo = MarketingDashboardRepository();

  bool _loading = true;
  String? _erro;
  MarketingPeriodFilter _periodo = MarketingPeriodFilter.mes;
  List<SeriePonto> _serie = [];
  CampanhaDashboardSnapshot? _campSnap;
  RoletaDashboardKpis? _roleta;

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
      if (id.isEmpty) id = (await LojaIdService.get()) ?? '';
      if (id.isEmpty) {
        id = (await StoreResolverFacade.resolveForAdminApp()) ?? '';
      }
      if (id.isEmpty) {
        setState(() {
          _erro = 'Loja não resolvida';
          _loading = false;
        });
        return;
      }
      final serie = await _repo.carregarParticipantesPorDia(
        lojaId: id,
        periodo: _periodo,
      );
      final camp = await _repo.carregarDashboardCampanhas(
        lojaId: id,
        periodo: _periodo,
      );
      final roleta = await _repo.carregarDashboardRoleta(
        lojaId: id,
        periodo: _periodo,
      );
      if (!mounted) return;
      setState(() {
        _serie = serie;
        _campSnap = camp;
        _roleta = roleta;
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
        backgroundColor: MpColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Estatísticas de Marketing'),
        actions: [
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
              : ListView(
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
                    MpSectionHeader(
                      title: 'Participantes por dia',
                      subtitle: 'Somente leitura dos dados existentes',
                    ),
                    MpCard(
                      child: SizedBox(
                        height: 220,
                        child: _serie.isEmpty
                            ? const Center(
                                child: Text('Sem pontos no período',
                                    style: MpType.caption),
                              )
                            : LineChart(
                                LineChartData(
                                  gridData: const FlGridData(show: true),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false),
                                    ),
                                    leftTitles: const AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 28,
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        interval: (_serie.length / 4)
                                            .clamp(1, 10)
                                            .toDouble(),
                                        getTitlesWidget: (v, _) {
                                          final i = v.toInt();
                                          if (i < 0 || i >= _serie.length) {
                                            return const SizedBox.shrink();
                                          }
                                          final lab = _serie[i].label;
                                          final short = lab.length >= 5
                                              ? lab.substring(5)
                                              : lab;
                                          return Text(short,
                                              style: const TextStyle(
                                                  fontSize: 10));
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: [
                                        for (var i = 0;
                                            i < _serie.length;
                                            i++)
                                          FlSpot(
                                            i.toDouble(),
                                            _serie[i].valor,
                                          ),
                                      ],
                                      isCurved: true,
                                      color: MpColors.primary,
                                      barWidth: 3,
                                      dotData:
                                          const FlDotData(show: false),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    MpSectionHeader(title: 'Vendas por campanha (receita)'),
                    MpCard(
                      child: SizedBox(
                        height: 220,
                        child: (_campSnap?.topCampanhas.isEmpty ?? true)
                            ? const Center(
                                child: Text('Sem campanhas',
                                    style: MpType.caption),
                              )
                            : BarChart(
                                BarChartData(
                                  gridData: const FlGridData(show: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false),
                                    ),
                                    leftTitles: const AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 36,
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (v, _) {
                                          final i = v.toInt();
                                          final list =
                                              _campSnap!.topCampanhas;
                                          if (i < 0 || i >= list.length) {
                                            return const SizedBox.shrink();
                                          }
                                          final n = list[i].nome;
                                          final short = n.length > 8
                                              ? '${n.substring(0, 8)}…'
                                              : n;
                                          return Text(short,
                                              style: const TextStyle(
                                                  fontSize: 10));
                                        },
                                      ),
                                    ),
                                  ),
                                  barGroups: [
                                    for (var i = 0;
                                        i <
                                            _campSnap!
                                                .topCampanhas.length;
                                        i++)
                                      BarChartGroupData(
                                        x: i,
                                        barRods: [
                                          BarChartRodData(
                                            toY: _campSnap!
                                                .topCampanhas[i].receita,
                                            color: MpColors.marketing,
                                            width: 16,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    MpSectionHeader(title: 'Roleta (período)'),
                    if (_roleta != null)
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: MpSpacing.sm,
                        mainAxisSpacing: MpSpacing.sm,
                        childAspectRatio: 1.5,
                        children: [
                          MpStatCard(
                            label: 'Uso da roleta',
                            value: '${_roleta!.giros} giros',
                            icon: Icons.casino,
                            accent: MpColors.roleta,
                          ),
                          MpStatCard(
                            label: 'Conversão roleta',
                            value:
                                '${_roleta!.taxaConversaoPercent.toStringAsFixed(0)}%',
                            icon: Icons.insights,
                            accent: MpColors.success,
                          ),
                          MpStatCard(
                            label: 'Ticket médio campanha',
                            value: _campSnap == null
                                ? '—'
                                : _campSnap!.kpis.ticketMedio
                                    .toStringAsFixed(2),
                            icon: Icons.trending_up,
                            accent: MpColors.info,
                          ),
                          MpStatCard(
                            label: 'Participantes',
                            value:
                                '${_campSnap?.kpis.participantes ?? 0}',
                            icon: Icons.people,
                            accent: MpColors.primary,
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}
