// lib/screens/public_catalog/widgets/catalog_minimal_best_sellers.dart
// Seção horizontal "Mais vendidos" — layout minimalista apenas.

import 'package:flutter/material.dart';

import '../../../utils/safe_parse.dart';
import '../catalog_product_card_size.dart';
import '../../../widgets/smart_image.dart';
import 'catalog_product_detail_screen.dart';

/// Lista horizontal de produtos em destaque (mais vendidos ou fallback elegante).
class CatalogMinimalBestSellersSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> products;
  final String lojaId;
  final List<Map<String, dynamic>> todosProdutos;
  final void Function(Map<String, dynamic>) onAdd;
  final VoidCallback? onAbrirCarrinho;
  final String? catalogShareUrl;
  final Color textColor;
  final Color cardColor;
  final Color priceColor;
  final String? prazoEntregaTexto;
  final String? nomeLoja;
  final String? contatoWhatsapp;
  final String? politicaFrete;
  final void Function(String productId)? onProductViewed;
  final String productCardSize;

  const CatalogMinimalBestSellersSection({
    super.key,
    required this.title,
    required this.products,
    required this.lojaId,
    required this.todosProdutos,
    required this.onAdd,
    this.onAbrirCarrinho,
    this.catalogShareUrl,
    required this.textColor,
    required this.cardColor,
    required this.priceColor,
    this.prazoEntregaTexto,
    this.nomeLoja,
    this.contatoWhatsapp,
    this.politicaFrete,
    this.onProductViewed,
    this.productCardSize = CatalogProductCardSize.medium,
  });

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  String _parceladoTexto(Map<String, dynamic> p, double precoBase) {
    final divideSemJuros = safeBool(p['divideSemJuros']);
    final n = safeInt(p['maxParcelasSemJuros'], 12).clamp(1, 24);
    if (divideSemJuros) return '${n}x R\$ ${_fmt2(precoBase / n)}';
    return '${n}x R\$ ${_fmt2(precoBase / n)}';
  }

  void _openDetail(BuildContext context, Map<String, dynamic> p) {
    onProductViewed?.call(safeStr(p['id']));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogProductDetailScreen.fromProdutoMap(
          p: p,
          lojaId: lojaId,
          onAdd: onAdd,
          onAbrirCarrinho: onAbrirCarrinho,
          catalogShareUrl: catalogShareUrl,
          nomeLoja: nomeLoja,
          contatoWhatsapp: contatoWhatsapp,
          politicaFrete: politicaFrete,
          prazoEntregaTexto: prazoEntregaTexto,
          todosProdutos: todosProdutos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final narrow = w < 420;
        final hPad = narrow ? 12.0 : 16.0;
        final rowPad = narrow ? 12.0 : 12.0;
        final gap = narrow ? 10.0 : 12.0;
        final cardW = CatalogProductCardSize.bestSellerCardWidth(
          productCardSize,
          screenWidth: w,
        );
        final listHeight = CatalogProductCardSize.bestSellerListHeight(
          productCardSize,
          screenWidth: w,
        );
        final radius = narrow ? 12.0 : 14.0;
        final titleSize = narrow ? 13.5 : 14.5;
        final bodyNameSize = narrow ? 11.5 : 12.0;
        final priceSize = narrow ? 11.0 : 11.5;

        return Padding(
          padding: EdgeInsets.only(bottom: narrow ? 8 : 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, narrow ? 4 : 2, hPad, narrow ? 8 : 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.trim().isEmpty ? 'Mais vendidos' : title.trim(),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.92),
                          fontSize: titleSize,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.15,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: listHeight,
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: rowPad),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => SizedBox(width: gap),
                  itemBuilder: (context, i) {
                    final p = products[i];
                    final img = safeListString(p['imagens']).isNotEmpty
                        ? safeListString(p['imagens']).first
                        : safeStr(p['imageUrl']);
                    final nome = safeStr(p['nome'], 'Produto');
                    final preco = safeDouble(p['preco']);
                    final temFaixa = p['priceMin'] != null &&
                        p['priceMax'] != null &&
                        (safeDouble(p['priceMin']) - safeDouble(p['priceMax']))
                                .abs() >
                            0.001;
                    final precoBase = temFaixa
                        ? safeDouble(p['priceMin'])
                        : preco;
                    final pixDesconto = safeDouble(p['percentualDescontoPix']);
                    final hasPix = pixDesconto > 0;
                    final pixTexto = hasPix
                        ? 'PIX R\$ ${_fmt2(precoBase * (1 - pixDesconto / 100))}'
                        : '';
                    final parceladoTexto = _parceladoTexto(p, precoBase);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openDetail(context, p),
                        borderRadius: BorderRadius.circular(radius),
                        child: Ink(
                          width: cardW,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(radius),
                            border: Border.all(
                              color: textColor.withValues(alpha: 0.06),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(radius - 1),
                                  ),
                                  child: img.isEmpty
                                      ? ColoredBox(
                                          color: cardColor,
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: textColor
                                                .withValues(alpha: 0.32),
                                            size: narrow ? 32 : 34,
                                          ),
                                        )
                                      : SmartImage(src: img, fit: BoxFit.cover),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  narrow ? 7 : 8,
                                  narrow ? 5 : 6,
                                  narrow ? 7 : 8,
                                  narrow ? 7 : 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nome,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: textColor.withValues(alpha: 0.9),
                                        fontSize: bodyNameSize,
                                        fontWeight: FontWeight.w500,
                                        height: 1.22,
                                      ),
                                    ),
                                    SizedBox(height: narrow ? 3 : 4),
                                    Text(
                                      temFaixa
                                          ? 'A partir de R\$ ${_fmt2(safeDouble(p['priceMin']))}'
                                          : 'R\$ ${_fmt2(preco)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p['emPromocao'] == true
                                            ? Colors.red[700]
                                            : priceColor,
                                        fontSize: priceSize,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                      ),
                                    ),
                                    SizedBox(height: narrow ? 2 : 3),
                                    Row(
                                      children: [
                                        if (hasPix) ...[
                                          Expanded(
                                            child: Text(
                                              pixTexto,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.green[700],
                                                fontSize: narrow ? 9.2 : 9.6,
                                                fontWeight: FontWeight.w700,
                                                height: 1.1,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            parceladoTexto,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: hasPix
                                                ? TextAlign.right
                                                : TextAlign.left,
                                            style: TextStyle(
                                              color: textColor.withValues(alpha: 0.62),
                                              fontSize: narrow ? 8.8 : 9.2,
                                              fontWeight: FontWeight.w500,
                                              height: 1.1,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
