import 'package:flutter/material.dart';

import '../services/vendas_period_metrics_service.dart';

/// Faixa compacta Hoje / Mês para o cabeçalho da Home.
class VendasPeriodMetricsStrip extends StatelessWidget {
  const VendasPeriodMetricsStrip({super.key, required this.lojaId});

  final String lojaId;

  @override
  Widget build(BuildContext context) {
    if (lojaId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<VendasPeriodMetricsBundle>(
      future: VendasPeriodMetricsService.load(lojaId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 72,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final b = snap.data!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: _periodCard('Hoje', b.hoje)),
              const SizedBox(width: 8),
              Expanded(child: _periodCard('Mês', b.mes)),
            ],
          ),
        );
      },
    );
  }

  Widget _periodCard(String title, VendasPeriodMetrics m) {
    String money(double v) =>
        'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 4),
          _line('Líquido', money(m.liquido)),
          _line('Bruto', money(m.bruto)),
          _line('Descontos', money(m.descontos)),
          _line('Ticket', money(m.ticketMedio)),
          _line('Vendas', '${m.quantidade}'),
        ],
      ),
    );
  }

  Widget _line(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ),
          Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
