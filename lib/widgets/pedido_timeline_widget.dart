import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/pedido_timeline_builder.dart';

class PedidoTimelineWidget extends StatelessWidget {
  const PedidoTimelineWidget({
    super.key,
    required this.pedidoData,
  });

  final Map<String, dynamic> pedidoData;

  @override
  Widget build(BuildContext context) {
    // Fail-closed: só eventos realmente ocorridos (nada de checklist fake).
    final events = buildPedidoTimelineOcorridos(pedidoData);
    final df = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timeline do pedido',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            Text(
              'Nenhum evento registrado neste pedido.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          else
            ...List.generate(events.length, (i) {
              final e = events[i];
              final last = i == events.length - 1;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Color(0xFF22C55E),
                      ),
                      if (!last)
                        Container(
                          width: 2,
                          height: 28,
                          color: const Color(0xFFBBF7D0),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: last ? 0 : 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          if (e.at != null)
                            Text(
                              df.format(e.at!),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          if ((e.detail ?? '').trim().isNotEmpty)
                            Text(
                              e.detail!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
