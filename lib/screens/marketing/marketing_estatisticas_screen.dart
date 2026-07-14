import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import '../../services/loja_id_service.dart';
import '../../services/marketing_dashboard/firestore_client_error.dart';
import '../../services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import '../../services/marketing_dashboard/marketing_dashboard_repository.dart';
import '../../services/marketing_dashboard/marketing_period_filter.dart';
import '../../services/store_resolver_facade.dart';

enum _SectionPhase { loading, data, empty, permissionDenied, error }

/// Gráficos modernos somente leitura — seções independentes (R2).
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

  MarketingPeriodFilter _periodo = MarketingPeriodFilter.mes;

  _SectionPhase _campPhase = _SectionPhase.loading;
  _SectionPhase _seriePhase = _SectionPhase.loading;
  _SectionPhase _roletaPhase = _SectionPhase.loading;
  String? _campErro;
  String? _serieErro;
  String? _roletaErro;

  List<SeriePonto> _serie = [];
  CampanhaDashboardSnapshot? _campSnap;
  RoletaDashboardLoadResult? _roletaLoad;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _campPhase = _SectionPhase.loading;
      _seriePhase = _SectionPhase.loading;
      _roletaPhase = _SectionPhase.loading;
      _campErro = null;
      _serieErro = null;
      _roletaErro = null;
    });

    var id = widget.lojaId?.trim() ?? '';
    if (id.isEmpty) id = (await LojaIdService.get()) ?? '';
    if (id.isEmpty) {
      id = (await StoreResolverFacade.resolveForAdminApp()) ?? '';
    }
    if (id.isEmpty) {
      setState(() {
        _campPhase = _SectionPhase.error;
        _seriePhase = _SectionPhase.error;
        _roletaPhase = _SectionPhase.error;
        _campErro = 'Loja não resolvida';
        _serieErro = 'Loja não resolvida';
        _roletaErro = 'Loja não resolvida';
      });
      return;
    }

    await Future.wait([
      _loadCampanhas(id),
      _loadSerie(id),
      _loadRoleta(id),
    ]);
  }

  Future<void> _loadCampanhas(String id) async {
    try {
      final camp = await _repo.carregarDashboardCampanhas(
        lojaId: id,
        periodo: _periodo,
      );
      if (!mounted) return;
      setState(() {
        _campSnap = camp;
        _campPhase = camp.campanhas.isEmpty
            ? _SectionPhase.empty
            : _SectionPhase.data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isFirestorePermissionDenied(e)) {
          _campPhase = _SectionPhase.permissionDenied;
        } else {
          _campPhase = _SectionPhase.error;
          _campErro = e.toString();
        }
      });
    }
  }

  Future<void> _loadSerie(String id) async {
    try {
      final serie = await _repo.carregarParticipantesPorDia(
        lojaId: id,
        periodo: _periodo,
      );
      if (!mounted) return;
      setState(() {
        _serie = serie;
        _seriePhase =
            serie.isEmpty ? _SectionPhase.empty : _SectionPhase.data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isFirestorePermissionDenied(e)) {
          _seriePhase = _SectionPhase.permissionDenied;
        } else {
          _seriePhase = _SectionPhase.error;
          _serieErro = e.toString();
        }
      });
    }
  }

  Future<void> _loadRoleta(String id) async {
    try {
      final r = await _repo.carregarDashboardRoleta(
        lojaId: id,
        periodo: _periodo,
      );
      if (!mounted) return;
      setState(() {
        _roletaLoad = r;
        if (!r.historicoDisponivel &&
            r.indisponibilidadeCodigo == 'permission-denied') {
          _roletaPhase = _SectionPhase.permissionDenied;
        } else if (!r.historicoDisponivel) {
          _roletaPhase = _SectionPhase.error;
          _roletaErro = r.indisponibilidadeCodigo ?? 'erro';
        } else {
          _roletaPhase = _SectionPhase.data;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isFirestorePermissionDenied(e)) {
          _roletaPhase = _SectionPhase.permissionDenied;
        } else {
          _roletaPhase = _SectionPhase.error;
          _roletaErro = e.toString();
        }
      });
    }
  }

  bool get _anyLoading =>
      _campPhase == _SectionPhase.loading ||
      _seriePhase == _SectionPhase.loading ||
      _roletaPhase == _SectionPhase.loading;

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
            onPressed: _anyLoading ? null : _boot,
          ),
        ],
      ),
      body: ListView(
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
          _kpiHeader(),
          MpSectionHeader(
            title: 'Participantes por dia',
            subtitle: 'Somente leitura dos dados existentes',
          ),
          _sectionBox(
            phase: _seriePhase,
            error: _serieErro,
            permissionMsg: 'Participantes indisponíveis para este perfil.',
            emptyMsg: 'Sem pontos no período',
            child: SizedBox(height: 220, child: _serieChart()),
          ),
          MpSectionHeader(title: 'Vendas por campanha (receita)'),
          _sectionBox(
            phase: _campPhase,
            error: _campErro,
            permissionMsg: 'Campanhas indisponíveis para este perfil.',
            emptyMsg: 'Sem campanhas',
            child: SizedBox(height: 220, child: _campChart()),
          ),
          MpSectionHeader(title: 'Roleta (período)'),
          if (_roletaPhase == _SectionPhase.loading)
            const MpCard(
              child: SizedBox(height: 120, child: MpLoadingState()),
            )
          else if (_roletaPhase == _SectionPhase.error)
            MpCard(
              child: Text(_roletaErro ?? 'Erro', style: MpType.caption),
            )
          else ...[
            if (_roletaPhase == _SectionPhase.permissionDenied)
              const Padding(
                padding: EdgeInsets.only(bottom: MpSpacing.sm),
                child: MpInfoBanner(
                  message: 'Indisponível para este perfil.',
                ),
              ),
            MpCard(child: _roletaCards()),
          ],
          if (_campPhase == _SectionPhase.data && _campSnap != null) ...[
            const SizedBox(height: MpSpacing.md),
            MpStatCard(
              label: 'Ticket médio campanha',
              value: _campSnap!.kpis.ticketMedio.toStringAsFixed(2),
              icon: Icons.trending_up,
              accent: MpColors.info,
            ),
            const SizedBox(height: MpSpacing.sm),
            MpStatCard(
              label: 'Participantes',
              value: '${_campSnap!.kpis.participantes}',
              icon: Icons.people,
              accent: MpColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiHeader() {
    final camp = _campSnap?.kpis;
    final roleta = _roletaLoad?.kpis;
    String money(double? v) {
      if (v == null) return '—';
      return 'R\$ ${v.toStringAsFixed(0)}';
    }

    final tiles = <({String label, String value, IconData icon, Color color})>[
      (
        label: 'Campanhas ativas',
        value: camp == null ? '—' : '${camp.ativas}',
        icon: Icons.campaign_outlined,
        color: MpColors.marketing,
      ),
      (
        label: 'Participantes',
        value: camp == null ? '—' : '${camp.participantes}',
        icon: Icons.people_outline,
        color: MpColors.primary,
      ),
      (
        label: 'Conversão',
        value: camp == null
            ? '—'
            : '${camp.conversaoPercent.toStringAsFixed(0)}%',
        icon: Icons.percent,
        color: MpColors.info,
      ),
      (
        label: 'Receita',
        value: camp == null ? '—' : money(camp.receitaGerada),
        icon: Icons.attach_money,
        color: MpColors.success,
      ),
      (
        label: 'Roletas',
        value: formatMetricDisplay(
          roleta?.giros,
          disponivel: roleta?.logsDisponiveis ?? false,
        ),
        icon: Icons.casino_outlined,
        color: MpColors.roleta,
      ),
      (
        label: 'Prêmios',
        value: formatMetricDisplay(
          roleta?.premios,
          disponivel: roleta?.logsDisponiveis ?? false,
        ),
        icon: Icons.card_giftcard_outlined,
        color: MpColors.warning,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: MpSpacing.md),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in tiles)
            SizedBox(
              width: MediaQuery.sizeOf(context).width > 700
                  ? (MediaQuery.sizeOf(context).width - 80) / 3
                  : (MediaQuery.sizeOf(context).width - 56) / 2,
              child: MpStatCard(
                label: t.label,
                value: t.value,
                icon: t.icon,
                accent: t.color,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionBox({
    required _SectionPhase phase,
    required String? error,
    required String permissionMsg,
    required String emptyMsg,
    required Widget child,
  }) {
    switch (phase) {
      case _SectionPhase.loading:
        return const MpCard(
          child: SizedBox(height: 120, child: MpLoadingState()),
        );
      case _SectionPhase.permissionDenied:
        return MpInfoBanner(message: permissionMsg);
      case _SectionPhase.error:
        return MpCard(
          child: Text(error ?? 'Erro', style: MpType.caption),
        );
      case _SectionPhase.empty:
        return MpCard(
          child: SizedBox(
            height: 80,
            child: Center(child: Text(emptyMsg, style: MpType.caption)),
          ),
        );
      case _SectionPhase.data:
        return MpCard(child: child);
    }
  }

  Widget _serieChart() {
    if (_serie.isEmpty) {
      return const Center(
        child: Text('Sem pontos no período', style: MpType.caption),
      );
    }
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (_serie.length / 4).clamp(1, 10).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= _serie.length) {
                  return const SizedBox.shrink();
                }
                final lab = _serie[i].label;
                final short = lab.length >= 5 ? lab.substring(5) : lab;
                return Text(short, style: const TextStyle(fontSize: 10));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < _serie.length; i++)
                FlSpot(i.toDouble(), _serie[i].valor),
            ],
            isCurved: true,
            color: MpColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _campChart() {
    final list = _campSnap?.topCampanhas ?? const [];
    if (list.isEmpty) {
      return const Center(
        child: Text('Sem campanhas', style: MpType.caption),
      );
    }
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= list.length) {
                  return const SizedBox.shrink();
                }
                final n = list[i].nome;
                final short = n.length > 8 ? '${n.substring(0, 8)}…' : n;
                return Text(short, style: const TextStyle(fontSize: 10));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < list.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: list[i].receita,
                  color: MpColors.marketing,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _roletaCards() {
    final r = _roletaLoad;
    if (r == null) {
      return const Text('—', style: MpType.caption);
    }
    final k = r.kpis;
    final logsOk = r.historicoDisponivel;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: MpSpacing.sm,
      mainAxisSpacing: MpSpacing.sm,
      childAspectRatio: 1.5,
      children: [
        MpStatCard(
          label: 'Uso da roleta',
          value: logsOk
              ? '${k.giros ?? 0} giros'
              : 'Indisponível',
          icon: Icons.casino,
          accent: MpColors.roleta,
        ),
        MpStatCard(
          label: 'Conversão roleta',
          value: logsOk && k.taxaConversaoPercent != null
              ? '${k.taxaConversaoPercent!.toStringAsFixed(0)}%'
              : '—',
          icon: Icons.insights,
          accent: MpColors.success,
        ),
        MpStatCard(
          label: 'Config ativa',
          value: k.configAtiva ? 'Sim' : 'Não',
          icon: Icons.toggle_on,
          accent: MpColors.info,
        ),
        MpStatCard(
          label: 'Saldo prêmios (config)',
          value: '${k.configPremiosRestantes ?? 0}',
          icon: Icons.inventory_2_outlined,
          accent: MpColors.warning,
        ),
      ],
    );
  }
}
