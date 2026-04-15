import 'package:flutter/material.dart';

import '../../../models/catalog_avaliacao.dart';

class CatalogAvaliacaoCard extends StatelessWidget {
  final CatalogAvaliacao avaliacao;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;
  /// Largura fixa (lista horizontal). Se null, usa 320. No carrossel, passe a largura da página.
  final double? cardWidth;

  const CatalogAvaliacaoCard({
    super.key,
    required this.avaliacao,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
    this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    final fotos = avaliacao.fotos.take(3).toList();
    final textSecondary = textColor.withOpacity(0.72);

    return Container(
      width: cardWidth ?? 320,
      padding: const EdgeInsets.all(14),
      margin: EdgeInsets.only(right: cardWidth != null ? 0 : 12),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  avaliacao.nomeCliente,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (avaliacao.isMock)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Exemplo',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < avaliacao.estrelas ? Icons.star_rounded : Icons.star_border_rounded,
                size: 16,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            avaliacao.comentario,
            style: TextStyle(
              color: textColor.withOpacity(0.92),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (fotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      fotos[index],
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 58,
                        height: 58,
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 16,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const Spacer(),
          const SizedBox(height: 10),
          Text(
            _formatDate(avaliacao.data),
            style: TextStyle(
              color: textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    return '$dd/$mm/$yyyy';
  }
}
