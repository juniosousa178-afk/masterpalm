// lib/screens/public_catalog/widgets/catalog_product_detail_screen.dart
// Tela de detalhes do produto para layout minimalista – full screen, visual clean.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/produto_variacao_extra.dart';
import '../../../services/catalog_share_service.dart';
import '../../../services/ai_loja_service.dart';
import '../../../services/ia_uso_limite_service.dart';
import '../../../utils/image_provider.dart';
import '../../../utils/platform_adaptive.dart';
import '../../../utils/safe_parse.dart';
import 'catalog_product_selection_sheet.dart';
import 'catalog_combo_variation_sheet.dart';

Map<String, int> _estoqueMapForDetail(Map<String, dynamic> raw) {
  final result = <String, int>{};
  raw.forEach((k, v) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n != null && n > 0) result[k.toString()] = n;
  });
  return result;
}

/// Tela full-screen de detalhes do produto para layout minimalista.
/// Prioriza galeria, nome, preço, descrição e botão "Adicionar ao carrinho".
class CatalogProductDetailScreen extends StatelessWidget {
  final String id;
  final String name;
  final String descricao;
  final String slug;
  final num peso;
  final String tipoEmbalagem;
  final double price;
  final double? priceMin;
  final double? priceMax;
  final Map<String, double>? precoPorTamanho;
  final double? precoOriginal;
  final bool emPromocao;
  final double percentualPromo;
  final double valorPromo;
  final List<String> imagens;
  final int quantidade;
  final Map<String, int>? estoquePorTamanho;
  final Map<String, int>? estoquePorCor;
  final Map<String, dynamic>? variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final String? prazoEntrega;
  final double percentualDescontoPix;
  final bool divideSemJuros;
  final int maxParcelas;
  final String? catalogShareUrl;
  final String lojaId;
  final bool ehCombo;
  final List<Map<String, dynamic>>? itensCombo;
  final Map<String, dynamic>? comboProductMap;
  final List<Map<String, dynamic>>? todosProdutosForCombo;
  final String? nomeLoja;
  final String? contatoWhatsapp;
  final String? politicaFrete;
  final bool Function(Map<String, dynamic>) onAdd;
  final VoidCallback? onAbrirCarrinho;
  final String? initialCatalogExtraValor;
  final void Function(String? value)? onCatalogVariacaoExtraChanged;

  const CatalogProductDetailScreen({
    super.key,
    required this.id,
    required this.name,
    required this.descricao,
    this.slug = '',
    this.peso = 0,
    this.tipoEmbalagem = 'padrao',
    required this.price,
    this.priceMin,
    this.priceMax,
    this.precoPorTamanho,
    this.precoOriginal,
    required this.emPromocao,
    required this.percentualPromo,
    required this.valorPromo,
    required this.imagens,
    required this.quantidade,
    this.estoquePorTamanho,
    this.estoquePorCor,
    this.variacoes,
    this.variacoesExtraTipo,
    this.prazoEntrega,
    this.percentualDescontoPix = 0.0,
    this.divideSemJuros = false,
    this.maxParcelas = 12,
    this.catalogShareUrl,
    required this.lojaId,
    this.ehCombo = false,
    this.itensCombo,
    this.comboProductMap,
    this.todosProdutosForCombo,
    this.nomeLoja,
    this.contatoWhatsapp,
    this.politicaFrete,
    required this.onAdd,
    this.onAbrirCarrinho,
    this.initialCatalogExtraValor,
    this.onCatalogVariacaoExtraChanged,
  });

  /// Abre a mesma tela a partir do mapa de produto do catálogo (mesma origem do [PublicCatalogProductCard]).
  factory CatalogProductDetailScreen.fromProdutoMap({
    required Map<String, dynamic> p,
    required String lojaId,
    required bool Function(Map<String, dynamic>) onAdd,
    VoidCallback? onAbrirCarrinho,
    String? catalogShareUrl,
    String? nomeLoja,
    String? contatoWhatsapp,
    String? politicaFrete,
    String? prazoEntregaTexto,
    List<Map<String, dynamic>>? todosProdutos,
    String? initialCatalogExtraValor,
    void Function(String? value)? onCatalogVariacaoExtraChanged,
  }) {
    final estoqueTam = _estoqueMapForDetail(asMap(p['estoquePorTamanho']));
    final estoqueCor = _estoqueMapForDetail(asMap(p['estoquePorCor']));
    final price = safeDouble(p['preco']);
    final priceMin = p['priceMin'] != null ? safeDouble(p['priceMin']) : null;
    final priceMax = p['priceMax'] != null ? safeDouble(p['priceMax']) : null;
    final precoPorTamanho = (p['precoPorTamanho'] != null && p['precoPorTamanho'] is Map)
        ? Map<String, double>.from(
            (p['precoPorTamanho'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v is num) ? v.toDouble() : 0.0),
            ),
          )
        : null;
    final tipoProduto = (p['tipoProduto'] ?? p['tipo'] ?? 'simples').toString();
    final itensComboRaw = p['itensCombo'];
    List<Map<String, dynamic>>? itensCombo;
    if (itensComboRaw is List && itensComboRaw.isNotEmpty) {
      itensCombo = [];
      for (final e in itensComboRaw) {
        if (e is! Map) continue;
        itensCombo.add(
          Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
      if (itensCombo.isEmpty) itensCombo = null;
    }
    final ehCombo = tipoProduto == 'combo' ||
        (itensCombo != null && itensCombo.isNotEmpty);
    final maxPar = safeBool(p['divideSemJuros'])
        ? safeInt(p['maxParcelasSemJuros'], 12).clamp(1, 24)
        : 12;

    return CatalogProductDetailScreen(
      id: safeStr(p['id'], ''),
      name: safeStr(p['nome'], 'Produto'),
      descricao: safeStr(p['descricao']),
      slug: safeStr(p['slug']),
      peso: safeDouble(p['peso']),
      tipoEmbalagem: safeStr(p['tipoEmbalagem'], 'padrao'),
      price: price,
      priceMin: priceMin,
      priceMax: priceMax,
      precoPorTamanho: precoPorTamanho,
      precoOriginal:
          (p['emPromocao'] == true) ? safeDouble(p['precoFinal']) : null,
      emPromocao: safeBool(p['emPromocao']),
      percentualPromo: safeDouble(p['percentualPromo']),
      valorPromo: safeDouble(p['valorPromo']),
      imagens: safeListString(p['imagens']).isNotEmpty
          ? safeListString(p['imagens'])
          : [safeStr(p['imageUrl'])],
      quantidade: safeInt(p['quantidade']),
      estoquePorTamanho: estoqueTam.isNotEmpty ? estoqueTam : null,
      estoquePorCor: estoqueCor.isNotEmpty ? estoqueCor : null,
      variacoes: (p['variacoes'] != null && asMapDeep(p['variacoes']).isNotEmpty)
          ? asMapDeep(p['variacoes'])
          : null,
      variacoesExtraTipo: (p['variacoesExtraTipo'] != null &&
              asMapDeep(p['variacoesExtraTipo']).isNotEmpty)
          ? asMapDeep(p['variacoesExtraTipo'])
          : null,
      prazoEntrega: prazoEntregaTexto,
      percentualDescontoPix: safeDouble(p['percentualDescontoPix']),
      divideSemJuros: safeBool(p['divideSemJuros']),
      maxParcelas: maxPar,
      catalogShareUrl: catalogShareUrl,
      lojaId: lojaId,
      ehCombo: ehCombo,
      itensCombo: itensCombo,
      comboProductMap: ehCombo ? p : null,
      todosProdutosForCombo: ehCombo ? (todosProdutos ?? []) : null,
      nomeLoja: nomeLoja,
      contatoWhatsapp: contatoWhatsapp,
      politicaFrete: politicaFrete,
      onAdd: onAdd,
      onAbrirCarrinho: onAbrirCarrinho,
      initialCatalogExtraValor: initialCatalogExtraValor,
      onCatalogVariacaoExtraChanged: onCatalogVariacaoExtraChanged,
    );
  }

  bool get _temFaixaPreco =>
      priceMin != null &&
      priceMax != null &&
      (priceMin! - priceMax!).abs() > 0.001;

  String _fmt2(num v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');

  void _openFullscreenGallery(BuildContext context, int initialIndex) {
    if (imagens.isEmpty || imagens.every((e) => e.trim().isEmpty)) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CatalogFullscreenGallery(
          images: imagens.where((e) => e.trim().isNotEmpty).toList(),
          initialIndex: initialIndex,
          heroPrefix: id,
        ),
      ),
    );
  }

  void _addToCart(BuildContext context) {
    if (ehCombo && comboProductMap != null && todosProdutosForCombo != null) {
      showCatalogComboVariationSheet(
        context: context,
        comboProduct: comboProductMap!,
        todosProdutos: todosProdutosForCombo!,
        onAdd: onAdd,
        onAbrirCarrinho: () {
          Navigator.of(context).pop();
          onAbrirCarrinho?.call();
        },
      );
      return;
    }
    final hasVariacoes = (estoquePorTamanho != null && estoquePorTamanho!.isNotEmpty) ||
        (estoquePorCor != null && estoquePorCor!.isNotEmpty) ||
        (variacoes != null && variacoes!.isNotEmpty);
    if (hasVariacoes) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CatalogProductSelectionSheet(
          name: name,
          price: price,
          precoPorTamanho: precoPorTamanho,
          precoOriginal: precoOriginal,
          emPromocao: emPromocao,
          imageUrl: imagens.isNotEmpty ? imagens.first : '',
          estoquePorTamanho: estoquePorTamanho ?? {},
          estoquePorCor: estoquePorCor ?? {},
          variacoes: variacoes,
          variacoesExtraTipo: variacoesExtraTipo,
          initialExtraValor: initialCatalogExtraValor,
          onCatalogVariacaoExtraChanged: onCatalogVariacaoExtraChanged,
          percentualDescontoPix: percentualDescontoPix,
          mostrarQuantidadeNoCatalogo: false,
          onAddToCart: (tamanho, cor, preco, extraValor, extraTipo) {
            final img = imagens.isNotEmpty ? imagens.first : '';
            final ex = extraValor.trim();
            final resumoExtra = ex.isNotEmpty
                ? ProdutoVariacaoExtra.textoResumoExtra(
                    extraTipo: extraTipo,
                    extraValor: ex,
                  )
                : '';
            onAdd({
              'produtosId': id,
              'id': id,
              'nome': name,
              'preco': preco,
              'percentualDescontoPix': percentualDescontoPix,
              'divideSemJuros': divideSemJuros,
              'maxParcelasSemJuros': maxParcelas,
              'quantidade': 1,
              'imageUrl': img,
              'url_foto': img,
              'slug': slug,
              'peso': peso,
              'tipoEmbalagem': tipoEmbalagem,
              'tamanho': tamanho ?? '',
              'cor': cor ?? '',
              if (ex.isNotEmpty) 'extraValor': ex,
              if (extraTipo.trim().isNotEmpty) 'extraTipo': extraTipo.trim(),
              if (resumoExtra.isNotEmpty) 'variacaoExtraResumo': resumoExtra,
            });
            Navigator.of(context).pop();
            Navigator.of(context).pop();
            onAbrirCarrinho?.call();
          },
        ),
      );
    } else {
      final img = imagens.isNotEmpty ? imagens.first : '';
      onAdd({
        'produtosId': id,
        'id': id,
        'nome': name,
        'preco': price,
        'percentualDescontoPix': percentualDescontoPix,
        'divideSemJuros': divideSemJuros,
        'maxParcelasSemJuros': maxParcelas,
        'quantidade': 1,
        'imageUrl': img,
        'url_foto': img,
        'slug': slug,
        'peso': peso,
        'tipoEmbalagem': tipoEmbalagem,
        'tamanho': '',
        'cor': '',
      });
      Navigator.of(context).pop();
      onAbrirCarrinho?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final galleryHeight = MediaQuery.of(context).size.width < 420 ? 300.0 : 340.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.cardColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        actions: [
          if (catalogShareUrl != null && catalogShareUrl!.isNotEmpty)
            IconButton(
              onPressed: () async {
                final precoTexto = _temFaixaPreco
                    ? 'R\$ ${_fmt2(priceMin!)} a R\$ ${_fmt2(priceMax!)}'
                    : 'R\$ ${_fmt2(price)}';
                final msg = CatalogShareService.buildProductShareMessage(
                  nome: name,
                  precoTexto: precoTexto,
                  descricaoCurta: descricao.trim().isEmpty ? null : descricao,
                  url: catalogShareUrl!,
                );
                final uri = Uri.parse(
                  'https://wa.me/?text=${CatalogShareService.encodeForWhatsApp(msg)}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.share_outlined, size: 22),
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Galeria
            SizedBox(
              height: galleryHeight,
              child: _CatalogInlineGallery(
                productId: id,
                imagens: imagens,
                cardColor: theme.cardColor,
                onOpenFullscreen: _openFullscreenGallery,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_temFaixaPreco)
                    Text(
                      'R\$ ${_fmt2(priceMin!)} a R\$ ${_fmt2(priceMax!)}',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (emPromocao && precoOriginal != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'R\$ ${_fmt2(precoOriginal!)}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'R\$ ${_fmt2(price)}',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (percentualPromo > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red[700],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '-${percentualPromo.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Text(
                      'R\$ ${_fmt2(price)}',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (percentualDescontoPix > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.pix, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          'ou R\$ ${_fmt2(price * (1 - percentualDescontoPix / 100))} no PIX (${percentualDescontoPix == percentualDescontoPix.truncateToDouble() ? percentualDescontoPix.toInt() : _fmt2(percentualDescontoPix)}% off)',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (prazoEntrega != null && prazoEntrega!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Entrega: $prazoEntrega',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Descrição',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    descricao.trim().isEmpty
                        ? 'Sem descrição disponível para este produto.'
                        : descricao,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      height: 1.5,
                      fontStyle: descricao.trim().isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: quantidade > 0 ? () => _addToCart(context) : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        quantidade > 0 ? 'Adicionar ao carrinho' : 'Indisponível',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _abrirDuvidasPergunte(context),
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('Dúvidas? Pergunte'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDuvidasPergunte(BuildContext context) {
    final perguntaCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => _DuvidasPergunteDialogDetail(
        produtoNome: name,
        temEstoque: quantidade > 0,
        nomeLoja: nomeLoja,
        contatoWhatsapp: contatoWhatsapp,
        politicaFrete: politicaFrete,
        perguntaCtrl: perguntaCtrl,
        lojaId: lojaId,
      ),
    );
  }
}

/// Galeria inline: em telas estreitas (mobile/APK, web mobile) o foco é deslizar;
/// em telas largas (desktop web, tablet) mostra setas para o mesmo fluxo com mouse.
class _CatalogInlineGallery extends StatefulWidget {
  final String productId;
  final List<String> imagens;
  final Color cardColor;
  final void Function(BuildContext context, int initialIndex) onOpenFullscreen;

  const _CatalogInlineGallery({
    required this.productId,
    required this.imagens,
    required this.cardColor,
    required this.onOpenFullscreen,
  });

  @override
  State<_CatalogInlineGallery> createState() => _CatalogInlineGalleryState();
}

class _CatalogInlineGalleryState extends State<_CatalogInlineGallery> {
  late final PageController _pageController;
  late final List<String> _imgs;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _imgs = widget.imagens.where((e) => e.trim().isNotEmpty).toList();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _go(int delta) {
    if (_imgs.length <= 1) return;
    final next = (_index + delta).clamp(0, _imgs.length - 1);
    if (next == _index) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_imgs.isEmpty) {
      return Container(
        color: widget.cardColor,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 64,
          color: Colors.grey[400],
        ),
      );
    }

    final showArrows =
        showGalleryArrowNavigation(context) && _imgs.length > 1;
    final hint = showArrows
        ? 'Toque para ampliar'
        : 'Deslize para ver mais · toque para ampliar';

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: _imgs.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => widget.onOpenFullscreen(context, i),
            child: Hero(
              tag: 'catalog_detail_img_${widget.productId}_$i',
              child: Image(
                image: mpImageProvider(_imgs[i]),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        if (showArrows) ...[
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Material(
                color: Colors.black26,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.chevron_left),
                  color: Colors.white,
                  onPressed: _index > 0 ? () => _go(-1) : null,
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Material(
                color: Colors.black26,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.chevron_right),
                  color: Colors.white,
                  onPressed: _index < _imgs.length - 1 ? () => _go(1) : null,
                ),
              ),
            ),
          ),
        ],
        if (_imgs.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.38),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hint,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CatalogFullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String heroPrefix;

  const _CatalogFullscreenGallery({
    required this.images,
    required this.initialIndex,
    required this.heroPrefix,
  });

  @override
  State<_CatalogFullscreenGallery> createState() =>
      _CatalogFullscreenGalleryState();
}

class _CatalogFullscreenGalleryState extends State<_CatalogFullscreenGallery> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _go(int delta) {
    if (widget.images.length <= 1) return;
    final next = (_index + delta).clamp(0, widget.images.length - 1);
    if (next == _index) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showArrows =
        showGalleryArrowNavigation(context) && widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1}/${widget.images.length}'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: 'catalog_detail_img_${widget.heroPrefix}_$i',
                    child: Image(
                      image: mpImageProvider(widget.images[i]),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
          ),
          if (showArrows) ...[
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  iconSize: 40,
                  color: Colors.white70,
                  onPressed: _index > 0 ? () => _go(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  iconSize: 40,
                  color: Colors.white70,
                  onPressed:
                      _index < widget.images.length - 1 ? () => _go(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DuvidasPergunteDialogDetail extends StatefulWidget {
  final String produtoNome;
  final bool temEstoque;
  final String? nomeLoja;
  final String? contatoWhatsapp;
  final String? politicaFrete;
  final TextEditingController perguntaCtrl;
  final String lojaId;

  const _DuvidasPergunteDialogDetail({
    required this.produtoNome,
    required this.temEstoque,
    this.nomeLoja,
    this.contatoWhatsapp,
    this.politicaFrete,
    required this.perguntaCtrl,
    required this.lojaId,
  });

  @override
  State<_DuvidasPergunteDialogDetail> createState() =>
      _DuvidasPergunteDialogDetailState();
}

class _DuvidasPergunteDialogDetailState
    extends State<_DuvidasPergunteDialogDetail> {
  bool _enviando = false;
  String? _resposta;

  Future<void> _enviar() async {
    final pergunta = widget.perguntaCtrl.text.trim();
    if (pergunta.isEmpty || _enviando) return;
    final lojaId = widget.lojaId;
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }
    setState(() {
      _enviando = true;
      _resposta = null;
    });
    try {
      final contexto = <String, dynamic>{
        'produtoNome': widget.produtoNome,
        'temEstoque': widget.temEstoque,
        if (widget.nomeLoja != null &&
            widget.nomeLoja!.trim().isNotEmpty)
          'nomeLoja': widget.nomeLoja!.trim(),
        if (widget.contatoWhatsapp != null &&
            widget.contatoWhatsapp!.trim().isNotEmpty)
          'contato': widget.contatoWhatsapp!.trim(),
        if (widget.politicaFrete != null &&
            widget.politicaFrete!.trim().isNotEmpty)
          'politicaFrete': widget.politicaFrete!.trim(),
      };
      final resposta = await AiLojaService.chatAtendimentoCatalogo(
        pergunta: pergunta,
        contexto: contexto.isEmpty ? null : contexto,
      );
      if (mounted) {
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        setState(() {
          _resposta = resposta;
          _enviando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AiLojaService.messageForUser(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxW = math.min(
      kMaxContentWidth,
      MediaQuery.sizeOf(context).width - 40,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: AlertDialog(
      title: const Text('Dúvidas? Pergunte'),
      content: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.perguntaCtrl,
              decoration: const InputDecoration(
                hintText: 'Ex: Tem em estoque? Qual o prazo de entrega?',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              enabled: !_enviando,
            ),
            if (_resposta != null) ...[
              const SizedBox(height: 16),
              const Text('Resposta:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    child: SelectableText(_resposta!,
                        style: const TextStyle(height: 1.4)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
        FilledButton.icon(
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send, size: 18),
          label: Text(_enviando ? 'Enviando…' : 'Enviar'),
        ),
      ],
      ),
    );
  }
}
