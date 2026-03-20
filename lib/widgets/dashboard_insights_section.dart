// lib/widgets/dashboard_insights_section.dart
// Seção de insights automáticos no painel (Home). Consome DashboardInsightsService.

import 'dart:async';
import 'package:flutter/material.dart';

import '../models/dashboard_insight.dart';
import '../services/dashboard_insights_service.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _successColor = Color(0xFF22C55E);
const Color _warningColor = Color(0xFFF59E0B);

/// Exibe lista de insights (sugestões automáticas) abaixo dos cards do dashboard.
/// [lojaId] obrigatório. [isVendedor] true oculta "melhor vendedor".
class DashboardInsightsSection extends StatefulWidget {
  final String lojaId;
  final bool isVendedor;
  final String• vendedorNome;

  const DashboardInsightsSection({
    super.key,
    required this.lojaId,
    this.isVendedor = false,
    this.vendedorNome,
  });

  @override
  State<DashboardInsightsSection> createState() =>
      _DashboardInsightsSectionState();
}

class _DashboardInsightsSectionState extends State<DashboardInsightsSection> {
  Future<DashboardInsightsResult>• _future;

  @override
  void initState() {
    super.initState();
    _future = DashboardInsightsService.loadInsights(
      lojaId: widget.lojaId,
      vendedorNome: widget.vendedorNome,
      isVendedor: widget.isVendedor,
    );
  }

  @override
  void didUpdateWidget(DashboardInsightsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaId != widget.lojaId ||
        oldWidget.isVendedor != widget.isVendedor ||
        oldWidget.vendedorNome != widget.vendedorNome) {
      _future = DashboardInsightsService.loadInsights(
        lojaId: widget.lojaId,
        vendedorNome: widget.vendedorNome,
        isVendedor: widget.isVendedor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lojaId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DashboardInsightsResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 60,
              child: Center(
                  child: CircularProgressIndicator(color: _primaryColor)),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Não foi possível carregar as sugestões.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }
        final result = snap.data;
        if (result == null || result.insights.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sugestões',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              ...result.insights.map((i) => _InsightTile(insight: i)),
            ],
          ),
        );
      },
    );
  }
}

/// Versão compacta para o card principal da Home: mostra um insight por vez,
/// trocando automaticamente como um “letreiro”.
class DashboardInsightsTicker extends StatefulWidget {
  final String lojaId;
  final bool isVendedor;
  final String• vendedorNome;

  const DashboardInsightsTicker({
    super.key,
    required this.lojaId,
    this.isVendedor = false,
    this.vendedorNome,
  });

  @override
  State<DashboardInsightsTicker> createState() =>
      _DashboardInsightsTickerState();
}

class _DashboardInsightsTickerState extends State<DashboardInsightsTicker> {
  Future<DashboardInsightsResult>• _future;
  int _currentIndex = 0;
  late final PageController _pageController;
  Timer• _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _future = DashboardInsightsService.loadInsights(
      lojaId: widget.lojaId,
      vendedorNome: widget.vendedorNome,
      isVendedor: widget.isVendedor,
    );
    _pageController = PageController();
    _startAutoAdvance();
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _future?.then((result) {
        if (!mounted || result.insights.length <= 1) return;
        final next = (_currentIndex + 1) % result.insights.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
        _currentIndex = next;
      });
    });
  }

  @override
  void didUpdateWidget(DashboardInsightsTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lojaId != widget.lojaId ||
        oldWidget.isVendedor != widget.isVendedor ||
        oldWidget.vendedorNome != widget.vendedorNome) {
      _future = DashboardInsightsService.loadInsights(
        lojaId: widget.lojaId,
        vendedorNome: widget.vendedorNome,
        isVendedor: widget.isVendedor,
      );
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lojaId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DashboardInsightsResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _primaryColor),
              ),
            ),
          );
        }
        if (snap.hasError || snap.data == null || snap.data!.insights.isEmpty) {
          return const SizedBox.shrink();
        }
        final insights = snap.data!.insights;

        // Garante que o índice esteja sempre dentro do range.
        if (_currentIndex >= insights.length) {
          _currentIndex = 0;
        }

        return SizedBox(
          height: 52,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) {
              _currentIndex = idx;
            },
            itemCount: insights.length,
            itemBuilder: (context, index) {
              final i = insights[index];
              final color = _InsightTile._colorForType(i.type);
              final icon = _InsightTile._iconForType(i.type);
              final title = _InsightTile._titleForType(i.type);
              final theme = Theme.of(context);
              return Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(icon, size: 14, color: color),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            i.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha:0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _InsightTile extends StatelessWidget {
  final DashboardInsight insight;

  const _InsightTile({required this.insight});
  static Color _colorForType(DashboardInsightType type) {
    switch (type) {
      case DashboardInsightType.produtoMaisVendido:
      case DashboardInsightType.produtoMaiorFaturamento:
      case DashboardInsightType.clienteDestaque:
      case DashboardInsightType.melhorVendedor:
        return _successColor;
      case DashboardInsightType.produtoParado:
      case DashboardInsightType.estoqueBaixo:
      case DashboardInsightType.sugestaoPromocao:
        return _warningColor;
      case DashboardInsightType.metaProgresso:
        return _primaryColor;
    }
  }

  static IconData _iconForType(DashboardInsightType type) {
    switch (type) {
      case DashboardInsightType.produtoMaisVendido:
        return Icons.trending_up;
      case DashboardInsightType.produtoMaiorFaturamento:
        return Icons.attach_money;
      case DashboardInsightType.produtoParado:
        return Icons.inventory_2_outlined;
      case DashboardInsightType.clienteDestaque:
        return Icons.person;
      case DashboardInsightType.melhorVendedor:
        return Icons.emoji_events;
      case DashboardInsightType.estoqueBaixo:
        return Icons.warning_amber_rounded;
      case DashboardInsightType.metaProgresso:
        return Icons.flag_outlined;
      case DashboardInsightType.sugestaoPromocao:
        return Icons.local_offer_outlined;
    }
  }

  /// Título amigável por tipo para exibir no letreiro (ex.: "Rank de produtos mais vendidos").
  static String _titleForType(DashboardInsightType type) {
    switch (type) {
      case DashboardInsightType.produtoMaisVendido:
        return 'Rank de produtos mais vendidos';
      case DashboardInsightType.produtoMaiorFaturamento:
        return 'Produto com maior faturamento';
      case DashboardInsightType.produtoParado:
        return 'Produto parado';
      case DashboardInsightType.clienteDestaque:
        return 'Cliente destaque';
      case DashboardInsightType.melhorVendedor:
        return 'Melhor vendedor';
      case DashboardInsightType.estoqueBaixo:
        return 'Estoque baixo';
      case DashboardInsightType.metaProgresso:
        return 'Meta e progresso';
      case DashboardInsightType.sugestaoPromocao:
        return 'Sugestão de promoção';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForType(insight.type);
    final icon = _iconForType(insight.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha:0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _titleForType(insight.type),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  insight.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (insight.subtitle != null &&
                    insight.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    insight.subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha:0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
