import 'package:flutter/material.dart';

import '../core/premio_roleta_snapshot.dart';

/// Card do prêmio da roleta na tela de pré-pedidos (vendedor).
class PremioRoletaVendedorCard extends StatelessWidget {
  const PremioRoletaVendedorCard({
    super.key,
    required this.premioRaw,
  });

  final dynamic premioRaw;

  @override
  Widget build(BuildContext context) {
    final snap = premioRoletaFromFirestoreMap(premioRaw);
    if (snap == null) return const SizedBox.shrink();

    final tipoLabel = PremioRoletaFormatter.tipoLabelVendedor(snap);
    final statusLabel = PremioRoletaFormatter.statusLabel(snap.status);
    final aplicacao = PremioRoletaFormatter.textoAplicacao(snap);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🎁', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'Prêmio da roleta',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (tipoLabel.isNotEmpty)
            Text(
              'Tipo: $tipoLabel',
              style: const TextStyle(fontSize: 13),
            ),
          if (snap.codigo != null && snap.codigo!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Código: ${snap.codigo!.toUpperCase()}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Status: $statusLabel',
            style: const TextStyle(fontSize: 13),
          ),
          if (aplicacao.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Aplicação: $aplicacao',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ],
        ],
      ),
    );
  }
}
