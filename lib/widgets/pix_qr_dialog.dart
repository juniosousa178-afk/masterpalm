// lib/widgets/pix_qr_dialog.dart
// Dialog para exibir QR Code PIX com valor e op??o de copiar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Exibe um dialog com QR Code PIX, valor e bot?o para copiar o c?digo.
///
/// [pixPayload] - String PIX Copia e Cola (BR Code) ou do Mercado Pago
/// [valor] - Valor em reais para exibi??o
/// [pedidoId] - ID do pedido para refer?ncia (opcional)
void showPixQrDialog({
  required BuildContext context,
  required String pixPayload,
  required double valor,
  String? pedidoId,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.pix, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          const Text('Pagar com PIX'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Escaneie o QR Code com o app do seu banco. O valor j? vem preenchido.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: QrImageView(
                data: pixPayload,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Valor: ',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    'R\$ ${valor.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            if (pedidoId != null) ...[
              const SizedBox(height: 8),
              Text(
                'Pedido #$pedidoId',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar c?digo PIX'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: pixPayload));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('C?digo PIX copiado! Cole no app do seu banco.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

