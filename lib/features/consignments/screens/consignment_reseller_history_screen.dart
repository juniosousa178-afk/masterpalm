import 'package:flutter/material.dart';

import '../../../design_system/mp_tokens.dart';
import '../consignment_models.dart';
import '../consignment_service.dart';
import '../consignment_ui.dart';
import 'consignment_details_screen.dart';

class ConsignmentResellerHistoryScreen extends StatelessWidget {
  const ConsignmentResellerHistoryScreen({super.key, required this.lojaId});
  final String lojaId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(title: const Text('Histórico por revendedor')),
      body: StreamBuilder<List<ConsignmentDoc>>(
        stream: ConsignmentService.watchConsignments(lojaId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final byReseller = <String, List<ConsignmentDoc>>{};
          for (final c in snap.data!) {
            byReseller.putIfAbsent(c.resellerId, () => []).add(c);
          }
          if (byReseller.isEmpty) {
            return const Center(child: Text('Nenhum revendedor com consignação.'));
          }
          final ids = byReseller.keys.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ids.length,
            itemBuilder: (context, i) {
              final list = byReseller[ids[i]]!;
              final name = list.first.resellerName;
              final open = list.where((c) => c.isIssued).toList();
              final closed = list.where((c) => c.isSettled).toList();
              final sent = list.fold<int>(0, (s, c) => s + c.totalItemsSent);
              final sold = list.fold<int>(0, (s, c) => s + c.totalItemsSold);
              final returned = list.fold<int>(0, (s, c) => s + c.totalItemsReturned);
              final commission = list.fold<double>(0, (s, c) => s + c.commissionAmount);
              return Card(
                child: ExpansionTile(
                  title: Text(name),
                  subtitle: Text(
                    'Aberto ${open.length} · Encerrado ${closed.length}\n'
                    'Enviado $sent · Vendido $sold · Devolvido $returned · '
                    'Comissão ${consignmentMoney.format(commission)}',
                  ),
                  children: [
                    for (final c in list)
                      ListTile(
                        title: ConsignmentStatusChip(c.status),
                        subtitle: Text('${c.totalItemsSent} pç'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConsignmentDetailsScreen(
                              lojaId: lojaId,
                              consignmentId: c.id,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
