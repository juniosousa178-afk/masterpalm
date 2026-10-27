import 'package:flutter/material.dart';

import '../services/bulk_editorial_service.dart';

/// Final summary when not everything was confirmed; pops `true` to retry only retriable failures.
class BulkEditorialResultadoDialog extends StatelessWidget {
  const BulkEditorialResultadoDialog({super.key, required this.resultado});

  final BulkEditorialResultado resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final erro = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(r.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final linha in r.linhas) Text(linha),
            if (r.falhas.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final falha in r.falhas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${falha.mensagem}', style: TextStyle(color: erro)),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
        if (r.idsParaNovaTentativa.isNotEmpty)
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tentar novamente')),
      ],
    );
  }
}
