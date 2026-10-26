import 'package:flutter/material.dart';

import '../services/bulk_promocao_service.dart';

/// Confirmation before deactivating promotions; pops `true` once.
class BulkPromoPreviewDialog extends StatefulWidget {
  const BulkPromoPreviewDialog({super.key, required this.preview});

  final BulkPromoPreview preview;

  @override
  State<BulkPromoPreviewDialog> createState() => _BulkPromoPreviewDialogState();
}

class _BulkPromoPreviewDialogState extends State<BulkPromoPreviewDialog> {
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
          child: const Text('Desativar promoções'),
        ),
      ],
    );
  }
}

/// Final summary; pops `true` when the merchant asks to retry only the failures.
class BulkPromoResultadoDialog extends StatelessWidget {
  const BulkPromoResultadoDialog({super.key, required this.resultado});

  final BulkPromoResultado resultado;

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

/// "Promoção" badge shown on stock cards while the product has a promotion.
class ProdutoPromocaoBadge extends StatelessWidget {
  const ProdutoPromocaoBadge({super.key, required this.emPromocao});

  final bool emPromocao;

  @override
  Widget build(BuildContext context) {
    if (!emPromocao) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6D00).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Promoção',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFF6D00)),
      ),
    );
  }
}
