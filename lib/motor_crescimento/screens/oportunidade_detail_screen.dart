// lib/motor_crescimento/screens/oportunidade_detail_screen.dart
// Etapa 3: Detalhe da oportunidade com sugestão e execução real de campanha.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/oportunidade_crescimento.dart';
import '../models/sugestao_campanha.dart';
import '../services/motor_crescimento_executor_service.dart';
import '../services/motor_crescimento_sugestor_service.dart';
import 'campanha_motor_result_screen.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _warningColor = Color(0xFFF59E0B);
const Color _errorColor = Color(0xFFEF4444);
const Color _surfaceDark = Color(0xFF1E293B);
const Color _cardDark = Color(0xFF0F172A);

/// Tela de detalhe da oportunidade com sugestão de campanha (Etapa 3).
class OportunidadeDetailScreen extends StatefulWidget {
  final OportunidadeCrescimento oportunidade;
  final String lojaId;

  const OportunidadeDetailScreen({super.key, required this.oportunidade, required this.lojaId});

  @override
  State<OportunidadeDetailScreen> createState() => _OportunidadeDetailScreenState();
}

class _OportunidadeDetailScreenState extends State<OportunidadeDetailScreen> {
  Future<SugestaoCampanha>? _future;
  SugestaoCampanha? _sugestao;
  bool _executando = false;

  @override
  void initState() {
    super.initState();
    _future = MotorCrescimentoSugestorService.sugerirCampanha(widget.oportunidade);
  }

  Future<void> _executar() async {
    final s = _sugestao;
    if (s == null || _executando) return;
    setState(() => _executando = true);
    try {
      final result = await MotorCrescimentoExecutorService.executar(
        lojaId: widget.lojaId,
        oportunidade: widget.oportunidade,
        sugestao: s,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CampanhaMotorResultScreen(result: result),
        ),
      );
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
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  void _copiar(String texto, String label) {
    if (texto.isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copiado'),
          backgroundColor: _primaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.oportunidade;
    final color = o.tipo == TipoOportunidade.produtoParado ? _warningColor : _errorColor;

    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: AppBar(
        title: const Text('Sugestão de campanha', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<SugestaoCampanha>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _primaryColor),
                  SizedBox(height: 16),
                  Text('Gerando sugestão…', style: TextStyle(color: Colors.white70)),
                ],
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
                    Text(
                      'Não foi possível gerar a sugestão.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Voltar'),
                    ),
                  ],
                ),
              ),
            );
          }
          _sugestao = snap.data;
          if (_sugestao == null) return const SizedBox.shrink();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCardOportunidade(o, color),
                const SizedBox(height: 20),
                _buildCardSugestao(_sugestao!),
                const SizedBox(height: 20),
                _buildBlocoTexto(
                  'Texto de promoção',
                  _sugestao!.textoPromocao,
                  Icons.campaign_outlined,
                ),
                const SizedBox(height: 16),
                _buildBlocoTexto(
                  'Mensagem WhatsApp',
                  _sugestao!.mensagemWhatsApp,
                  Icons.chat_outlined,
                ),
                const SizedBox(height: 16),
                _buildBlocoTexto(
                  'Legenda Instagram',
                  _sugestao!.legendaInstagram,
                  Icons.camera_alt_outlined,
                ),
                const SizedBox(height: 24),
                _buildBotaoExecutar(_sugestao!),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardOportunidade(OportunidadeCrescimento o, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  o.tipo == TipoOportunidade.produtoParado
                      ? Icons.inventory_2_outlined
                      : Icons.warning_amber_outlined,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.tipoLabel, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                    Text(o.entidadeNome, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(o.descricao, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCardSugestao(SugestaoCampanha s) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withOpacity(0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(s.descricao, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
          if (s.percentualDesconto > 0) ...[
            const SizedBox(height: 12),
            Text('Desconto sugerido: ${s.percentualDesconto.toInt()}%', style: const TextStyle(color: _primaryColor, fontWeight: FontWeight.w600)),
            Text('Código cupom: ${s.codigoCupomSugerido}', style: TextStyle(color: Colors.white.withOpacity(0.8))),
          ],
        ],
      ),
    );
  }

  Widget _buildBlocoTexto(String label, String texto, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: _primaryColor),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
              IconButton(
                onPressed: () => _copiar(texto, label),
                icon: const Icon(Icons.copy_outlined, size: 20, color: Colors.white70),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(texto, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildBotaoExecutar(SugestaoCampanha s) {
    final podeExecutar = s.codigoCupomSugerido.trim().isNotEmpty && !_executando;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: podeExecutar ? _executar : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primaryColor.withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _executando
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Criando campanha…', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rocket_launch_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('Executar campanha', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}
