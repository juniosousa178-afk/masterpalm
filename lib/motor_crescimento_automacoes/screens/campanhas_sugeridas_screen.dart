// lib/motor_crescimento_automacoes/screens/campanhas_sugeridas_screen.dart
// Tela de campanhas sugeridas automaticamente pela IA.

import 'package:flutter/material.dart';

import '../../motor_crescimento/screens/campanha_motor_result_screen.dart';
import '../../motor_crescimento/services/motor_crescimento_executor_service.dart';
import '../models/campanha_automatica.dart';
import '../services/motor_crescimento_automacoes_service.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _warningColor = Color(0xFFF59E0B);
const Color _errorColor = Color(0xFFEF4444);
const Color _surfaceDark = Color(0xFF1E293B);
const Color _cardDark = Color(0xFF0F172A);

/// Tela de campanhas sugeridas pela IA de Campanhas Automáticas.
class CampanhasSugeridasScreen extends StatefulWidget {
  final String lojaId;

  const CampanhasSugeridasScreen({super.key, required this.lojaId});

  @override
  State<CampanhasSugeridasScreen> createState() => _CampanhasSugeridasScreenState();
}

class _CampanhasSugeridasScreenState extends State<CampanhasSugeridasScreen> {
  Future<List<CampanhaAutomaticaSugerida>>? _future;
  final Set<String> _ativando = {};
  /// Progresso durante o carregamento: (concluídos, total).
  (int, int)? _loadingProgress;

  void _carregarSugestoes() {
    setState(() {
      _loadingProgress = null;
      _future = MotorCrescimentoAutomacoesService.gerarSugestoesAutomaticas(
        widget.lojaId,
        onProgress: (concluidos, total) {
          if (mounted) setState(() => _loadingProgress = (concluidos, total));
        },
      );
    });
    _future!.whenComplete(() {
      if (mounted) setState(() => _loadingProgress = null);
    });
  }

  @override
  void initState() {
    super.initState();
    _carregarSugestoes();
  }

  Future<void> _ativarCampanha(
    CampanhaAutomaticaSugerida item,
  ) async {
    if (_ativando.contains(item.campanha.id)) return;
    setState(() => _ativando.add(item.campanha.id));
    try {
      final result = await MotorCrescimentoExecutorService.executar(
        lojaId: widget.lojaId,
        oportunidade: item.oportunidade,
        sugestao: item.sugestao,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CampanhaMotorResultScreen(result: result),
        ),
      );
      setState(() => _ativando.remove(item.campanha.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _ativando.remove(item.campanha.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lojaId.isEmpty) {
      return Scaffold(
        backgroundColor: _surfaceDark,
        appBar: AppBar(
          title: const Text('Campanhas sugeridas', style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: _surfaceDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            'Nenhuma loja ativa. Configure a loja nas Configurações.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Campanhas sugeridas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            Text('Ative as que fazem mais sentido para sua loja', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70)),
          ],
        ),
        backgroundColor: _surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Tooltip(
            message: 'Atualizar sugestões',
            child: IconButton(
              onPressed: _carregarSugestoes,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<CampanhaAutomaticaSugerida>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            final p = _loadingProgress;
            final total = p != null ? p.$2 : 0;
            final concluidos = p != null ? p.$1 : 0;
            final temProgresso = total > 0;
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LinearProgressIndicator(
                      color: _primaryColor,
                      value: temProgresso ? (concluidos / total) : null,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      temProgresso
                          ? 'Analisando… $concluidos/$total sugestões (${(100 * concluidos / total).round()}%)'
                          : 'Buscando oportunidades…',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pode levar até 1 minuto',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                    const SizedBox(height: 16),
                    Text(
                      snap.error?.toString() ?? 'Erro ao carregar.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _carregarSugestoes,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          final lista = snap.data ?? [];
          if (lista.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _primaryColor.withValues(alpha:0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.auto_awesome, size: 48, color: _primaryColor.withValues(alpha:0.8)),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tudo em ordem por enquanto',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Quando houver produtos parados há mais de 30 dias ou estoque baixo, aparecerão sugestões de campanha aqui para você ativar com um clique.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha:0.7), fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _carregarSugestoes();
              await _future;
            },
            color: _primaryColor,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lista.length,
              itemBuilder: (_, i) {
                return _CampanhaSugeridaCard(
                  item: lista[i],
                  ativando: _ativando.contains(lista[i].campanha.id),
                  onAtivar: () => _ativarCampanha(lista[i]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CampanhaSugeridaCard extends StatelessWidget {
  final CampanhaAutomaticaSugerida item;
  final bool ativando;
  final VoidCallback onAtivar;

  const _CampanhaSugeridaCard({
    required this.item,
    required this.ativando,
    required this.onAtivar,
  });

  @override
  Widget build(BuildContext context) {
    final c = item.campanha;
    final isPromocao = c.tipoCampanha == 'promocao';
    final color = isPromocao ? _warningColor : _errorColor;
    final isAltaPrioridade = c.prioridade == PrioridadeCampanha.alta;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAltaPrioridade ? color.withValues(alpha:0.6) : color.withValues(alpha:0.3),
          width: isAltaPrioridade ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPromocao ? Icons.local_offer_outlined : Icons.warning_amber_outlined,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.entidadeNome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            c.badgeTipo,
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isAltaPrioridade)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: _primaryColor.withValues(alpha:0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Prioridade alta', style: TextStyle(color: _primaryColor, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.motivoSugestao,
                      style: TextStyle(color: Colors.white.withValues(alpha:0.8), fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.dicaImpacto,
                      style: TextStyle(color: Colors.white.withValues(alpha:0.6), fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (c.percentualDesconto > 0 || c.codigoCupom.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (c.percentualDesconto > 0)
                    Text(
                      '${c.percentualDesconto.toInt()}% off',
                      style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  if (c.percentualDesconto > 0 && c.codigoCupom.isNotEmpty) const SizedBox(width: 12),
                  if (c.codigoCupom.isNotEmpty)
                    Text(
                      'Cupom: ${c.codigoCupom}',
                      style: TextStyle(color: Colors.white.withValues(alpha:0.95), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: ativando ? null : onAtivar,
              icon: ativando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rocket_launch_outlined, size: 18),
              label: Text(ativando ? 'Criando…' : 'Ativar campanha'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
