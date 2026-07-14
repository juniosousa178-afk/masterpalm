import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../design_system/mp_components.dart';
import '../../design_system/mp_tokens.dart';
import '../../services/marketing_dashboard/marketing_dashboard_aggregators.dart';
import '../../services/marketing_dashboard/marketing_dashboard_repository.dart';

class CampanhaDetalheDashboardScreen extends StatefulWidget {
  const CampanhaDetalheDashboardScreen({
    super.key,
    required this.lojaId,
    required this.campanhaId,
  });

  final String lojaId;
  final String campanhaId;

  @override
  State<CampanhaDetalheDashboardScreen> createState() =>
      _CampanhaDetalheDashboardScreenState();
}

class _CampanhaDetalheDashboardScreenState
    extends State<CampanhaDetalheDashboardScreen> {
  final _repo = MarketingDashboardRepository();
  final _busca = TextEditingController();
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final _date = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  String? _erro;
  Map<String, dynamic>? _campanha;
  List<Map<String, dynamic>> _participantes = [];
  List<Map<String, dynamic>> _historico = [];
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
      _erro = null;
    });
    try {
      final c = await _repo.obterCampanha(
        lojaId: widget.lojaId,
        campanhaId: widget.campanhaId,
      );
      final p = await _repo.listarParticipantesCampanha(
        lojaId: widget.lojaId,
        campanhaId: widget.campanhaId,
      );
      final h = await _repo.listarHistoricoSorteio(
        lojaId: widget.lojaId,
        campanhaId: widget.campanhaId,
      );
      if (!mounted) return;
      setState(() {
        _campanha = c;
        _participantes = p;
        _historico = h;
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

  List<Map<String, dynamic>> get _filtrados {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return _participantes;
    return _participantes.where((p) {
      final blob = [
        p['clienteNome'],
        p['nomeCliente'],
        p['clienteTelefone'],
        p['telefone'],
        p['clienteEmail'],
        p['email'],
        p['numeroSorte'],
        p['numero'],
        p['pedidoId'],
        p['vendaId'],
      ].where((e) => e != null).map((e) => e.toString().toLowerCase()).join(' ');
      return blob.contains(q);
    }).toList();
  }

  String get _resumoTexto {
    final c = _campanha ?? {};
    final nome = (c['nome'] ?? c['titulo'] ?? 'Campanha').toString();
    final premio = (c['premioDescricao'] ?? c['premio'] ?? '').toString();
    return 'Campanha: $nome\nPrêmio: $premio\n'
        'Participantes: ${_participantes.length}\n'
        'Histórico sorteios: ${_historico.length}';
  }

  Future<void> _exportar() async {
    await Share.share(_resumoTexto, subject: 'Campanha MasterPalm');
  }

  @override
  Widget build(BuildContext context) {
    final nome = (_campanha?['nome'] ?? _campanha?['titulo'] ?? 'Campanha')
        .toString();
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        backgroundColor: MpColors.marketing,
        foregroundColor: Colors.white,
        title: Text(nome),
        actions: [
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy),
            onPressed: () => mpCopyToClipboard(context, _resumoTexto),
          ),
          IconButton(
            tooltip: 'Compartilhar',
            icon: const Icon(Icons.share),
            onPressed: _exportar,
          ),
          IconButton(
            tooltip: 'Exportar',
            icon: const Icon(Icons.upload_file),
            onPressed: _exportar,
          ),
        ],
      ),
      body: _loading
          ? const MpLoadingState()
          : _erro != null
              ? MpErrorState(message: _erro!, onRetry: _load)
              : _campanha == null
                  ? const MpEmptyState(title: 'Campanha não encontrada')
                  : _body(),
    );
  }

  Widget _body() {
    final c = _campanha!;
    final ativa = campanhaEstaAtiva(c);
    final inicio = parseMarketingDate(c['dataInicio'] ?? c['criadaEm']);
    final fim = parseMarketingDate(c['dataFim']);
    final premio = (c['premioDescricao'] ?? c['premio'] ?? '—').toString();
    final reg = (c['regulamento'] ?? c['descricao'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(MpSpacing.lg),
      children: [
        Row(
          children: [
            MpBadge(
              label: ativa ? 'Ativa' : 'Encerrada',
              tone: ativa ? MpBadgeTone.success : MpBadgeTone.neutral,
            ),
            const Spacer(),
            Text(
              '${_participantes.length} participantes',
              style: MpType.caption,
            ),
          ],
        ),
        const SizedBox(height: MpSpacing.md),
        MpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Informações gerais', style: MpType.body),
              const SizedBox(height: MpSpacing.sm),
              _kv('Período',
                  '${inicio != null ? _date.format(inicio) : '—'} → ${fim != null ? _date.format(fim) : '—'}'),
              _kv('Prêmio', premio),
              if (reg.trim().isNotEmpty) _kv('Regulamento', reg),
              _kv('Valor mín.',
                  _money.format((c['valorMinimo'] as num?)?.toDouble() ?? 0)),
            ],
          ),
        ),
        MpSectionHeader(title: 'Participantes / números da sorte'),
        MpSearchField(
          controller: _busca,
          hintText: 'Pesquisar participante, telefone, número…',
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: MpSpacing.sm),
        if (_filtrados.isEmpty)
          const MpEmptyState(
            title: 'Nenhum participante',
            icon: Icons.person_search_outlined,
          )
        else
          ..._filtrados.map((p) {
            final nomeP =
                (p['clienteNome'] ?? p['nomeCliente'] ?? 'Cliente').toString();
            final tel =
                (p['clienteTelefone'] ?? p['telefone'] ?? '').toString();
            final numSorte =
                (p['numeroSorte'] ?? p['numero'] ?? '').toString();
            final valor = valorParticipacao(p);
            final ped = (p['pedidoId'] ?? p['vendaId'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: MpSpacing.sm),
              child: MpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(nomeP, style: MpType.body)),
                        if (numSorte.isNotEmpty)
                          MpBadge(label: 'Nº $numSorte', tone: MpBadgeTone.info),
                      ],
                    ),
                    if (tel.isNotEmpty)
                      Text(tel, style: MpType.caption),
                    Text(
                      '${_money.format(valor)}${ped.isNotEmpty ? ' · Pedido $ped' : ''}',
                      style: MpType.caption,
                    ),
                  ],
                ),
              ),
            );
          }),
        MpSectionHeader(title: 'Histórico de sorteios'),
        if (_historico.isEmpty)
          const Text('Sem sorteios registrados.', style: MpType.caption)
        else
          ..._historico.map((h) {
            return Padding(
              padding: const EdgeInsets.only(bottom: MpSpacing.sm),
              child: MpCard(
                child: Text(
                  'Nº ${h['numero'] ?? '—'} · ${h['nomeCliente'] ?? '—'} · '
                  '${_money.format((h['valorCompra'] as num?)?.toDouble() ?? 0)}',
                  style: MpType.body,
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: MpType.caption),
          ),
          Expanded(child: Text(v, style: MpType.body)),
        ],
      ),
    );
  }
}
