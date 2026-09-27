import 'package:flutter/material.dart';

import '../../screens/financeiro/financeiro_screen.dart';
import '../../services/loja_id_service.dart';
import 'financial_dashboard_pilot.dart';
import 'financial_launch_catalog.dart';
import 'financial_v2_preview_screen.dart';

/// `/financeiro`. A visão nova só entra se o piloto da loja estiver ligado
/// e marcado como somente leitura. Qualquer falha volta ao ecrã antigo.
class FinancialHomeRoute extends StatefulWidget {
  const FinancialHomeRoute({
    super.key,
    this.mesInicial,
    this.debugStoreId,
    this.debugPilot,
    this.debugSource,
    this.oldScreen,
    this.dashboard,
  });

  final DateTime? mesInicial;
  final String? debugStoreId;
  final FinancialDashboardPilot? debugPilot;
  final FinancialDashboardPilotSource? debugSource;
  final Widget Function()? oldScreen;
  final Widget Function()? dashboard;

  @override
  State<FinancialHomeRoute> createState() => _FinancialHomeRouteState();
}

class _FinancialHomeRouteState extends State<FinancialHomeRoute> {
  FinancialDashboardPilot? _pilot;
  String? _storeId;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FinancialHomeRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.debugPilot != widget.debugPilot ||
        oldWidget.debugStoreId != widget.debugStoreId ||
        oldWidget.debugSource != widget.debugSource) {
      _pilot = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (widget.debugPilot != null) {
      if (!mounted) return;
      setState(() => _pilot = widget.debugPilot);
      return;
    }
    final store = (widget.debugStoreId ?? await LojaIdService.get() ?? '').trim();
    if (!mounted) return;
    if (store.isEmpty) {
      setState(() => _pilot = FinancialDashboardPilot.disabled);
      return;
    }
    final source = widget.debugSource ?? FirestoreFinancialDashboardPilotSource();
    final pilot = await source.read(store);
    if (!mounted) return;
    setState(() {
      _storeId = store;
      _pilot = pilot;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pilot = _pilot;
    if (pilot == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!pilot.showReadOnlyDashboard) {
      final oldScreen = widget.oldScreen;
      if (oldScreen != null) return oldScreen();
      return FinanceiroScreen(mesInicial: widget.mesInicial);
    }
    final dashboard = widget.dashboard;
    if (dashboard != null) return dashboard();
    return FinancialV2PreviewScreen(
      internalOnly: false,
      operationalHub: FinancialV2OperationalPolicy.hubEnabled(
        showReadOnlyDashboard: pilot.showReadOnlyDashboard,
      ),
      debugStoreId: _storeId ?? widget.debugStoreId,
    );
  }
}
