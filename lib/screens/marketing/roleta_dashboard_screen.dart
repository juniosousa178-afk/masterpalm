import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import '../../services/loja_id_service.dart';
import '../../services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import '../../services/marketing_dashboard/marketing_dashboard_repository.dart';
import '../../services/marketing_dashboard/marketing_period_filter.dart';
import '../../services/store_resolver_facade.dart';
import '../roleta_sorte_config_screen.dart';
import 'roleta_historico_screen.dart';

class RoletaDashboardScreen extends StatefulWidget {
  const RoletaDashboardScreen({super.key, this.lojaId});

  final String? lojaId;

  @override
  State<RoletaDashboardScreen> createState() => _RoletaDashboardScreenState();
}

class _RoletaDashboardScreenState extends State<RoletaDashboardScreen> {
  final _repo = MarketingDashboardRepository();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  String? _lojaId;
  bool _loading = true;
  String? _erro;
  MarketingPeriodFilter _periodo = MarketingPeriodFilter.mes;
  RoletaDashboardKpis? _kpis;

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
      _lojaId = id;
      if (id.isEmpty) {
        setState(() {
          _erro = 'Loja não resolvida';
          _loading = false;
        });
        return;
      }
      final k = await _repo.carregarDashboardRoleta(
        lojaId: id,
        periodo: _periodo,
      );
      if (!mounted) return;
      setState(() {
        _kpis = k;
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
        backgroundColor: MpColors.roleta,
        foregroundColor: Colors.white,
        title: const Text('Dashboard da Roleta'),
        actions: [
          IconButton(
            tooltip: 'Configuração',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              final id = _lojaId;
              if (id == null || id.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoletaSorteConfigScreen(lojaId: id),
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
    final k = _kpis!;
    return RefreshIndicator(
      onRefresh: _boot,
      color: MpColors.roleta,
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
          const SizedBox(height: MpSpacing.sm),
          MpBadge(
            label: k.configAtiva ? 'Roleta ativa' : 'Roleta inativa',
            tone: k.configAtiva ? MpBadgeTone.success : MpBadgeTone.neutral,
          ),
          const SizedBox(height: MpSpacing.md),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
            crossAxisSpacing: MpSpacing.sm,
            mainAxisSpacing: MpSpacing.sm,
            childAspectRatio: 1.4,
            children: [
              MpStatCard(
                label: 'Giros',
                value: '${k.giros}',
                icon: Icons.casino,
                accent: MpColors.roleta,
              ),
              MpStatCard(
                label: 'Prêmios',
                value: '${k.premios}',
                icon: Icons.card_giftcard,
                accent: MpColors.marketing,
              ),
              MpStatCard(
                label: 'Taxa conversão',
                value: '${k.taxaConversaoPercent.toStringAsFixed(0)}%',
                icon: Icons.percent,
                accent: MpColors.success,
                subtitle: 'prêmios / giros',
              ),
              MpStatCard(
                label: 'Pendentes',
                value: '${k.premiosPendentes}',
                icon: Icons.hourglass_empty,
                accent: MpColors.warning,
              ),
              MpStatCard(
                label: 'Valor distribuído',
                value: _money.format(k.valorDistribuido),
                icon: Icons.payments_outlined,
                accent: MpColors.financeiro,
              ),
            ],
          ),
          const SizedBox(height: MpSpacing.lg),
          MpPrimaryButton(
            label: 'Ver histórico completo',
            icon: Icons.history,
            expanded: true,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoletaHistoricoScreen(lojaId: _lojaId),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
