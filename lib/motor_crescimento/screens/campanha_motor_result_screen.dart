// lib/motor_crescimento/screens/campanha_motor_result_screen.dart
// Tela de resultado da execução de campanha (Etapa 3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/campanha_motor_result.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _surfaceDark = Color(0xFF1E293B);
const Color _cardDark = Color(0xFF0F172A);
const Color _successColor = Color(0xFF22C55E);

/// Tela de resultado da execução de campanha.
class CampanhaMotorResultScreen extends StatelessWidget {
  final CampanhaMotorResult result;

  const CampanhaMotorResultScreen({super.key, required this.result});

  void _copiar(String texto, String label, BuildContext context) {
    if (texto.isEmpty) return;
    Clipboard.setData(ClipboardData(text: texto));
    if (context.mounted) {
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
    if (!result.sucesso) {
      return Scaffold(
        backgroundColor: _surfaceDark,
        appBar: AppBar(
          title: const Text('Erro', style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: _surfaceDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                result.mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final c = result.campanha!;

    return Scaffold(
      backgroundColor: _surfaceDark,
      appBar: AppBar(
        title: const Text('Campanha criada', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _successColor.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle, color: _successColor, size: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result.mensagem,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (result.cupomCriado || c.codigoCupom.isNotEmpty) _buildCard(
              context: context,
              label: 'Cupom',
              valor: c.codigoCupom,
              icon: Icons.local_offer_outlined,
              onCopiar: () => _copiar(c.codigoCupom, 'Cupom', context),
            ),
            if (result.linkGerado || c.linkPromocao.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildCard(
                context: context,
                label: 'Link de promoção',
                valor: c.linkPromocao,
                icon: Icons.link,
                onCopiar: () => _copiar(c.linkPromocao, 'Link', context),
              ),
            ],
            if (c.textos['textoPromocao']?.isNotEmpty ?? false) ...[
              const SizedBox(height: 16),
              _buildCard(
                context: context,
                label: 'Texto promocional',
                valor: c.textos['textoPromocao']!,
                icon: Icons.campaign_outlined,
                onCopiar: () => _copiar(c.textos['textoPromocao']!, 'Texto', context),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.done),
              label: const Text('Concluir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required String label,
    required String valor,
    required IconData icon,
    required VoidCallback onCopiar,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _primaryColor),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: onCopiar,
                icon: const Icon(Icons.copy_outlined, size: 20, color: Colors.white70),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            valor,
            style: TextStyle(color: Colors.white.withValues(alpha:0.9), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
