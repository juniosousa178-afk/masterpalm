// lib/widgets/painel_crescimento_widget.dart
// Seção "Painel de Crescimento" na home – produtos parados, estoque baixo, top vendas, carrinhos abandonados.

import 'package:flutter/material.dart';

import '../motor_crescimento/models/crescimento_resumo.dart';
import '../motor_crescimento/services/motor_crescimento_resumo_service.dart';

const Color _primaryColor = Color(0xFF6366F1);
const Color _warningColor = Color(0xFFF59E0B);
const Color _successColor = Color(0xFF22C55E);

/// Painel de crescimento da loja (resumo visual).
class PainelCrescimentoWidget extends StatelessWidget {
  final String lojaId;

  const PainelCrescimentoWidget({super.key, required this.lojaId});

  @override
  Widget build(BuildContext context) {
    if (lojaId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<CrescimentoResumo>(
      future: MotorCrescimentoResumoService.gerarResumo(lojaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
              ),
            ),
          );
        }
        final resumo = snap.data ?• const CrescimentoResumo();
        final any = resumo.produtosParados > 0 ||
            resumo.estoqueBaixo > 0 ||
            resumo.produtosTopVenda > 0 ||
            resumo.carrinhosAbandonados > 0;
        if (!any) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Text(
                  'Crescimento da loja',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.8),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _primaryColor.withValues(alpha:0.2)),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (resumo.produtosParados > 0) _chip('${resumo.produtosParados} parados', Icons.warning_amber_rounded, _warningColor),
                    if (resumo.estoqueBaixo > 0) _chip('${resumo.estoqueBaixo} estoque baixo', Icons.inventory_2_outlined, _warningColor),
                    if (resumo.produtosTopVenda > 0) _chip('${resumo.produtosTopVenda} em alta', Icons.trending_up, _successColor),
                    if (resumo.carrinhosAbandonados > 0) _chip('${resumo.carrinhosAbandonados} carrinhos', Icons.shopping_cart_outlined, _primaryColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
