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
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_icon(e.channel), size: 20),
                title: Text(e.label, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  [
                    _statusLabel(e.status),
                    if (e.at != null) df.format(e.at!),
                    if ((e.detail ?? '').isNotEmpty) e.detail!,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11),
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
}
