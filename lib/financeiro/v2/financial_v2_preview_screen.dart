import 'package:flutter/material.dart';

import '../../design_system/mp_tokens.dart';
import '../../services/loja_id_service.dart';
import '../../utils/role_utils.dart';
import 'brazil_business_date.dart';
import 'financial_dashboard_gate.dart';
import 'financial_dashboard_presentation.dart';
import 'financial_overview_loader.dart';
import 'financial_v2_dashboard_view.dart';
import 'financial_v2_operational_hub.dart';

/// Rota interna. Não substitui `/financeiro`.
class FinancialV2PreviewScreen extends StatefulWidget {
  const FinancialV2PreviewScreen({
    super.key,
    this.debugIsAdmin,
    this.debugStoreId,
    this.debugReads,
    this.debugToday,
    this.internalOnly = true,
    this.operationalHub = false,
  });

  final bool? debugIsAdmin;
  final String? debugStoreId;
  final FinancialPeriodReads? debugReads;
  final DateTime? debugToday;

  /// A rota `/financeiro_v2_preview` continua só para admin/programador.
  /// O piloto da loja chega aqui já autorizado pelo plano do Financeiro.
  final bool internalOnly;

  /// Navegação operacional. A prévia interna continua só com os cartões.
  final bool operationalHub;

  @override
  State<FinancialV2PreviewScreen> createState() =>
      _FinancialV2PreviewScreenState();
}

class _FinancialV2PreviewScreenState extends State<FinancialV2PreviewScreen> {
  final _loader = const FinancialOverviewLoader();
  FinancialDashboardPeriodKind _kind = FinancialDashboardPeriodKind.currentMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  FinancialDashboardViewData? _data;
  bool _loading = true;
  bool _allowed = false;
  String? _storeId;
  int _loadTicket = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  DateTime get _today =>
      widget.debugToday ?? BrazilBusinessDate.dateOnly(DateTime.now());

  Future<void> _bootstrap() async {
    final admin = widget.internalOnly
        ? (widget.debugIsAdmin ?? await _sessionAdmin())
        : true;
    if (!FinancialV2DashboardGate.previewAllowed(admin)) {
      if (!mounted) return;
      setState(() {
        _allowed = false;
        _loading = false;
      });
      return;
    }
    final store = (widget.debugStoreId ?? await LojaIdService.get() ?? '').trim();
    if (!mounted) return;
    setState(() {
      _allowed = true;
      _storeId = store;
    });
    await _reload();
  }

  Future<bool> _sessionAdmin() async {
    final role = await RoleUtils.loadFromSession();
    return role == UserRole.admin || role == UserRole.programador;
  }

  Future<void> _reload() async {
    final store = (_storeId ?? '').trim();
    if (store.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final ticket = ++_loadTicket;
    setState(() => _loading = true);
    final reads = widget.debugReads ?? FirestoreFinancialPeriodReads();
    final data = await _loader.load(
      storeId: store,
      period: financialDashboardPeriod(
        kind: _kind,
        today: _today,
        customStart: _customStart,
        customEnd: _customEnd,
      ),
      today: _today,
      reads: reads,
    );
    if (!mounted || ticket != _loadTicket) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _pickCustom() async {
    final start = await showDatePicker(
      context: context,
      initialDate: _customStart ?? _today,
      firstDate: DateTime(2018),
      lastDate: DateTime(_today.year + 1),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: _customEnd ?? start,
      firstDate: start,
      lastDate: DateTime(_today.year + 1),
    );
    if (end == null || !mounted) return;
    setState(() {
      _customStart = start;
      _customEnd = end;
      _kind = FinancialDashboardPeriodKind.custom;
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Visão financeira')),
      body: !_allowed
          ? const Center(
              child: Text(
                'Prévia interna indisponível.',
                style: MpType.body,
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _data == null
                  ? const Center(
                      child: Text(unavailableValue, style: MpType.body),
                    )
                  : FinancialV2OperationalHub(
                      enabled: widget.operationalHub,
                      storeId: _storeId,
                      overview: FinancialV2DashboardView(
                        data: _data!,
                        periodKind: _kind,
                        onPeriod: (kind) {
                          if (kind == FinancialDashboardPeriodKind.custom) {
                            _pickCustom();
                            return;
                          }
                          setState(() => _kind = kind);
                          _reload();
                        },
                        onRefresh: _reload,
                        onOpenReceivables: () =>
                            Navigator.of(context).pushNamed('/contas_receber'),
                        onOpenPayables: () =>
                            Navigator.of(context).pushNamed('/contas_pagar'),
                      ),
                    ),
    );
  }
}
