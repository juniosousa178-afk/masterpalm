// lib/motor_crescimento/screens/motor_crescimento_screen.dart
// Etapa 1: Painel do Motor de Crescimento IA. Apenas exibição de oportunidades.
// Sem automação de campanhas ou criação de cupom.

import 'package:flutter/material.dart';

import '../models/oportunidade_crescimento.dart';
import '../services/motor_crescimento_orchestrator.dart';
import 'oportunidade_detail_screen.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _warningColor = Color(0xFFF59E0B);
const Color _errorColor = Color(0xFFEF4444);

/// Tela principal do Motor de Crescimento IA (Etapa 1).
class MotorCrescimentoScreen extends StatefulWidget {
  final String lojaId;

  const MotorCrescimentoScreen({super.key, required this.lojaId});

  @override
  State<MotorCrescimentoScreen> createState() => _MotorCrescimentoScreenState();
}

/// Quantidade de oportunidades na primeira carga (abre a tela rápido; resto carrega em background).
const int _primeiraPaginaLimit = 30;

class _MotorCrescimentoScreenState extends State<MotorCrescimentoScreen> {
  Future<MotorCrescimentoPainel>? _future;
  bool _carregandoResto = false;

  @override
  void initState() {
    super.initState();
    _carregarPrimeiraPagina();
  }

  void _carregarPrimeiraPagina() {
    _future = MotorCrescimentoOrchestrator.carregarPainel(
      widget.lojaId,
      limit: _primeiraPaginaLimit,
    );
    _carregarRestoEmBackground();
  }

  void _carregarRestoEmBackground() {
    MotorCrescimentoOrchestrator.carregarPainel(widget.lojaId).then((painelCompleto) {
      if (!mounted) return;
      if (painelCompleto.oportunidades.length <= _primeiraPaginaLimit) return;
      setState(() {
        _future = Future.value(painelCompleto);
        _carregandoResto = false;
      });
    });
    if (mounted) setState(() => _carregandoResto = true);
  }

  @override
  void didUpdateWidget(MotorCrescimentoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaId != widget.lojaId) {
      _carregarPrimeiraPagina();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Motor de Crescimento IA',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: widget.lojaId.isEmpty
          ? const Center(
              child: Text('Nenhuma loja ativa. Configure a loja nas Configurações.'),
            )
          : FutureBuilder<MotorCrescimentoPainel>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const LinearProgressIndicator(color: _primaryColor),
                          const SizedBox(height: 20),
                          Text(
                            'Carregando primeiras $_primeiraPaginaLimit oportunidades…',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface.withValues(alpha:0.8),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar as oportunidades.',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }
                final painel = snap.data;
                if (painel == null) return const SizedBox.shrink();

                return RefreshIndicator(
                  onRefresh: () async {
                    _carregarPrimeiraPagina();
                    await _future;
                    if (mounted) setState(() {});
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMetricas(painel),
                        if (_carregandoResto)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const LinearProgressIndicator(color: _primaryColor),
                                const SizedBox(height: 8),
                                Text(
                                  'Carregando mais oportunidades…',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                        _buildSecaoOportunidades(painel, theme),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildMetricas(MotorCrescimentoPainel painel) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Métricas',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricaCard(
                    label: 'Ticket médio',
                    valor: 'R\$ ${painel.ticketMedio.toStringAsFixed(2).replaceAll('.', ',')}',
                    subtitle: 'Últimos 30 dias',
                    icon: Icons.receipt_long,
                    color: _primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricaCard(
                    label: 'Produtos parados',
                    valor: '${painel.totalProdutosParados}',
                    subtitle: 'Sem venda em 30 dias',
                    icon: Icons.inventory_2_outlined,
                    color: _warningColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricaCard(
                    label: 'Estoque baixo',
                    valor: '${painel.totalEstoqueBaixo}',
                    subtitle: 'Abaixo do mínimo',
                    icon: Icons.warning_amber_outlined,
                    color: _errorColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecaoOportunidades(
    MotorCrescimentoPainel painel,
    ThemeData theme,
  ) {
    if (painel.oportunidades.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tudo em ordem! Nenhuma oportunidade no momento.',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final parados = painel.oportunidades
        .where((o) => o.tipo == TipoOportunidade.produtoParado)
        .toList();
    final estoqueBaixo = painel.oportunidades
        .where((o) => o.tipo == TipoOportunidade.estoqueBaixo)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Oportunidades',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        if (parados.isNotEmpty) ...[
          const Text(
            'Produtos parados',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _warningColor,
            ),
          ),
          const SizedBox(height: 8),
          ...parados.map((o) => _OportunidadeTile(oportunidade: o, onTap: () => _navegarParaDetalhe(context, o))),
          const SizedBox(height: 16),
        ],
        if (estoqueBaixo.isNotEmpty) ...[
          const Text(
            'Estoque baixo',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _errorColor,
            ),
          ),
          const SizedBox(height: 8),
          ...estoqueBaixo.map((o) => _OportunidadeTile(oportunidade: o, onTap: () => _navegarParaDetalhe(context, o))),
        ],
      ],
    );
  }

  void _navegarParaDetalhe(BuildContext context, OportunidadeCrescimento o) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OportunidadeDetailScreen(
          oportunidade: o,
          lojaId: widget.lojaId,
        ),
      ),
    );
  }
}

class _MetricaCard extends StatelessWidget {
  final String label;
  final String valor;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricaCard({
    required this.label,
    required this.valor,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OportunidadeTile extends StatelessWidget {
  final OportunidadeCrescimento oportunidade;
  final VoidCallback onTap;

  const _OportunidadeTile({required this.oportunidade, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = oportunidade.tipo == TipoOportunidade.produtoParado
        ? _warningColor
        : _errorColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha:0.15),
          child: Icon(
            oportunidade.tipo == TipoOportunidade.produtoParado
                ? Icons.inventory_2_outlined
                : Icons.warning_amber_outlined,
            color: color,
            size: 22,
          ),
        ),
        title: Text(
          oportunidade.entidadeNome,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(oportunidade.descricao),
        trailing: TextButton(
          onPressed: onTap,
          child: const Text('Ver sugestão'),
        ),
      ),
    );
  }
}
