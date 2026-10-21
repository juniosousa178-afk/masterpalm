import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/bulk_pix_discount_service.dart';

/// Confirmation before removing the Pix discount; pops `true` once.
class BulkPixPreviewDialog extends StatefulWidget {
  const BulkPixPreviewDialog({super.key, required this.preview});

  final BulkPixPreview preview;

  @override
  State<BulkPixPreviewDialog> createState() => _BulkPixPreviewDialogState();
}

class _BulkPixPreviewDialogState extends State<BulkPixPreviewDialog> {
  bool _confirmado = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return AlertDialog(
      title: Text(preview.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final linha in preview.linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(linha),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _confirmado ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: preview.podeExecutar && !_confirmado
              ? () {
                  setState(() => _confirmado = true);
                  Navigator.pop(context, true);
                }
              : null,
          child: const Text('Remover desconto no Pix'),
        ),
      ],
    );
  }
}

/// Blocking progress while batches run; cannot be dismissed.
class BulkPixProgressDialog extends StatelessWidget {
  const BulkPixProgressDialog({super.key, required this.progresso});

  final ValueListenable<String> progresso;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progresso,
                builder: (_, texto, __) => Text(texto),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Final summary; pops `true` when the merchant asks to retry failed batches.
class BulkPixResultadoDialog extends StatelessWidget {
  const BulkPixResultadoDialog({super.key, required this.resultado});

  final BulkPixResultado resultado;

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
            if (!r.sucessoTotal) ...[
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
        if (!r.sucessoTotal && r.idsParaNovaTentativa.isNotEmpty)
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tentar novamente')),
      ],
    );
  }
}
