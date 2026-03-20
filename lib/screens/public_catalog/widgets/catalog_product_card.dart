// lib/screens/public_catalog/widgets/catalog_product_card.dart
// Card de produto – extraído do public_catalog_screen.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../../services/catalog_share_service.dart';
import '../catalog_product_card_size.dart';
import '../catalog_theme_extension.dart';
import 'catalog_gallery_view.dart';
import 'catalog_image_placeholder.dart';
import 'catalog_product_details_sheet.dart';
import 'catalog_product_detail_screen.dart';
import 'catalog_product_selection_sheet.dart';
import 'catalog_combo_variation_sheet.dart';

class CatalogProductCard extends StatefulWidget {
  final String id;
  final String name;
  final String imageUrl;
  final List<String> imagens;
  final String descricao;
  final String slug;
  final double price;
  final double• priceMin;
  final double• priceMax;
  final Map<String, double>• precoPorTamanho;
  final double peso;
  final String tipoEmbalagem;
  final bool emPromocao;
  final double• precoOriginal;
  final double percentualPromo;
  final double valorPromo;
  final int quantidade;
  final Map<String, int>• estoquePorTamanho;
  final Map<String, int>• estoquePorCor;
  final Map<String, dynamic>• variacoes;
  final void Function(Map<String, dynamic>) onAdd;
  final double borderRadius;
  final bool showShadow;
  final String• catalogShareUrl;
  final bool isNovo;
  final void Function(String productId)• onProductViewed;
  final bool isFavorito;
  final void Function()• onToggleFavorito;
  final String• prazoEntrega;
  final bool divideSemJuros;
  final double• jurosParcelamento;
  final int maxParcelas;
  final double percentualDescontoPix;
  /// Callback para abrir o carrinho após adicionar (usado pelo botão "Comprar")
  final void Function()• onAbrirCarrinho;
  /// Se true, exibe o selo "Últimas X" quando estoque <= 5
  final bool showStockBadge;
  /// Se true, exibe "X un." no modal de opções; se false, exibe "Disponível"
  final bool mostrarQuantidadeNoCatalogo;
  /// Layout compacto (ex.: "Vistos recentemente" com 3 cards por linha)
  final bool compact;
  /// Tamanho da imagem para cache (grid: 360x480; destaque: 600x800)
  final int• imageCacheWidth;
  final int• imageCacheHeight;
  /// Se true, produto é combo/kit: botão Ver mostra itens do kit e Comprar abre seleção de variações.
  final bool ehCombo;
  /// Itens do combo para exibir em "Ver" (Produtos do kit) e para o sheet de variações.
  final List<Map<String, dynamic>>• itensCombo;
  /// Mapa completo do produto combo (para passar ao sheet de variações). Obrigatório quando ehCombo.
  final Map<String, dynamic>• comboProductMap;
  /// Lista de todos os produtos do catálogo (para resolver variações dos itens do combo). Obrigatório quando ehCombo.
  final List<Map<String, dynamic>>• todosProdutosForCombo;
  /// Loja do catálogo (obrigatório para IA no sheet de detalhes). Contexto do catálogo, nunca admin.
  final String lojaId;
  /// Layout minimalista: card abre tela de detalhe ao toque, sem botão Ver, tipografia reduzida
  final bool minimalLayout;
  final String productCardSize;

  /// Construtor não-const para conversão defensiva num→double/int (evita TypeError em release).
  CatalogProductCard({
    super.key,
    required this.id,
    required this.name,
    required num price,
    this.priceMin,
    this.priceMax,
    this.precoPorTamanho,
    required this.imageUrl,
    required this.imagens,
    required this.descricao,
    required this.slug,
    required this.onAdd,
    num peso = 0.0,
    this.tipoEmbalagem = 'padrao',
    this.emPromocao = false,
    num• precoOriginal,
    num percentualPromo = 0.0,
    num valorPromo = 0.0,
    num quantidade = 0,
    this.estoquePorTamanho,
    this.estoquePorCor,
    this.variacoes,
    num borderRadius = 18.0,
    this.showShadow = true,
    this.catalogShareUrl,
    this.isNovo = false,
    this.onProductViewed,
    this.isFavorito = false,
    this.onToggleFavorito,
    this.prazoEntrega,
    this.divideSemJuros = false,
    num• jurosParcelamento,
    num maxParcelas = 12,
    num percentualDescontoPix = 0.0,
    this.onAbrirCarrinho,
    this.showStockBadge = false,
    this.mostrarQuantidadeNoCatalogo = false,
    this.compact = false,
    this.imageCacheWidth,
    this.imageCacheHeight,
    this.ehCombo = false,
    this.itensCombo,
    this.comboProductMap,
    this.todosProdutosForCombo,
    required this.lojaId,
    this.minimalLayout = false,
    this.productCardSize = CatalogProductCardSize.medium,
  })  : price = price.toDouble(),
        peso = peso.toDouble(),
        precoOriginal = precoOriginal?.toDouble(),
        percentualPromo = percentualPromo.toDouble(),
        valorPromo = valorPromo.toDouble(),
        quantidade = quantidade.toInt(),
        borderRadius = borderRadius.toDouble(),
        jurosParcelamento = jurosParcelamento?.toDouble(),
        maxParcelas = maxParcelas.toInt().clamp(1, 24),
        percentualDescontoPix = percentualDescontoPix.toDouble();

  @override
  State<CatalogProductCard> createState() => _CatalogProductCardState();
}

class _CatalogProductCardState extends State<CatalogProductCard> {
  bool _hovered = false;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  /// Quando tem variação com preços, card mostra o menor e o maior cadastrado (ex.: R$ 50,00 a R$ 100,00)
  bool get _temFaixaPreco =>
      widget.priceMin != null &&
      widget.priceMax != null &&
      (widget.priceMin! - widget.priceMax!).abs() > 0.001;

  /// Calcula parcela com juros (PMT): valor * (i * (1+i)^n) / ((1+i)^n - 1)
  double _parcelaComJuros(double valor, double taxaMensalPct, int n) {
    if (n <= 0 || taxaMensalPct <= 0) return valor / n;
    final i = taxaMensalPct / 100;
    var p = 1.0;
    for (var k = 0; k < n; k++) {
      p *= (1 + i);
    }
    return valor * (i * p) / (p - 1);
  }

  double get _precoParaParcelamento =>
      _temFaixaPreco • (widget.priceMin ?• widget.price) : widget.price;

  String _buildParcelamentoTexto() {
    final p = _precoParaParcelamento;
    final n = widget.maxParcelas.clamp(1, 24);
    final prefix = _temFaixaPreco • 'A partir de ' : '';
    if (widget.divideSemJuros) {
      return '$prefix${n}x R\$ ${_fmt2(p / n)} sem juros';
    }
    final juros = widget.jurosParcelamento;
    if (juros != null && juros > 0) {
      final parcela = _parcelaComJuros(p, juros, n);
      return '$prefix${n}x R\$ ${_fmt2(parcela)}';
    }
    return '${prefix}ou em até ${n}x de R\$ ${_fmt2(p / n)}';
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _compartilharProduto() async {
    final url = widget.catalogShareUrl ?• '';
    if (url.isEmpty) return;
    final precoTexto = (widget.priceMin != null &&
            widget.priceMax != null &&
            (widget.priceMin! - widget.priceMax!).abs() > 0.001)
        • 'R\$ ${_fmt2(widget.priceMin!)} a R\$ ${_fmt2(widget.priceMax!)}'
        : 'R\$ ${_fmt2(widget.price)}';
    final descricaoCurta = widget.descricao.trim().isEmpty
        • null
        : (widget.descricao.length > 120
            • '${widget.descricao.substring(0, 117)}…'
            : widget.descricao);
    final msg = CatalogShareService.buildProductShareMessage(
      nome: widget.name,
      precoTexto: precoTexto,
      descricaoCurta: descricaoCurta,
      url: url,
    );
    final uri = Uri.parse(
      'https://wa.me/?text=${CatalogShareService.encodeForWhatsApp(msg)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openGallery() {
    if (widget.imagens.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: CatalogGalleryView(imagens: widget.imagens, index: 0),
      ),
    );
  }

  void _openDetails() {
    widget.onProductViewed?.call(widget.id);
    if (widget.minimalLayout) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CatalogProductDetailScreen(
            id: widget.id,
            name: widget.name,
            descricao: widget.descricao,
            slug: widget.slug,
            peso: widget.peso,
            tipoEmbalagem: widget.tipoEmbalagem,
            price: widget.price,
            priceMin: widget.priceMin,
            priceMax: widget.priceMax,
            precoPorTamanho: widget.precoPorTamanho,
            precoOriginal: widget.precoOriginal,
            emPromocao: widget.emPromocao,
            percentualPromo: widget.percentualPromo,
            valorPromo: widget.valorPromo,
            imagens: widget.imagens.isNotEmpty • widget.imagens : [widget.imageUrl],
            quantidade: widget.quantidade,
            estoquePorTamanho: widget.estoquePorTamanho,
            estoquePorCor: widget.estoquePorCor,
            variacoes: widget.variacoes,
            prazoEntrega: widget.prazoEntrega,
            percentualDescontoPix: widget.percentualDescontoPix,
            divideSemJuros: widget.divideSemJuros,
            maxParcelas: widget.maxParcelas,
            catalogShareUrl: widget.catalogShareUrl,
            lojaId: widget.lojaId,
            ehCombo: widget.ehCombo,
            itensCombo: widget.itensCombo,
            comboProductMap: widget.comboProductMap,
            todosProdutosForCombo: widget.todosProdutosForCombo,
            onAdd: widget.onAdd,
            onAbrirCarrinho: widget.onAbrirCarrinho,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CatalogProductDetailsSheet(
            name: widget.name,
            descricao: widget.descricao,
            price: widget.price,
            priceMin: widget.priceMin,
            priceMax: widget.priceMax,
            precoOriginal: widget.precoOriginal,
            emPromocao: widget.emPromocao,
            percentualPromo: widget.percentualPromo,
            valorPromo: widget.valorPromo,
            imagens: widget.imagens.isNotEmpty • widget.imagens : [widget.imageUrl],
            quantidade: widget.quantidade,
            estoquePorTamanho: widget.estoquePorTamanho,
            estoquePorCor: widget.estoquePorCor,
            variacoes: widget.variacoes,
            catalogShareUrl: widget.catalogShareUrl,
            prazoEntrega: widget.prazoEntrega,
            percentualDescontoPix: widget.percentualDescontoPix,
            itensCombo: widget.itensCombo,
            lojaId: widget.lojaId,
          ),
      );
    }
  }

  void _openComboVariationSheet({bool abrirCarrinhoDepois = false}) {
    if (widget.comboProductMap == null || widget.todosProdutosForCombo == null) return;
    widget.onProductViewed?.call(widget.id);
    showCatalogComboVariationSheet(
      context: context,
      comboProduct: widget.comboProductMap!,
      todosProdutos: widget.todosProdutosForCombo!,
      onAdd: widget.onAdd,
      onAbrirCarrinho: abrirCarrinhoDepois • widget.onAbrirCarrinho : null,
    );
  }

  void _openSelectionModal({bool comprarDirecto = false}) {
    widget.onProductViewed?.call(widget.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CatalogProductSelectionSheet(
        name: widget.name,
        price: widget.price,
        precoPorTamanho: widget.precoPorTamanho,
        precoOriginal: widget.precoOriginal,
        emPromocao: widget.emPromocao,
        imageUrl: widget.imagens.isNotEmpty • widget.imagens.first : widget.imageUrl,
        estoquePorTamanho: widget.estoquePorTamanho ?• {},
        estoquePorCor: widget.estoquePorCor ?• {},
        variacoes: widget.variacoes,
        percentualDescontoPix: widget.percentualDescontoPix,
        mostrarQuantidadeNoCatalogo: widget.mostrarQuantidadeNoCatalogo,
        onAddToCart: (tamanho, cor, preco) {
          final img = widget.imagens.isNotEmpty
              • widget.imagens.first
              : widget.imageUrl;

          final itemParaCarrinho = {
            'produtosId': widget.id,
            'id': widget.id,
            'nome': widget.name,
            'preco': preco,
            'percentualDescontoPix': widget.percentualDescontoPix,
            'divideSemJuros': widget.divideSemJuros,
            'maxParcelasSemJuros': widget.maxParcelas,
            'quantidade': 1,
            'imageUrl': img,
            'url_foto': img,
            'slug': widget.slug,
            'peso': widget.peso,
            'tipoEmbalagem': widget.tipoEmbalagem,
            'tamanho': tamanho ?• '',
            'cor': cor ?• '',
          };

          widget.onAdd(itemParaCarrinho);
          Navigator.of(context).pop();
          if (comprarDirecto && widget.onAbrirCarrinho != null) {
            widget.onAbrirCarrinho!();
          }
        },
      ),
    );
  }

  void _comprarDirecto() {
    if (widget.ehCombo) {
      _openComboVariationSheet(abrirCarrinhoDepois: true);
      return;
    }
    final hasTamanhos = (widget.estoquePorTamanho != null && widget.estoquePorTamanho!.isNotEmpty) ||
        (widget.variacoes != null && widget.variacoes!.isNotEmpty);
    final hasCores = (widget.estoquePorCor != null && widget.estoquePorCor!.isNotEmpty) ||
        (widget.variacoes != null && widget.variacoes!.isNotEmpty);
    final hasVariacoes = widget.variacoes != null && widget.variacoes!.isNotEmpty;

    if (hasTamanhos || hasCores || hasVariacoes) {
      _openSelectionModal(comprarDirecto: true);
    } else {
      final img = widget.imagens.isNotEmpty • widget.imagens.first : widget.imageUrl;
      widget.onAdd({
        'produtosId': widget.id,
        'id': widget.id,
        'nome': widget.name,
        'preco': widget.price,
        'percentualDescontoPix': widget.percentualDescontoPix,
        'divideSemJuros': widget.divideSemJuros,
        'maxParcelasSemJuros': widget.maxParcelas,
        'quantidade': 1,
        'imageUrl': img,
        'url_foto': img,
        'slug': widget.slug,
        'peso': widget.peso,
        'tipoEmbalagem': widget.tipoEmbalagem,
        'tamanho': '',
        'cor': '',
      });
      widget.onAbrirCarrinho?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasImg = widget.imagens.isNotEmpty || widget.imageUrl.isNotEmpty;

    final cardColor = theme.cardColor;
    final borderColor = Colors.white.withValues(alpha:0.06);
    final catalogExt = theme.extension<CatalogThemeExtension>();
    final productNameColor =
        catalogExt?.productNameColor ?• theme.textTheme.bodyMedium?.color ?• Colors.white;
    final productPriceColor =
        catalogExt?.productPriceColor ?• theme.colorScheme.primary;

    final normalizedCardSize =
        CatalogProductCardSize.normalize(widget.productCardSize);
    final screenW = MediaQuery.of(context).size.width;
    final is360 = screenW <= 360;
    final is390 = screenW > 360 && screenW <= 390;
    final is412 = screenW > 390 && screenW <= 412;
    final isSmallCard = normalizedCardSize == CatalogProductCardSize.small;
    final isLargeCard = normalizedCardSize == CatalogProductCardSize.large;
    // Dois Expanded na Column (imagem + rodapé): só assim o flex altera a fração
    // real da altura — um único Expanded recebe 100% do espaço restante e ignora flex.
    final int imageFlex;
    final int contentFlex;
    if (widget.compact) {
      if (isSmallCard) {
        imageFlex = 7;
        contentFlex = 15;
      } else if (isLargeCard) {
        imageFlex = 13;
        contentFlex = 9;
      } else {
        imageFlex = 10;
        contentFlex = 12;
      }
    } else {
      if (isSmallCard) {
        imageFlex = 10;
        contentFlex = 18;
      } else if (isLargeCard) {
        imageFlex = 22;
        contentFlex = 10;
      } else {
        imageFlex = 15;
        contentFlex = 14;
      }
    }
    final titleSizeBase = widget.minimalLayout
        • (isLargeCard • 14.0 : (isSmallCard • 12.0 : 13.0))
        : (widget.compact • (isLargeCard • 13.0 : 12.0) : (isLargeCard • 16.0 : 15.0));
    final priceSizeBase = widget.minimalLayout
        • (isLargeCard • 13.0 : 12.0)
        : (widget.compact • (isLargeCard • 12.0 : 11.0) : (isLargeCard • 15.0 : 14.0));
    final actionHeightBase = widget.minimalLayout
        • (isLargeCard • 38.0 : (isSmallCard • 32.0 : 34.0))
        : (widget.compact • 32.0 : (isLargeCard • 42.0 : 40.0));
    final titleSize = is360
        • (titleSizeBase - 0.8)
        : is390
            • (titleSizeBase - 0.5)
            : is412
                • (titleSizeBase - 0.2)
                : titleSizeBase;
    final priceSize = is360
        • (priceSizeBase - 0.5)
        : is390
            • (priceSizeBase - 0.3)
            : priceSizeBase;
    final actionHeight = is360
        • (actionHeightBase - 1.0)
        : actionHeightBase;
    final contentVPad = widget.compact
        • (is360 • 5.0 : 6.0)
        : (is360 • 7.0 : 8.0);
    final spacingAfterTitle = widget.compact • (is360 • 1.0 : 2.0) : 4.0;

    return MouseRegion(
      onEnter: (_) {
        if (!kIsWeb) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!kIsWeb) return;
        setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        clipBehavior: Clip.antiAlias,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: (!kIsWeb && _hovered)
            • (Matrix4.identity()..scaleByVector3(Vector3(1.02, 1.02, 1.0)))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _hovered
                • theme.colorScheme.primary.withValues(alpha:0.35)
                : borderColor,
          ),
          boxShadow: widget.showShadow
              • (_hovered
                  • [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha:0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ])
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: imageFlex,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(widget.borderRadius),
                  topRight: Radius.circular(widget.borderRadius),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.minimalLayout • _openDetails : _openGallery,
                      child: Container(
                        color: cardColor,
                        width: double.infinity,
                        height: double.infinity,
                        child: CatalogImagePlaceholder(
                          url: hasImg
                              • (widget.imagens.isNotEmpty
                                  • widget.imagens.first
                                  : widget.imageUrl)
                              : '',
                          radius: BorderRadius.zero,
                          fit: BoxFit.cover,
                          cacheWidth: widget.imageCacheWidth ?• (kIsWeb • 600 : 500),
                          cacheHeight: widget.imageCacheHeight ?• (kIsWeb • 800 : 667),
                        ),
                      ),
                    ),
                    if ((widget.catalogShareUrl != null && widget.catalogShareUrl!.isNotEmpty) ||
                        widget.emPromocao ||
                        (widget.isNovo && !widget.emPromocao) ||
                        widget.ehCombo)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.catalogShareUrl != null &&
                                widget.catalogShareUrl!.isNotEmpty)
                              Material(
                                color: Colors.white.withValues(alpha:0.9),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: _compartilharProduto,
                                  customBorder: const CircleBorder(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.share_outlined, size: 18, color: Colors.black87),
                                  ),
                                ),
                              ),
                            if (widget.catalogShareUrl != null &&
                                widget.catalogShareUrl!.isNotEmpty &&
                                (widget.emPromocao || widget.isNovo || widget.ehCombo))
                              const SizedBox(width: 6),
                            if (widget.ehCombo)
                              _buildBadge('Kit', Colors.orange[700]!),
                            if (widget.ehCombo && (widget.emPromocao || widget.isNovo))
                              const SizedBox(width: 6),
                            if (widget.emPromocao)
                              _buildBadge(
                                widget.percentualPromo > 0
                                    • '-${widget.percentualPromo.toStringAsFixed(0)}%'
                                    : '-R\$ ${widget.valorPromo.toStringAsFixed(2).replaceAll('.', ',')}',
                                Colors.red[700]!,
                              ),
                            if (widget.isNovo && !widget.emPromocao)
                              _buildBadge('Novo', Colors.green[700]!),
                          ],
                        ),
                      ),
                    if (widget.showStockBadge && widget.quantidade > 0 && widget.quantidade <= 5)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: _buildBadge(
                          'Últimas ${widget.quantidade}',
                          Colors.orange[700]!,
                        ),
                      ),
                    if (widget.onToggleFavorito != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.white.withValues(alpha:0.9),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: widget.onToggleFavorito,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                widget.isFavorito • Icons.favorite : Icons.favorite_border,
                                color: widget.isFavorito • Colors.red : Colors.grey[700],
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: contentFlex,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact • 4 : 10,
                  vertical: contentVPad,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                  GestureDetector(
                    onTap: widget.minimalLayout • _openDetails : null,
                    behavior: widget.minimalLayout • HitTestBehavior.opaque : HitTestBehavior.deferToChild,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                              widget.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: widget.minimalLayout • FontWeight.w500 : FontWeight.w600,
                                fontSize: titleSize,
                                color: productNameColor,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: spacingAfterTitle),
                            if (_temFaixaPreco)
                              Text(
                                'R\$ ${_fmt2(widget.priceMin!)} a R\$ ${_fmt2(widget.priceMax!)}',
                                style: TextStyle(
                                  color: widget.emPromocao • Colors.red[700] : productPriceColor,
                                  fontSize: priceSize,
                                  fontWeight: widget.minimalLayout • FontWeight.w600 : FontWeight.w700,
                                ),
                              )
                            else if (widget.emPromocao && widget.precoOriginal != null)
                              Row(
                                children: [
                                  Text(
                                    'R\$ ${_fmt2(widget.precoOriginal!)}',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: widget.minimalLayout • 10 : (widget.compact • 9 : 10),
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  SizedBox(width: widget.compact • 2 : 4),
                                  Text(
                                    'R\$ ${_fmt2(widget.price)}',
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontSize: priceSize,
                                      fontWeight: widget.minimalLayout • FontWeight.w600 : FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'R\$ ${_fmt2(widget.price)}',
                                style: TextStyle(
                                  color: productPriceColor,
                                  fontSize: priceSize,
                                  fontWeight: widget.minimalLayout • FontWeight.w600 : FontWeight.w700,
                                ),
                              ),
                            Text(
                              _buildParcelamentoTexto(),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: widget.minimalLayout • 10 : (widget.compact • 7 : 8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.percentualDescontoPix > 0)
                              Text(
                                'R\$ ${_fmt2(_precoParaParcelamento * (1 - widget.percentualDescontoPix / 100))} - PIX ${widget.percentualDescontoPix == widget.percentualDescontoPix.truncateToDouble() • widget.percentualDescontoPix.toInt() : _fmt2(widget.percentualDescontoPix)}% off',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: widget.minimalLayout • 10 : (widget.compact • 7 : 8),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        ],
                      ),
                    ),
                    SizedBox(height: widget.compact • 3 : 5),
                    Row(
                      children: [
                        if (!widget.minimalLayout)
                          Expanded(
                            child: SizedBox(
                              height: widget.compact • 32 : 40,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: catalogExt?.buttonVerText ?• theme.colorScheme.primary,
                                  side: BorderSide(color: (catalogExt?.buttonVerText ?• theme.colorScheme.primary).withValues(alpha:0.7)),
                                  padding: EdgeInsets.symmetric(horizontal: widget.compact • 4 : 8),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(widget.compact • 6 : 8),
                                  ),
                                ),
                                onPressed: _openDetails,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: widget.compact • 14 : 17,
                                        color: catalogExt?.buttonVerText ?• theme.colorScheme.primary,
                                      ),
                                      if (!widget.compact) const SizedBox(width: 4),
                                      Text(
                                        'Ver',
                                        style: TextStyle(
                                          fontSize: widget.compact • 11 : 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (!widget.minimalLayout) SizedBox(width: widget.compact • 4 : 8),
                        Expanded(
                          child: SizedBox(
                            height: actionHeight,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: catalogExt?.buttonComprarBg ?• theme.colorScheme.primary,
                                foregroundColor: catalogExt?.buttonComprarText ?• Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: widget.minimalLayout • 6 : (widget.compact • 4 : 8)),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(widget.minimalLayout • 8 : (widget.compact • 6 : 8)),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () {
                                if (widget.ehCombo) {
                                  _openComboVariationSheet(abrirCarrinhoDepois: false);
                                  return;
                                }
                                final hasTamanhos = (widget.estoquePorTamanho != null && widget.estoquePorTamanho!.isNotEmpty) ||
                                    (widget.variacoes != null && widget.variacoes!.isNotEmpty);
                                final hasCores = (widget.estoquePorCor != null && widget.estoquePorCor!.isNotEmpty) ||
                                    (widget.variacoes != null && widget.variacoes!.isNotEmpty);
                                final hasVariacoes = widget.variacoes != null && widget.variacoes!.isNotEmpty;
                                if (hasTamanhos || hasCores || hasVariacoes) {
                                  _openSelectionModal();
                                } else {
                                  final img = widget.imagens.isNotEmpty • widget.imagens.first : widget.imageUrl;
                                  widget.onAdd({
                                    'produtosId': widget.id, 'id': widget.id, 'nome': widget.name, 'preco': widget.price,
                                    'percentualDescontoPix': widget.percentualDescontoPix, 'quantidade': 1,
                                    'imageUrl': img, 'url_foto': img, 'slug': widget.slug, 'peso': widget.peso,
                                    'tipoEmbalagem': widget.tipoEmbalagem, 'tamanho': '', 'cor': '',
                                  });
                                }
                              },
                              child: Icon(
                                Icons.shopping_cart_outlined,
                                size: widget.minimalLayout • 18 : (widget.compact • 18 : 22),
                                color: catalogExt?.buttonComprarText ?• Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onAbrirCarrinho != null && !widget.minimalLayout) ...[
                      SizedBox(height: widget.compact • 3 : 4),
                      SizedBox(
                        width: double.infinity,
                        height: widget.compact • 34 : 40,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: catalogExt?.buttonComprarBg ?• theme.colorScheme.primary,
                            foregroundColor: catalogExt?.buttonComprarText ?• Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(widget.compact • 6 : 8),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _comprarDirecto,
                          child: Text(
                            'Comprar',
                            style: TextStyle(
                              fontSize: widget.compact • 12 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


