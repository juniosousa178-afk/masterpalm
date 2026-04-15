import 'package:flutter/material.dart';

import '../models/catalog_avaliacao.dart';

/// Card de avaliação para o painel de moderação (loja atual).
class AdminCatalogAvaliacaoCard extends StatelessWidget {
  final CatalogAvaliacao avaliacao;
  final bool processando;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;

  const AdminCatalogAvaliacaoCard({
    super.key,
    required this.avaliacao,
    required this.processando,
    required this.onAprovar,
    required this.onRejeitar,
  });

  static String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  static ({String label, Color bg, Color border, Color fg}) _statusStyle(
    CatalogAvaliacaoStatus s,
  ) {
    switch (s) {
      case CatalogAvaliacaoStatus.pendente:
        return (
          label: 'Pendente',
          bg: const Color(0xFFFFF7ED),
          border: const Color(0xFFFDBA74),
          fg: const Color(0xFFC2410C),
        );
      case CatalogAvaliacaoStatus.aprovado:
        return (
          label: 'Aprovado',
          bg: const Color(0xFFF0FDF4),
          border: const Color(0xFF86EFAC),
          fg: const Color(0xFF166534),
        );
      case CatalogAvaliacaoStatus.rejeitado:
        return (
          label: 'Rejeitado',
          bg: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          fg: const Color(0xFFB91C1C),
        );
    }
  }

  String _initialNome() {
    final n = avaliacao.nomeCliente.trim();
    if (n.isEmpty) return '?';
    return n.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fotos = avaliacao.fotos.take(4).toList();
    final st = _statusStyle(avaliacao.status);
    final enviadoEm = avaliacao.criadoEm ?? avaliacao.data;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer.withOpacity(0.9),
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    _initialNome(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        avaliacao.nomeCliente.isEmpty
                            ? '(Sem nome)'
                            : avaliacao.nomeCliente,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: st.bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: st.border, width: 1),
                        ),
                        child: Text(
                          st.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: st.fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.35)),
            const SizedBox(height: 12),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < avaliacao.estrelas
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 20,
                  color: Colors.amber.shade700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              avaliacao.comentario,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.4,
                color: theme.textTheme.bodyLarge?.color?.withOpacity(0.92),
              ),
            ),
            const SizedBox(height: 12),
            _metaLine(
              context,
              Icons.schedule_outlined,
              'Enviado em: ${_formatDate(enviadoEm)}',
            ),
            if (avaliacao.aprovadoEm != null) ...[
              const SizedBox(height: 4),
              _metaLine(
                context,
                Icons.verified_outlined,
                'Aprovado em: ${_formatDate(avaliacao.aprovadoEm!)}',
              ),
            ],
            if (fotos.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Fotos',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withOpacity(0.75),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fotos
                    .map(
                      (url) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          url,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 76,
                            height: 76,
                            color: Colors.grey.shade200,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 26,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: processando ? null : onAprovar,
                  icon: processando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: Text(processando ? 'Aprovando…' : 'Aprovar'),
                ),
                OutlinedButton.icon(
                  onPressed: processando ? null : onRejeitar,
                  icon: const Icon(Icons.cancel_outlined, size: 20),
                  label: const Text('Rejeitar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaLine(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.hintColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.88),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
