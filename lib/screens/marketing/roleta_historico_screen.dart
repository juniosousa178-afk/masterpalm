import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import '../../services/loja_id_service.dart';
import '../../services/marketing_dashboard/firestore_client_error.dart';
import '../../services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import '../../services/marketing_dashboard/marketing_dashboard_repository.dart';
import '../../services/store_resolver_facade.dart';

class RoletaHistoricoScreen extends StatefulWidget {
  const RoletaHistoricoScreen({super.key, this.lojaId});

  final String? lojaId;

  @override
  State<RoletaHistoricoScreen> createState() => _RoletaHistoricoScreenState();
}

class _RoletaHistoricoScreenState extends State<RoletaHistoricoScreen> {
  final _repo = MarketingDashboardRepository();
  final _busca = TextEditingController();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _date = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  String? _erroRede;
  bool _permissionDenied = false;
  List<Map<String, dynamic>> _logs = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erroRede = null;
      _permissionDenied = false;
    });
    try {
      var id = widget.lojaId?.trim() ?? '';
      if (id.isEmpty) id = (await LojaIdService.get()) ?? '';
      if (id.isEmpty) {
        id = (await StoreResolverFacade.resolveForAdminApp()) ?? '';
      }
      if (id.isEmpty) {
        setState(() {
          _erroRede = 'Loja não resolvida';
          _loading = false;
        });
        return;
      }
      final r = await _repo.listarLogsRoletaResult(id);
      if (!mounted) return;
      if (r.availability == MarketingMetricAvailability.permissionDenied) {
        setState(() {
          _permissionDenied = true;
          _logs = const [];
          _loading = false;
        });
        return;
      }
      if (!r.historicoDisponivel) {
        setState(() {
          _erroRede = r.error?.toString() ?? 'Falha ao carregar histórico';
          _loading = false;
        });
        return;
      }
      setState(() {
        _logs = r.logs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (isFirestorePermissionDenied(e)) {
        setState(() {
          _permissionDenied = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _erroRede = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtrados => _logs
      .where((e) => roletaHistoricoCorrespondeBusca(item: e, query: _q))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        backgroundColor: MpColors.roleta,
        foregroundColor: Colors.white,
        title: const Text('Histórico da Roleta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const MpLoadingState()
          : _permissionDenied
              ? MpRestrictedAccessState(
                  title: 'Histórico indisponível',
                  subtitle:
                      'Seu perfil não possui acesso ao histórico detalhado da roleta.',
                  onBack: () => Navigator.pop(context),
                  onRetry: _load,
                )
              : _erroRede != null
                  ? MpErrorState(message: _erroRede!, onRetry: _load)
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(MpSpacing.lg),
                          child: MpSearchField(
                            controller: _busca,
                            hintText:
                                'Cliente, telefone, pedido, cupom, prêmio, data…',
                            onChanged: (v) => setState(() => _q = v),
                          ),
                        ),
                        Expanded(
                          child: _filtrados.isEmpty
                              ? const MpEmptyState(
                                  title: 'Nenhum giro encontrado',
                                  icon: Icons.casino_outlined,
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    MpSpacing.lg,
                                    0,
                                    MpSpacing.lg,
                                    MpSpacing.xl,
                                  ),
                                  itemCount: _filtrados.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: MpSpacing.sm),
                                  itemBuilder: (context, i) {
                                    final e = _filtrados[i];
                                    final premio = (e['premioLabel'] ??
                                            e['premio'] ??
                                            'Prêmio')
                                        .toString();
                                    final status = (e['status'] ?? 'registrado')
                                        .toString();
                                    final cupom = (e['cupom'] ??
                                            e['codigoCupom'] ??
                                            '')
                                        .toString();
                                    final ped = (e['pedidoId'] ??
                                            e['vendaId'] ??
                                            '')
                                        .toString();
                                    final valor = (e['valorCompraAntes'] ??
                                            e['valorCompraDepois'] ??
                                            e['premioValor'] ??
                                            0) as num?;
                                    final campanha = (e['campanhaNome'] ??
                                            e['campanhaId'] ??
                                            '')
                                        .toString();
                                    final dt = parseMarketingDate(
                                      e['criadoEm'] ?? e['createdAt'],
                                    );
                                    final nome = (e['clienteNome'] ?? 'Cliente')
                                        .toString();
                                    return MpCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  nome,
                                                  style: MpType.body,
                                                ),
                                              ),
                                              MpBadge(
                                                label: status,
                                                tone: MpBadgeTone.info,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text('Prêmio: $premio',
                                              style: MpType.caption),
                                          if (cupom.isNotEmpty)
                                            Text('Cupom: $cupom',
                                                style: MpType.caption),
                                          if (ped.isNotEmpty)
                                            Text('Pedido: $ped',
                                                style: MpType.caption),
                                          Text(
                                            'Valor: ${_money.format(valor?.toDouble() ?? 0)}',
                                            style: MpType.caption,
                                          ),
                                          if (campanha.isNotEmpty)
                                            Text('Campanha: $campanha',
                                                style: MpType.caption),
                                          if (dt != null)
                                            Text(_date.format(dt),
                                                style: MpType.caption),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
    );
  }
}
