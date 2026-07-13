import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/communication_history_builder.dart';

class CommunicationHistoryPanel extends StatelessWidget {
  const CommunicationHistoryPanel({
    super.key,
    required this.pedidoData,
  });

  final Map<String, dynamic> pedidoData;

  @override
  Widget build(BuildContext context) {
    final items = buildCommunicationHistory(pedidoData);
    final df = DateFormat('dd/MM/yyyy');
    final hf = DateFormat('HH:mm');

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
            'Central de comunicação',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'Nenhum evento de comunicação registrado neste pedido.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            )
          else
            ...items.map((e) {
              final dataStr = e.at == null ? null : df.format(e.at!);
              final horaStr = e.at == null ? null : hf.format(e.at!);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icon(e.channel), size: 20, color: _statusColor(e.status)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusColor(e.status).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(e.status),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(e.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (dataStr != null) 'Data: $dataStr',
                              if (horaStr != null) 'Hora: $horaStr',
                              if ((e.origem ?? '').isNotEmpty)
                                'Origem: ${e.origem}',
                              if ((e.detail ?? '').isNotEmpty) e.detail!,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  IconData _icon(CommunicationChannel c) {
    switch (c) {
      case CommunicationChannel.whatsapp:
        return Icons.chat;
      case CommunicationChannel.email:
        return Icons.email_outlined;
      case CommunicationChannel.mercadoPago:
        return Icons.payment;
      case CommunicationChannel.campanha:
        return Icons.campaign_outlined;
      case CommunicationChannel.roleta:
        return Icons.casino_outlined;
      case CommunicationChannel.numeroSorte:
        return Icons.confirmation_number_outlined;
    }
  }

  String _statusLabel(CommunicationStatus s) {
    switch (s) {
      case CommunicationStatus.enviado:
        return 'Enviado';
      case CommunicationStatus.pendente:
        return 'Pendente';
      case CommunicationStatus.falhou:
        return 'Falhou';
      case CommunicationStatus.reenviado:
        return 'Reenviado';
      case CommunicationStatus.desconhecido:
        return '—';
    }
  }

  Color _statusColor(CommunicationStatus s) {
    switch (s) {
      case CommunicationStatus.enviado:
      case CommunicationStatus.reenviado:
        return const Color(0xFF22C55E);
      case CommunicationStatus.pendente:
        return const Color(0xFFF59E0B);
      case CommunicationStatus.falhou:
        return const Color(0xFFEF4444);
      case CommunicationStatus.desconhecido:
        return Colors.grey;
    }
  }
}
