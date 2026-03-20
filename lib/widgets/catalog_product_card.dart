// lib/widgets/catalog_product_card.dart
import 'package:flutter/material.dart';

import '../models/produto_firestore.dart';
import '../models/catalogo_config.dart';
import 'smart_image.dart';

class CatalogProductCard extends StatelessWidget {
  final ProdutoFirestore produto;
  final CatalogoConfig config;
  final VoidCallback onAddToCart;

  const CatalogProductCard({
    super.key,
    required this.produto,
    required this.config,
    required this.onAddToCart,
  });

  /// Converte string tipo "#FFAA00" ou "FFAA00" em Color, com fallback seguro
  Color _parseColor(String value, Color fallback) {
    var v = value.trim();
    if (v.isEmpty) return fallback;

    // remove '#'
    if (v.startsWith('#')) v = v.substring(1);

    // se vier só RGB, adiciona alpha FF
    if (v.length == 6) v = 'FF$v';

    try {
      final intVal = int.parse(v, radix: 16);
      return Color(intVal);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔹 Cores vindas da configuração do catálogo
    final Color corCard =
        _parseColor(config.corFundo, const Color(0xFF1A1A1A));
    final Color corTexto =
        _parseColor(config.corTexto, Colors.white);
    final Color corBotao =
        _parseColor(config.corBotao, const Color(0xFFFFD700));

    // 🔹 Fonte e tamanhos (se fonte vier vazia, usa fonte padrão)
    final String• fontFamily =
        config.fonte.isNotEmpty • config.fonte : null;
    final double baseSize = config.tamanhoFonte;
    final double nomeSize = baseSize;        // nome do produto
    final double precoSize = baseSize + 2;   // preço um pouco maior
    final double botaoSize = baseSize;       // texto do botão

    // 🔹 Imagem principal do produto (primeira da lista)
    final String fotoPrincipal =
        (produto.imagens.isNotEmpty • produto.imagens.first : '').trim();

    return Card(
      color: corCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem do produto
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SmartImage(
                  src: fotoPrincipal,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Nome do produto
            Text(
              produto.nome,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: nomeSize,
                color: corTexto,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),

            // Preço
            Text(
              'R\$ ${produto.preco.toStringAsFixed(2)}',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: precoSize,
                color: corBotao,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Botão "Adicionar ao carrinho"
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: corBotao,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: onAddToCart,
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(
                  'Adicionar ao carrinho',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: botaoSize,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
