// lib/screens/public_catalog/widgets/product_card.dart
// Wrapper que mapeia Map<String, dynamic> produto para CatalogProductCard (UI extraído de public_catalog_screen.dart)

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import '../../../debug/catalog_normal_trace.dart';
import '../../../services/catalog_share_service.dart';
import '../../../services/public_store_link_helper.dart';
import '../../../utils/safe_parse.dart';
import '../catalog_helpers.dart'
    show
        catalogImageUrlMaskForLog,
        catalogPrecoPorTamanhoFromDynamic,
        catalogProductImageUrlLooksLikeGeneratedThumbnail,
        catalogProductImageUrlsForDisplay,
        selectCatalogPrimaryImageUrlFromProdutoMap;
import '../catalog_product_card_size.dart';
import 'catalog_product_card.dart';

/// Converte Map (Firestore pode vir Map<dynamic,dynamic> na web) para Map<String, int>.
Map<String, int> _mapToMapStringInt(Map<String, dynamic> raw) {
  final result = <String, int>{};
  raw.forEach((k, v) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n != null && n > 0) result[k.toString()] = n;
  });
  return result;
}

/// Card de produto do catálogo público. Recebe Map do produto e mapeia para CatalogProductCard.
/// Usado no grid e na seção "Vistos recentemente" — mesma hierarquia, mesmos paddings, callbacks e layout.
class PublicCatalogProductCard extends StatelessWidget {
  final Map<String, dynamic> produto;
  final String lojaId;
  final bool Function(Map<String, dynamic>) onAdd;
  final VoidCallback? onMinimalSilentAddFeedback;
  final void Function(String productId)? onProductViewed;
  final void Function(String prodUrlValue)? onProductUrlFocus;
  final VoidCallback? onProductUrlBlur;
  final void Function()? onToggleFavorito;
  final void Function()? onAbrirCarrinho;
  final String? clienteId;
  final List<String> favoritosIds;
  /// Lista de todos os produtos do catálogo (para combos: resolver variações dos itens do kit).
  final List<Map<String, dynamic>>? todosProdutos;
  final bool mostrarEstoqueNoCatalogo;
  final bool mostrarQuantidadeNoCatalogo;
  final double cardBorderRadius;
  final bool cardShowShadow;
  final String? prazoEntregaTexto;
  final double? jurosParcelamento;
  final int maxParcelas;
  /// Layout compacto (ex.: seção "Vistos recentemente")
  final bool compact;
  final int? imageCacheWidth;
  final int? imageCacheHeight;
  /// URL do catálogo para compartilhar (máscara, link curto ou padrão)
  final String? catalogShareUrl;
  /// Layout minimalista: card abre tela de detalhe ao toque, sem botão Ver, tipografia reduzida
  final bool minimalLayout;
  /// No catálogo clássico: card com o mesmo template visual do minimalista.
  final bool classicMinimalCardVisual;
  /// Grid principal clássico com corpo desktop (≥1024).
  final bool classicGridWideBody;
  final String productCardSize;
  final String? catalogInitialExtraValor;
  final void Function(String? value)? onCatalogVariacaoExtraChanged;

  const PublicCatalogProductCard({
    super.key,
    required this.produto,
    required this.lojaId,
    required this.onAdd,
    this.onMinimalSilentAddFeedback,
    this.onProductViewed,
    this.onProductUrlFocus,
    this.onProductUrlBlur,
    this.onToggleFavorito,
    this.onAbrirCarrinho,
    this.clienteId,
    this.favoritosIds = const [],
    this.todosProdutos,
    this.mostrarEstoqueNoCatalogo = false,
    this.mostrarQuantidadeNoCatalogo = false,
    this.cardBorderRadius = 18.0,
    this.cardShowShadow = true,
    this.prazoEntregaTexto,
    this.jurosParcelamento,
    this.maxParcelas = 12,
    this.compact = false,
    this.imageCacheWidth,
    this.imageCacheHeight,
    this.catalogShareUrl,
    this.minimalLayout = false,
    this.classicMinimalCardVisual = false,
    this.classicGridWideBody = false,
    this.productCardSize = CatalogProductCardSize.medium,
    this.catalogInitialExtraValor,
    this.onCatalogVariacaoExtraChanged,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return _buildBody(context);
    } catch (e, st) {
      final id = safeStr(produto['id']);
      final nome = safeStr(produto['nome']);
      if (kIsWeb) {
        CatalogNormalTrace.setField('last_product_card_error', e.toString());
        CatalogNormalTrace.setField(
            'last_product_card_error_type', e.runtimeType.toString());
        CatalogNormalTrace.setField('last_product_card_id', id);
        CatalogNormalTrace.setField(
            'last_product_card_name', nome.length > 80 ? '${nome.substring(0, 80)}…' : nome);
        CatalogNormalTrace.setField('last_product_stack', st.toString());
        CatalogNormalTrace.mark('product_card.build.exception');
        CatalogNormalTrace.persist();
      }
      if (kDebugMode) {
        debugPrint('PublicCatalogProductCard id=$id error=$e\n$st');
      }
      return Card(
        margin: const EdgeInsets.all(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Não foi possível exibir este produto.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
  }

  Widget _buildBody(BuildContext context) {
    final p = produto;
    final baseCatalogUrl = catalogShareUrl ?? buildPublicCatalogUrl(lojaId) ?? '';
    final deepLinkProduto = safeStr(p['slug']).isNotEmpty ? safeStr(p['slug']) : safeStr(p['id']);
    final catalogUrl = CatalogShareService.buildUrlWithParams(
      baseCatalogUrl,
      prod: deepLinkProduto,
    );

    final estoqueTam = _mapToMapStringInt(asMap(p['estoquePorTamanho']));
    final estoqueCor = _mapToMapStringInt(asMap(p['estoquePorCor']));

    final price = safeDouble(p['preco']);
    final priceMin = p['priceMin'] != null ? safeDouble(p['priceMin']) : null;
    final priceMax = p['priceMax'] != null ? safeDouble(p['priceMax']) : null;
    final precoPorTamanho =
        catalogPrecoPorTamanhoFromDynamic(p['precoPorTamanho']);

    final imageUrls = catalogProductImageUrlsForDisplay(p);
    final coverUrl = selectCatalogPrimaryImageUrlFromProdutoMap(p);
    if (kDebugMode) {
      debugPrint(
        '[CATALOG-IMG] id=${safeStr(p['id'])} '
        'cover=${catalogImageUrlMaskForLog(coverUrl)} '
        'coverLooksThumb=${catalogProductImageUrlLooksLikeGeneratedThumbnail(coverUrl)} '
        'imagensCount=${imageUrls.length}',
      );
    }

    final tipoProduto = (p['tipoProduto'] ?? p['tipo'] ?? 'simples').toString();
    final itensComboRaw = p['itensCombo'];
    List<Map<String, dynamic>>? itensCombo;
    if (itensComboRaw is List && itensComboRaw.isNotEmpty) {
      itensCombo = [];
      for (final e in itensComboRaw) {
        if (e is! Map) continue;
        itensCombo.add(asMap(e));
      }
      if (itensCombo.isEmpty) itensCombo = null;
    }
    // Kit/combo: tipoProduto == 'combo' OU lista itensCombo preenchida
    final ehCombo = tipoProduto == 'combo' || (itensCombo != null && itensCombo.isNotEmpty);

    return CatalogProductCard(
      id: safeStr(p['id'], ''),
      name: safeStr(p['nome'], 'Produto'),
      lojaId: lojaId,
      price: price,
      priceMin: priceMin,
      priceMax: priceMax,
      precoPorTamanho: precoPorTamanho,
      imageUrl: coverUrl.isNotEmpty
          ? coverUrl
          : (imageUrls.isNotEmpty ? imageUrls.first : ''),
      imagens: imageUrls,
      descricao: safeStr(p['descricao']),
      slug: safeStr(p['slug']),
      peso: safeDouble(p['peso']),
      tipoEmbalagem: safeStr(p['tipoEmbalagem'], 'padrao'),
      emPromocao: safeBool(p['emPromocao']),
      precoOriginal: (p['emPromocao'] == true)
          ? safeDouble(p['precoFinal'])
          : null,
      percentualPromo: safeDouble(p['percentualPromo']),
      valorPromo: safeDouble(p['valorPromo']),
      quantidade: safeInt(p['quantidade']),
      estoquePorTamanho: estoqueTam.isNotEmpty ? estoqueTam : null,
      estoquePorCor: estoqueCor.isNotEmpty ? estoqueCor : null,
      variacoes: (p['variacoes'] != null &&
              asMapDeep(p['variacoes']).isNotEmpty)
          ? asMapDeep(p['variacoes'])
          : null,
      variacoesExtraTipo: (p['variacoesExtraTipo'] != null &&
              asMapDeep(p['variacoesExtraTipo']).isNotEmpty)
          ? asMapDeep(p['variacoesExtraTipo'])
          : null,
      onAdd: onAdd,
      onMinimalSilentAddFeedback: onMinimalSilentAddFeedback,
      borderRadius: cardBorderRadius,
      showShadow: cardShowShadow,
      catalogShareUrl: catalogUrl,
      isNovo: safeBool(p['isNovo']),
      onProductViewed: onProductViewed,
      onProductUrlFocus: onProductUrlFocus,
      onProductUrlBlur: onProductUrlBlur,
      isFavorito: clienteId != null && favoritosIds.contains(p['id']),
      onToggleFavorito: onToggleFavorito,
      prazoEntrega: prazoEntregaTexto,
      divideSemJuros: safeBool(p['divideSemJuros']),
      jurosParcelamento: jurosParcelamento,
      maxParcelas: safeBool(p['divideSemJuros'])
          ? safeInt(p['maxParcelasSemJuros'], maxParcelas).clamp(1, 24)
          : maxParcelas,
      percentualDescontoPix: safeDouble(p['percentualDescontoPix']),
      onAbrirCarrinho: onAbrirCarrinho,
      showStockBadge: mostrarEstoqueNoCatalogo,
      mostrarQuantidadeNoCatalogo: mostrarQuantidadeNoCatalogo,
      compact: compact,
      imageCacheWidth: imageCacheWidth,
      imageCacheHeight: imageCacheHeight,
      ehCombo: ehCombo,
      itensCombo: itensCombo,
      comboProductMap: ehCombo ? p : null,
      todosProdutosForCombo: ehCombo ? (todosProdutos ?? []) : null,
      minimalLayout: minimalLayout,
      classicMinimalCardVisual: classicMinimalCardVisual,
      classicGridWideBody: classicGridWideBody,
      productCardSize: productCardSize,
      initialCatalogExtraValor: catalogInitialExtraValor,
      onCatalogVariacaoExtraChanged: onCatalogVariacaoExtraChanged,
    );
  }
}

