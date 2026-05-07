// lib/screens/public_catalog/widgets/catalog_product_detail_screen.dart
// Tela de detalhes do produto para layout minimalista – full screen, visual clean.

import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/produto_variacao_extra.dart';
import '../../../services/catalog_share_service.dart';
import '../../../services/ai_loja_service.dart';
import '../../../services/ia_uso_limite_service.dart';
import '../../../utils/image_provider.dart';
import '../../../utils/platform_adaptive.dart';
import '../../../utils/safe_parse.dart';
import '../catalog_helpers.dart' show
    catalogProductImageUrlsForDisplay,
    catalogSugestoesRelacionadasParaDetalhe,
    selectCatalogPrimaryImageUrlFromProdutoMap;
import 'catalog_combo_configurable_sheet.dart';
import 'catalog_product_variation_pick_body.dart';
import '../catalog_theme_extension.dart';

Color _detailCatalogAccent(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.chipFilterSelectedBg ??
    theme.extension<CatalogThemeExtension>()?.buttonComprarBg ??
    theme.colorScheme.primary;

Color _detailCatalogOnAccent(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.chipFilterSelectedText ??
    theme.extension<CatalogThemeExtension>()?.buttonComprarText ??
    theme.colorScheme.onPrimary;

Color _detailBuyButtonBg(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.buttonComprarBg ??
        _detailCatalogAccent(theme);

Color _detailBuyButtonFg(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.buttonComprarText ??
        _detailCatalogOnAccent(theme);

Color _detailProductPriceColor(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.productPriceColor ??
        _detailCatalogAccent(theme);

Color? _detailProductNameColor(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.productNameColor;

Color _detailBackdropSeed(ThemeData theme) =>
    theme.extension<CatalogThemeExtension>()?.buttonComprarBg ??
        theme.colorScheme.primary;

double _catalogDetailMaxInnerWidth(double viewportW) {
  if (viewportW >= 1024) return 900;
  if (viewportW >= 800) return 820;
  if (viewportW >= 680) return 760;
  return viewportW;
}

/// Rotas fullscreen do [Navigator] entram no [Overlay] lateral à pilha, fora da
/// subárvore onde o catálogo aplica [CatalogThemeExtension]. Sem isto,
/// `Theme.extension<CatalogThemeExtension>()` volta null e cores caem no tema
/// global (ex.: botão/preto/cinza). Repete aqui o [Theme] válido na origem da navegação.
Widget catalogReplayOpenedTheme(BuildContext openerContext, Widget child) =>
    Theme(data: Theme.of(openerContext), child: child);

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
class CatalogProductDetailScreen extends StatefulWidget {
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
  /// Produtos já carregados (grid + sugestões no detalhe).
  final List<Map<String, dynamic>> fonteCatalogoParaSugestoes;
  /// Snapshot do mapa do produto (categoria/subcategoria para sugestões).
  final Map<String, dynamic> produtoCatalogoSnap;
  final double? jurosParcelamento;

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
    this.fonteCatalogoParaSugestoes = const [],
    this.produtoCatalogoSnap = const {},
    this.jurosParcelamento,
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
    List<Map<String, dynamic>>? listaCatalogoMemoria,
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
    final imagensCatalogo = catalogProductImageUrlsForDisplay(asMap(p));
    final maxPar = safeBool(p['divideSemJuros'])
        ? safeInt(p['maxParcelasSemJuros'], 12).clamp(1, 24)
        : 12;

    final produtoSnap =
        Map<String, dynamic>.from(p.map((k, v) => MapEntry(k.toString(), v)));

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
      imagens: imagensCatalogo,
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
      fonteCatalogoParaSugestoes:
          listaCatalogoMemoria ?? todosProdutos ?? const [],
      produtoCatalogoSnap: produtoSnap,
      jurosParcelamento: p['jurosParcelamento'] is num
          ? (p['jurosParcelamento'] as num).toDouble()
          : double.tryParse('${p['jurosParcelamento']}'),
    );
  }

  @override
  State<CatalogProductDetailScreen> createState() =>
      _CatalogProductDetailScreenState();
}



class _CatalogProductDetailScreenState extends State<CatalogProductDetailScreen> {
  final GlobalKey<CatalogProductVariationPickBodyState> _pickKey =
      GlobalKey<CatalogProductVariationPickBodyState>();
  bool _descricaoExpandida = false;

  bool get _temFaixaPreco =>
      widget.priceMin != null &&
      widget.priceMax != null &&
      (widget.priceMin! - widget.priceMax!).abs() > 0.001;

  String _fmt2(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

  double _parcelaComJuros(double valor, double taxaMensalPct, int n) {
    if (n <= 0 || taxaMensalPct <= 0) return valor / n;
    final i = taxaMensalPct / 100;
    var p = 1.0;
    for (var k = 0; k < n; k++) {
      p *= (1 + i);
    }
    return valor * (i * p) / (p - 1);
  }

  bool get _variacoesInline {
    if (widget.ehCombo) return false;
    return (widget.estoquePorTamanho != null &&
            widget.estoquePorTamanho!.isNotEmpty) ||
        (widget.estoquePorCor != null && widget.estoquePorCor!.isNotEmpty) ||
        (widget.variacoes != null && widget.variacoes!.isNotEmpty);
  }

  double _precoBaseParcelamentoPix() {
    final v = _pickKey.currentState;
    if (_temFaixaPreco) return widget.priceMin ?? widget.price;
    if (_variacoesInline && v != null) return v.precoVariacaoAtual;
    return widget.price;
  }

  double _precoTituloOuPromoRed() {
    if (_temFaixaPreco) return widget.priceMin ?? widget.price;
    final v = _pickKey.currentState;
    if (_variacoesInline && v != null) return v.precoVariacaoAtual;
    return widget.price;
  }

  String _textoParcelasResumo() {
    final valor = _precoBaseParcelamentoPix();
    final n = widget.maxParcelas.clamp(1, 24);
    final pref = _temFaixaPreco ? 'A partir de ' : '';
    if (widget.divideSemJuros) {
      return '$pref${n}x R\$ ${_fmt2(valor / n)} sem juros';
    }
    final juros = widget.jurosParcelamento;
    if (juros != null && juros > 0) {
      final parc = _parcelaComJuros(valor, juros, n);
      return '${pref}até ${n}x R\$ ${_fmt2(parc)}';
    }
    return '${pref}em até ${n}x R\$ ${_fmt2(valor / n)}';
  }

  List<Map<String, dynamic>> _sugestados() =>
      catalogSugestoesRelacionadasParaDetalhe(
        fonteCompletaCatalogo: widget.fonteCatalogoParaSugestoes,
        produtoAtual: widget.produtoCatalogoSnap,
        limite: 8,
      );

  void _abrirDetalheRelacionado(Map<String, dynamic> p) {
    final opener = context;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => catalogReplayOpenedTheme(
          opener,
          CatalogProductDetailScreen.fromProdutoMap(
            p: p,
            lojaId: widget.lojaId,
            onAdd: widget.onAdd,
            onAbrirCarrinho: widget.onAbrirCarrinho,
            catalogShareUrl: widget.catalogShareUrl,
            nomeLoja: widget.nomeLoja,
            contatoWhatsapp: widget.contatoWhatsapp,
            politicaFrete: widget.politicaFrete,
            prazoEntregaTexto: widget.prazoEntrega,
            todosProdutos: widget.todosProdutosForCombo,
            listaCatalogoMemoria: widget.fonteCatalogoParaSugestoes,
            initialCatalogExtraValor: widget.initialCatalogExtraValor,
            onCatalogVariacaoExtraChanged:
                widget.onCatalogVariacaoExtraChanged,
          ),
        ),
      ),
    );
  }

  void _openFullscreenGallery(BuildContext context, int initialIndex) {
    if (widget.imagens.isEmpty ||
        widget.imagens.every((e) => e.trim().isEmpty)) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CatalogFullscreenGallery(
          images:
              widget.imagens.where((e) => e.trim().isNotEmpty).toList(),
          initialIndex: initialIndex,
          heroPrefix: widget.id,
        ),
      ),
    );
  }

  void _onCommitVariacao(
    String? tamanho,
    String? cor,
    double preco,
    String extraValor,
    String extraTipo,
  ) {
    final img = widget.imagens.isNotEmpty ? widget.imagens.first : '';
    final ex = extraValor.trim();
    final resumoExtra = ex.isNotEmpty
        ? ProdutoVariacaoExtra.textoResumoExtra(
            extraTipo: extraTipo,
            extraValor: ex,
          )
        : '';
    widget.onAdd({
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
      'tamanho': tamanho ?? '',
      'cor': cor ?? '',
      if (ex.isNotEmpty) 'extraValor': ex,
      if (extraTipo.trim().isNotEmpty) 'extraTipo': extraTipo.trim(),
      if (resumoExtra.isNotEmpty) 'variacaoExtraResumo': resumoExtra,
    });
    if (mounted) Navigator.of(context).pop();
    widget.onAbrirCarrinho?.call();
  }

  void _addToCart(BuildContext context) {
    if (widget.ehCombo &&
        widget.comboProductMap != null &&
        widget.todosProdutosForCombo != null) {
      showCatalogComboVariationSheet(
        context: context,
        comboProduct: widget.comboProductMap!,
        todosProdutos: widget.todosProdutosForCombo!,
        onAdd: widget.onAdd,
        onAbrirCarrinho: () {
          Navigator.of(context).pop();
          widget.onAbrirCarrinho?.call();
        },
      );
      return;
    }
    if (_variacoesInline) {
      _pickKey.currentState?.commitPickToCart();
      return;
    }
    final img = widget.imagens.isNotEmpty ? widget.imagens.first : '';
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
    if (mounted) Navigator.of(context).pop();
    widget.onAbrirCarrinho?.call();
  }

  bool _podeAcaoPrincipal() {
    if (widget.quantidade <= 0) return false;
    if (widget.ehCombo) return true;
    if (_variacoesInline) {
      return _pickKey.currentState?.podeAdicionarVariacao ?? false;
    }
    return true;
  }

  String _rotuloAcaoPrincipal() {
    if (widget.quantidade <= 0) return 'Indisponível';
    if (!_variacoesInline || widget.ehCombo) {
      return 'Adicionar ao carrinho';
    }
    return _pickKey.currentState?.textoBotaoVariacao ??
        'Selecione as opções';
  }

  void _abrirDuvidasPergunte(BuildContext context) {
    final perguntaCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => _DuvidasPergunteDialogDetail(
        produtoNome: widget.name,
        temEstoque: widget.quantidade > 0,
        nomeLoja: widget.nomeLoja,
        contatoWhatsapp: widget.contatoWhatsapp,
        politicaFrete: widget.politicaFrete,
        perguntaCtrl: perguntaCtrl,
        lojaId: widget.lojaId,
      ),
    );
  }

  Widget _buildProdutosKit(ThemeData theme) {
    final itens = widget.itensCombo;
    if (itens == null || itens.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 22,
              color: _detailCatalogAccent(theme),
            ),
            const SizedBox(width: 8),
            Text(
              'Produtos do kit',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _detailCatalogAccent(theme),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _detailCatalogAccent(theme).withOpacity(0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _detailCatalogAccent(theme).withOpacity(0.26),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este kit contém:',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.hintColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              ...itens.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final item = entry.value;
                final nomeItem =
                    (item['nome'] ?? item['name'] ?? '').toString();
                final qtd = (item['quantidade'] is num)
                    ? (item['quantidade'] as num).toInt()
                    : int.tryParse('${item['quantidade']}') ?? 1;
                final tam = (item['tamanho'] ?? '').toString().trim();
                final cor = (item['cor'] ?? '').toString().trim();
                final extras = <String>[];
                if (tam.isNotEmpty) extras.add('Tamanho: $tam');
                if (cor.isNotEmpty) extras.add('Cor: $cor');
                final extraLinha =
                    ProdutoVariacaoExtra.resumoExtraLinhaDeItemMap(
                  Map<String, dynamic>.from(item),
                );
                if (extraLinha.isNotEmpty) extras.add(extraLinha);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              _detailCatalogAccent(theme).withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$idx',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _detailCatalogAccent(theme),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nomeItem,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (extras.isNotEmpty)
                              Text(
                                extras.join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.hintColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${qtd}x',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _detailCatalogAccent(theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  /// Altura mínima do carrossel de sugestões: imagem + nome (2 linhas) + preço + paddings.
  /// Evita BOTTOM OVERFLOWED em [Column] quando a faixa vertical do [ListView] horizontal
  /// é menor que a soma dos filhos.
  double _detailSuggestionCarouselHeight(double imgH) {
    const padTopNome = 10.0;
    const padAfterNome = 8.0;
    const padBottomPreco = 12.0;
    const nomeSize = 13.0;
    const nomeLineHeight = 1.35;
    const precoSize = 14.5;
    const precoLineHeight = 1.25;
    const buffer = 14.0;
    const nomeBlock =
        padTopNome + nomeSize * nomeLineHeight * 2 + padAfterNome;
    const precoBlock = precoSize * precoLineHeight + padBottomPreco;
    return imgH + nomeBlock + precoBlock + buffer;
  }

  Widget _buildSugestoes(ThemeData theme, double viewportW) {
    final list = _sugestados();
    if (list.isEmpty) return const SizedBox.shrink();
    final cardW =
        viewportW >= 900 ? 186.0 : (viewportW >= 600 ? 172.0 : 156.0);
    final imgH = viewportW >= 900 ? 126.0 : (viewportW >= 600 ? 118.0 : 112.0);
    final listHeight = _detailSuggestionCarouselHeight(imgH);
    final accent = _detailCatalogAccent(theme);
    final priceCol = _detailProductPriceColor(theme);
    final scrollPhysics = viewportW >= 900
        ? const ClampingScrollPhysics()
        : const BouncingScrollPhysics();
    final carouselDrag = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Você também pode gostar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: listHeight,
          child: ScrollConfiguration(
            behavior: carouselDrag,
            child: ListView.separated(
              physics: scrollPhysics,
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              primary: false,
              padding: EdgeInsets.fromLTRB(0, 0, viewportW >= 840 ? 8 : 6, 12),
              separatorBuilder: (_, __) =>
                  SizedBox(width: viewportW >= 900 ? 16 : 12),
              itemBuilder: (ctx, i) {
              final p = list[i];
              final thumb =
                  selectCatalogPrimaryImageUrlFromProdutoMap(asMap(p));
              final nome = safeStr(p['nome'], 'Produto');
              final pre = safeDouble(p['preco']);
              return SizedBox(
                height: listHeight,
                width: cardW,
                child: Material(
                  color: theme.cardColor,
                  elevation: 3,
                  shadowColor: accent.withOpacity(0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _abrirDetalheRelacionado(p),
                    borderRadius: BorderRadius.circular(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                          child: SizedBox(
                            height: imgH,
                            width: cardW,
                            child: thumb.isEmpty
                                ? ColoredBox(
                                    color: theme.colorScheme
                                        .surfaceContainerHighest,
                                    child: Icon(
                                      Icons.image_outlined,
                                      color: theme.hintColor,
                                    ),
                                  )
                                : Image(
                                    image: mpImageProvider(thumb),
                                    width: cardW,
                                    height: imgH,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.broken_image_outlined,
                                      color: theme.hintColor,
                                    ),
                                  ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                                10, 10, 10, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                    color:
                                        theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'R\$ ${_fmt2(pre)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    height: 1.2,
                                    color: priceCol,
                                  ),
                                ),
                              ],
                            ),
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seed = _detailBackdropSeed(theme);
    final layeredBg = Color.alphaBlend(
      seed.withOpacity(0.065),
      theme.scaffoldBackgroundColor,
    );
    final accent = _detailCatalogAccent(theme);
    final priceCol = _detailProductPriceColor(theme);
    final nomeCol = _detailProductNameColor(theme);
    final w = MediaQuery.of(context).size.width;
    final galleryHeight =
        w < 420 ? 300.0 : (w >= 900 ? 392.0 : 340.0);
    final precoLinhaSel = _precoTituloOuPromoRed();
    final precoParcelPixBase = _precoBaseParcelamentoPix();
    final galleryBackdrop = Color.alphaBlend(
      theme.colorScheme.surfaceContainerHighest.withOpacity(0.42),
      theme.colorScheme.surface,
    );

    return Scaffold(
      backgroundColor: layeredBg,
      appBar: AppBar(
        backgroundColor: Color.alphaBlend(
          seed.withOpacity(0.14),
          theme.colorScheme.surface,
        ),
        foregroundColor: theme.colorScheme.onSurface,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        shadowColor: seed.withOpacity(0.06),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: theme.dividerColor.withOpacity(0.12),
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        actions: [
          if (widget.catalogShareUrl != null &&
              widget.catalogShareUrl!.isNotEmpty)
            IconButton(
              onPressed: () async {
                final precoTexto = _temFaixaPreco
                    ? 'R\$ ${_fmt2(widget.priceMin!)} a R\$ ${_fmt2(widget.priceMax!)}'
                    : 'R\$ ${_fmt2(precoLinhaSel)}';
                final msg = CatalogShareService.buildProductShareMessage(
                  nome: widget.name,
                  precoTexto: precoTexto,
                  descricaoCurta: widget.descricao.trim().isEmpty
                      ? null
                      : widget.descricao,
                  url: widget.catalogShareUrl!,
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
      bottomNavigationBar: widget.quantidade > 0
          ? Material(
              elevation: 10,
              color: theme.colorScheme.surface,
              shadowColor: accent.withOpacity(0.14),
              surfaceTintColor: Colors.transparent,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.dividerColor.withOpacity(0.09),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                      child: SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: _podeAcaoPrincipal()
                              ? () => _addToCart(context)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _detailBuyButtonBg(theme),
                            foregroundColor: _detailBuyButtonFg(theme),
                            disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
                            disabledForegroundColor:
                                theme.colorScheme.onSurface.withOpacity(0.38),
                            elevation: 1,
                            shadowColor:
                                accent.withOpacity(_podeAcaoPrincipal() ? 0.22 : 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            _rotuloAcaoPrincipal(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                seed.withOpacity(
                    theme.brightness == Brightness.dark ? 0.12 : 0.082),
                layeredBg,
              ),
              layeredBg,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(w, _catalogDetailMaxInnerWidth(w)),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(bottom: widget.quantidade > 0 ? 14 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Material(
                    elevation: 5,
                    borderRadius: BorderRadius.circular(24),
                    shadowColor: accent.withOpacity(0.12),
                    color: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: galleryHeight,
                      child: ColoredBox(
                        color: galleryBackdrop,
                        child: _CatalogInlineGallery(
                          productId: widget.id,
                          imagens: widget.imagens,
                          cardColor: galleryBackdrop,
                          onOpenFullscreen: _openFullscreenGallery,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    widget.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.3,
                      color: nomeCol,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_temFaixaPreco)
                    Text(
                      'R\$ ${_fmt2(widget.priceMin!)} a R\$ ${_fmt2(widget.priceMax!)}',
                      style: TextStyle(
                        color: priceCol,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else if (widget.emPromocao && widget.precoOriginal != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'R\$ ${_fmt2(widget.precoOriginal!)}',
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 14,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'R\$ ${_fmt2(precoLinhaSel)}',
                          style: TextStyle(
                            color: priceCol,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.percentualPromo > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.94),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '-${widget.percentualPromo.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: _detailCatalogOnAccent(theme),
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
                      'R\$ ${_fmt2(precoLinhaSel)}',
                      style: TextStyle(
                        color: priceCol,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (widget.percentualDescontoPix > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.pix, size: 18, color: Colors.green[700]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ou R\$ ${_fmt2(precoParcelPixBase * (1 - widget.percentualDescontoPix / 100))} no PIX (${widget.percentualDescontoPix == widget.percentualDescontoPix.truncateToDouble() ? widget.percentualDescontoPix.toInt() : _fmt2(widget.percentualDescontoPix)}% off)',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.maxParcelas > 1 ||
                      widget.divideSemJuros ||
                      (widget.jurosParcelamento != null &&
                          widget.jurosParcelamento! > 0)) ...[
                    const SizedBox(height: 6),
                    Text(
                      _textoParcelasResumo(),
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (widget.prazoEntrega != null &&
                      widget.prazoEntrega!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 18, color: theme.hintColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Entrega: ${widget.prazoEntrega}',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.descricao.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 2,
                      shadowColor: accent.withOpacity(0.08),
                      surfaceTintColor: Colors.transparent,
                      color: theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withOpacity(0.42),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.article_outlined,
                                  size: 21,
                                  color: accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Descrição',
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AnimatedCrossFade(
                              firstChild: Text(
                                widget.descricao,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.55,
                                  color: theme.textTheme.bodyLarge?.color
                                      ?.withOpacity(0.9),
                                ),
                              ),
                              secondChild: Text(
                                widget.descricao,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.55,
                                  color: theme.textTheme.bodyLarge?.color
                                      ?.withOpacity(0.9),
                                ),
                              ),
                              crossFadeState: _descricaoExpandida
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration:
                                  const Duration(milliseconds: 200),
                            ),
                            if (widget.descricao.trim().length > 180)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => setState(
                                    () => _descricaoExpandida =
                                        !_descricaoExpandida,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: accent,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text(
                                    _descricaoExpandida
                                        ? 'Ver menos'
                                        : 'Ver descrição completa',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (widget.ehCombo) _buildProdutosKit(theme),
                  if (_variacoesInline) ...[
                    const SizedBox(height: 22),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 2,
                      shadowColor: accent.withOpacity(0.08),
                      surfaceTintColor: Colors.transparent,
                      color: theme.cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withOpacity(0.42),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                        child: CatalogProductVariationPickBody(
                          key: _pickKey,
                          name: widget.name,
                          price: widget.price,
                          precoOriginal: widget.precoOriginal,
                          emPromocao: widget.emPromocao,
                          imageUrl:
                              widget.imagens.isNotEmpty ? widget.imagens.first : '',
                          estoquePorTamanho: widget.estoquePorTamanho ?? {},
                          estoquePorCor: widget.estoquePorCor ?? {},
                          variacoes: widget.variacoes,
                          variacoesExtraTipo: widget.variacoesExtraTipo,
                          precoPorTamanho: widget.precoPorTamanho,
                          onPickCommit: _onCommitVariacao,
                          percentualDescontoPix: widget.percentualDescontoPix,
                          mostrarQuantidadeNoCatalogo: false,
                          initialExtraValor: widget.initialCatalogExtraValor,
                          onCatalogVariacaoExtraChanged:
                              widget.onCatalogVariacaoExtraChanged,
                          showProductSnippet: false,
                          showAddToCartButton: false,
                          showSectionTitle: true,
                          onSelectionsChanged: () => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                  _buildSugestoes(theme, w),
                  const SizedBox(height: 12),
                  if (widget.quantidade <= 0) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Indisponível',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _abrirDuvidasPergunte(context),
                    icon: Icon(Icons.help_outline,
                        size: 20, color: accent),
                    label: Text('Dúvidas? Pergunte',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: accent)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withOpacity(0.42)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    ),
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
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey[400],
                    size: 64,
                  ),
                ),
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
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
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
