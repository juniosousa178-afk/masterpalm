// lib/screens/public_catalog_screen.dart
// Catálogo público (WEB/Mobile) – carrinho funcional, banners rolando,
// checkout com cadastro obrigatório e botão WhatsApp / Mercado Pago.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../utils/http_client_helper.dart';
import '../widgets/smart_image.dart';
import '../services/store_resolver_facade.dart';
import '../widgets/campanha_banner_widget.dart';
import '../services/catalogo_venda_service.dart';
import '../services/pre_pedido_service.dart';
import '../services/mercadopago_service.dart';
import 'auth/login_screen_cliente.dart';
import 'package:master_palm/screens/auth/cadastro_screen_cliente.dart';
import 'auth/perfil_cliente_screen_novo.dart';
import '../services/cliente_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/catalog_cache_service.dart';
import '../services/catalog_recent_service.dart';
import '../services/catalog_share_service.dart';
import '../services/catalog_visitas_service.dart';

import '../utils/instagram_launcher.dart';
import '../utils/pix_brcode.dart';
import '../widgets/pix_qr_dialog.dart';
import 'public_catalog/catalog_helpers.dart';
import 'public_catalog/catalog_best_sellers_helper.dart';
import 'public_catalog/catalog_product_card_size.dart';
import 'public_catalog/catalog_estoque_helper.dart';
import 'public_catalog/catalog_config_service.dart';
import '../utils/safe_parse.dart';
import 'public_catalog/catalog_theme_extension.dart';
import 'public_catalog/widgets/catalog_banner_carousel.dart';
import 'public_catalog/widgets/catalog_config_error_state.dart';
import 'public_catalog/widgets/catalog_config_loading_state.dart';
import 'public_catalog/widgets/catalog_empty_products_state.dart';
import 'public_catalog/widgets/catalog_error_loja_state.dart';
import 'public_catalog/widgets/catalog_footer.dart';
import 'public_catalog/widgets/catalog_loading_state.dart';
import 'public_catalog/widgets/catalog_search_filters_bar.dart';
import 'public_catalog/widgets/catalog_products_grid_sliver.dart';
import 'public_catalog/widgets/catalog_recent_section_sliver.dart';
import 'public_catalog/widgets/catalog_skeleton_grid.dart';
import 'public_catalog/widgets/catalog_minimalist_widgets.dart';
import 'public_catalog/widgets/catalog_minimal_best_sellers.dart';
import 'public_catalog/widgets/catalog_product_detail_screen.dart';
import 'public_catalog/widgets/catalog_product_details_sheet.dart';
import 'public_catalog/widgets/carrinho_sheet_web.dart';
import 'public_catalog/catalog_dicas_screen.dart';
import '../core/logger.dart';

// ===================================================================
// CACHE CATÁLOGO – Reduz leituras Firestore (TTL 3–5 min)
// ===================================================================
const bool _useCatalogCache =
    true; // Produção: cache; Preview: Firestore direto

class PublicCatalogScreen extends StatefulWidget {
  final String lojaId;
  final bool preview;

  /// ✅ ID do vendedor para tracking de comissão (vem da URL ?ref=vendedorId)
  final String? vendedorRef;

  /// ✅ ID do cliente que indicou (link ?indicacao=clienteId) – quem comprou ganha cupom e quem indicou também (após o amigo usar)
  final String? indicacaoClienteRef;

  /// ✅ Página inicial ao abrir (ex: ?page=dicas no link do catálogo)
  final String? initialPage;

  /// ✅ ID do carrinho para recuperação (ex: ?cart=ID no link)
  final String? initialCartId;

  /// ✅ ID ou slug do produto para abrir direto (ex: link campanha ?produto=ID)
  final String? initialProdutoId;

  const PublicCatalogScreen({
    super.key,
    required this.lojaId,
    this.preview = false,
    this.vendedorRef,
    this.indicacaoClienteRef,
    this.initialPage,
    this.initialCartId,
    this.initialProdutoId,
  });

  @override
  State<PublicCatalogScreen> createState() => _PublicCatalogScreenState();
}

/// Produtos por página no catálogo
const int _produtosPorPagina = 20;

/// Processa docs Firestore em lista de produtos (evita bloquear UI no build).
List<Map<String, dynamic>> _processDocsToProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final produtos = <Map<String, dynamic>>[];
  for (final d in docs) {
    try {
      final m = asMapDeep(d.data());
      if (m.isEmpty) continue;
      final publicarNoCatalogo =
          m['publicadoNoCatalogo'] ?? m['publicarNoCatalogo'] ?? true;
      if (publicarNoCatalogo == false) continue;

      final bool exibirCatalogo = !(m['exibir_no_catalogo'] == false ||
          m['ocultar_catalogo'] == true ||
          m['catalog_ativo'] == false);
      if (!exibirCatalogo) continue;

      final tipoEarly =
          (m['tipoProduto'] ?? m['tipo'] ?? 'simples').toString();
      final itensComboEarly = m['itensCombo'];
      final isComboEarly = tipoEarly == 'combo' ||
          (itensComboEarly is List && itensComboEarly.isNotEmpty);

      final stock = CatalogEstoqueHelper.processStockFromFirestoreMap(
        m,
        isCombo: isComboEarly,
      );
      if (!stock.incluirNoCatalogo) continue;

      final quantidadeTotal = stock.quantidadeTotal;
      final estoquePorTamanho = stock.estoquePorTamanho;
      final estoquePorCor = stock.estoquePorCor;
      final variacoes = stock.variacoes;

      final nome = (m['nome'] ?? m['name'] ?? '').toString();
      final desc = (m['descricao_curta'] ?? m['descricao'] ?? '').toString();
      final precoRaw =
          m['preco'] ?? m['preco_venda'] ?? m['price'] ?? m['precoFinal'];
      final preco = (precoRaw is num)
          ? precoRaw.toDouble()
          : double.tryParse('$precoRaw') ?? 0.0;

      // Preço por variação: no card deve aparecer o menor e o maior cadastrado na variação
      double priceMin = preco;
      double priceMax = preco;
      Map<String, double>? precoPorTamanhoMap;
      final pptRaw = m['precoPorTamanho'];
      if (pptRaw is Map && pptRaw.isNotEmpty) {
        precoPorTamanhoMap = {};
        final precos = <double>[];
        for (final e in pptRaw.entries) {
          final v = e.value;
          final d = (v is num) ? v.toDouble() : double.tryParse('$v');
          if (d != null && d > 0) {
            precoPorTamanhoMap[e.key.toString()] = d;
            precos.add(d);
          }
        }
        if (precos.isNotEmpty) {
          priceMin = precos.reduce((a, b) => a < b ? a : b);
          priceMax = precos.reduce((a, b) => a > b ? a : b);
        }
        if (precoPorTamanhoMap.isEmpty) precoPorTamanhoMap = null;
      }
      // Fallback: documento pode ter priceMin/priceMax já gravados pelo sync
      if (m['priceMin'] != null || m['priceMax'] != null) {
        final pm = (m['priceMin'] is num)
            ? (m['priceMin'] as num).toDouble()
            : double.tryParse('${m['priceMin']}');
        final pM = (m['priceMax'] is num)
            ? (m['priceMax'] as num).toDouble()
            : double.tryParse('${m['priceMax']}');
        if (pm != null && pM != null && pm > 0 && pM > 0) {
          if (precoPorTamanhoMap == null || precoPorTamanhoMap.isEmpty) {
            priceMin = pm < pM ? pm : pM;
            priceMax = pm > pM ? pm : pM;
          }
        }
      }

      final categoria =
          (m['categoria'] ?? m['categoria_nome'] ?? m['categoriaNome'] ?? '')
              .toString()
              .trim();
      final subcategoria = (m['subcategoria'] ??
              m['subcategoriaId'] ??
              m['subcategoria_nome'] ??
              '')
          .toString()
          .trim();

      String principal =
          (m['imagem_principal'] ?? m['imageUrl'] ?? '').toString();
      final imagens = <String>[];
      final imgsRaw = m['imagens'];
      if (imgsRaw is List) imagens.addAll(imgsRaw.map((e) => e.toString()));
      if (imagens.isEmpty && principal.isNotEmpty) imagens.add(principal);
      if (principal.isEmpty && imagens.isNotEmpty) principal = imagens.first;

      final emPromocao = m['emPromocao'] == true;
      double precoComDesconto = preco;
      double priceMinComPromo = priceMin;
      double priceMaxComPromo = priceMax;
      if (emPromocao) {
        final now = DateTime.now();
        bool promocaoAtiva = true;
        final dataInicio = m['dataInicioPromo'];
        if (dataInicio is Timestamp && now.isBefore(dataInicio.toDate())) {
          promocaoAtiva = false;
        }
        final dataFim = m['dataFimPromo'];
        if (dataFim is Timestamp && now.isAfter(dataFim.toDate())) {
          promocaoAtiva = false;
        }
        if (promocaoAtiva) {
          final percentualPromo = (m['percentualPromo'] is num)
              ? (m['percentualPromo'] as num).toDouble()
              : 0.0;
          final valorPromo = (m['valorPromo'] is num)
              ? (m['valorPromo'] as num).toDouble()
              : 0.0;
          if (percentualPromo > 0) {
            precoComDesconto = (preco - preco * (percentualPromo / 100))
                .clamp(0.0, double.infinity);
            priceMinComPromo = (priceMin - priceMin * (percentualPromo / 100))
                .clamp(0.0, double.infinity);
            priceMaxComPromo = (priceMax - priceMax * (percentualPromo / 100))
                .clamp(0.0, double.infinity);
          } else if (valorPromo > 0) {
            precoComDesconto = (preco - valorPromo).clamp(0.0, double.infinity);
            priceMinComPromo =
                (priceMin - valorPromo).clamp(0.0, double.infinity);
            priceMaxComPromo =
                (priceMax - valorPromo).clamp(0.0, double.infinity);
          }
        }
      }

      DateTime? dataCriacao;
      for (final k in ['createdAt', 'criadoEm', 'dataCadastro']) {
        final v = m[k];
        if (v != null) {
          try {
            if (v is Timestamp) {
              dataCriacao = v.toDate();
              break;
            }
            if (v is DateTime) {
              dataCriacao = v;
              break;
            }
          } catch (_) {}
        }
      }
      final isNovo = dataCriacao != null &&
          DateTime.now().difference(dataCriacao).inDays <= 30;

      // Combo: itens do kit (nome, slug, quantidade, tamanho?, cor?)
      List<Map<String, dynamic>>? itensCombo;
      final itensComboRaw = m['itensCombo'];
      if (itensComboRaw is List && itensComboRaw.isNotEmpty) {
        itensCombo = [];
        for (final e in itensComboRaw) {
          if (e is! Map) continue;
          final nomeItem = (e['nome'] ?? e['name'] ?? '').toString().trim();
          if (nomeItem.isEmpty) continue;
          final slugItem = (e['slug'] ?? '').toString().trim();
          final idItem = (e['id'] ?? e['produtoId'] ?? '').toString().trim();
          itensCombo.add({
            'nome': nomeItem,
            'slug': slugItem,
            'quantidade': (e['quantidade'] is num)
                ? (e['quantidade'] as num).toInt()
                : int.tryParse('${e['quantidade']}') ?? 1,
            if (idItem.isNotEmpty) 'id': idItem,
            if ((e['tamanho'] ?? '').toString().trim().isNotEmpty)
              'tamanho': (e['tamanho'] ?? '').toString().trim(),
            if ((e['cor'] ?? '').toString().trim().isNotEmpty)
              'cor': (e['cor'] ?? '').toString().trim(),
          });
        }
        if (itensCombo.isEmpty) itensCombo = null;
      }
      final tipoProduto =
          (m['tipoProduto'] ?? m['tipo'] ?? 'simples').toString();

      produtos.add({
        'id': d.id,
        'nome': nome.isEmpty ? 'Produto sem nome' : nome,
        'descricao': desc,
        'preco': emPromocao ? precoComDesconto : preco,
        'precoFinal': preco,
        'priceMin': emPromocao ? priceMinComPromo : priceMin,
        'priceMax': emPromocao ? priceMaxComPromo : priceMax,
        if (precoPorTamanhoMap != null && precoPorTamanhoMap.isNotEmpty)
          'precoPorTamanho': precoPorTamanhoMap,
        'imageUrl': principal,
        'imagens': imagens,
        'categoria': categoria,
        'subcategoria': subcategoria,
        'slug': m['slug'] ?? '',
        'peso': (m['peso'] is num) ? (m['peso'] as num).toDouble() : 0.0,
        'tipoEmbalagem': m['tipoEmbalagem'] ?? 'padrao',
        'emPromocao': emPromocao,
        'percentualPromo': (m['percentualPromo'] is num)
            ? (m['percentualPromo'] as num).toDouble()
            : 0.0,
        'valorPromo': (m['valorPromo'] is num)
            ? (m['valorPromo'] as num).toDouble()
            : 0.0,
        'quantidade': quantidadeTotal,
        'estoquePorTamanho': estoquePorTamanho,
        'estoquePorCor': estoquePorCor,
        'variacoes': variacoes,
        'isNovo': isNovo,
        'dataCriacao': dataCriacao,
        'divideSemJuros': m['divideSemJuros'] == true,
        'maxParcelasSemJuros': (m['maxParcelasSemJuros'] is num)
            ? (m['maxParcelasSemJuros'] as num).toInt()
            : 12,
        'percentualDescontoPix': (m['percentualDescontoPix'] is num)
            ? (m['percentualDescontoPix'] as num).toDouble()
            : 0.0,
        'videoUrl': (m['videoUrl'] ?? '').toString().trim(),
        'tipoProduto': tipoProduto,
        if (itensCombo != null && itensCombo.isNotEmpty)
          'itensCombo': itensCombo,
        if (itensCombo != null && itensCombo.isNotEmpty) ...{
          if (m['descontoComboValor'] != null)
            'descontoComboValor': (m['descontoComboValor'] is num)
                ? (m['descontoComboValor'] as num).toDouble()
                : 0.0,
          if (m['descontoComboPercentual'] != null)
            'descontoComboPercentual': (m['descontoComboPercentual'] is num)
                ? (m['descontoComboPercentual'] as num).toDouble()
                : 0.0,
        },
        'vendasScoreCatalogo': vendasScoreFromFirestoreMap(m),
      });
    } catch (e, st) {
      if (kDebugMode) {
        logD('[PARSE-FAIL] produtos (erro: type=${e.runtimeType})');
        logD('   $st');
      }
    }
  }
  _aplicarPrecoComboFromSoma(produtos);
  return produtos;
}

/// Encontra um produto na lista por id, nome ou slug (para combos).
Map<String, dynamic>? _findProdutoNaLista(List<Map<String, dynamic>> produtos,
    String? id, String? nome, String? slug) {
  final idTrim = (id ?? '').toString().trim();
  final nomeNorm = (nome ?? '').toString().trim().toLowerCase();
  final slugTrim = (slug ?? '').toString().trim();
  for (final p in produtos) {
    final pId = (p['id'] ?? '').toString().trim();
    if (idTrim.isNotEmpty && pId == idTrim) return p;
    final pNome = (p['nome'] ?? '').toString().trim().toLowerCase();
    if (nomeNorm.isNotEmpty && pNome == nomeNorm) return p;
    final pSlug = (p['slug'] ?? '').toString().trim();
    if (slugTrim.isNotEmpty && pSlug == slugTrim) return p;
  }
  return null;
}

/// Preço mínimo/máximo de um produto (considerando precoPorTamanho ou priceMin/priceMax).
void _precoMinMaxProduto(Map<String, dynamic> p, List<double> outMinMax) {
  final ppt = p['precoPorTamanho'];
  if (ppt is Map && ppt.isNotEmpty) {
    final precos = <double>[];
    ppt.forEach((_, v) {
      if (v is num) precos.add(v.toDouble());
    });
    if (precos.isNotEmpty) {
      outMinMax[0] = precos.reduce((a, b) => a < b ? a : b);
      outMinMax[1] = precos.reduce((a, b) => a > b ? a : b);
      return;
    }
  }
  final pm = (p['priceMin'] is num) ? (p['priceMin'] as num).toDouble() : null;
  final pM = (p['priceMax'] is num) ? (p['priceMax'] as num).toDouble() : null;
  final preco = (p['preco'] is num) ? (p['preco'] as num).toDouble() : 0.0;
  outMinMax[0] = pm ?? preco;
  outMinMax[1] = pM ?? preco;
}

/// Aplica preço do combo = soma dos produtos do kit com desconto (valor ou %). Mais atrativo = menor preço final.
void _aplicarPrecoComboFromSoma(List<Map<String, dynamic>> produtos) {
  for (final p in produtos) {
    final itens = p['itensCombo'];
    if (itens is! List || itens.isEmpty) continue;
    double somaMin = 0, somaMax = 0;
    for (final e in itens) {
      if (e is! Map) continue;
      final ref = _findProdutoNaLista(
        produtos,
        (e['id'] ?? e['produtoId'] ?? '').toString().trim(),
        (e['nome'] ?? e['name'] ?? '').toString().trim(),
        (e['slug'] ?? '').toString().trim(),
      );
      if (ref == null) continue;
      final qtd = (e['quantidade'] is num)
          ? (e['quantidade'] as num).toInt()
          : int.tryParse('${e['quantidade']}') ?? 1;
      final minMax = <double>[0, 0];
      _precoMinMaxProduto(ref, minMax);
      somaMin += minMax[0] * qtd;
      somaMax += minMax[1] * qtd;
    }
    if (somaMin <= 0 && somaMax <= 0) continue;
    final descontoValor = (p['descontoComboValor'] is num)
        ? (p['descontoComboValor'] as num).toDouble()
        : 0.0;
    final descontoPerc = (p['descontoComboPercentual'] is num)
        ? (p['descontoComboPercentual'] as num).toDouble()
        : 0.0;
    double finalMin = somaMin;
    double finalMax = somaMax;
    if (descontoValor > 0 || descontoPerc > 0) {
      final comValorMin = (somaMin - descontoValor).clamp(0.0, double.infinity);
      final comPercMin =
          somaMin * (1 - descontoPerc / 100).clamp(0.0, double.infinity);
      final comValorMax = (somaMax - descontoValor).clamp(0.0, double.infinity);
      final comPercMax =
          somaMax * (1 - descontoPerc / 100).clamp(0.0, double.infinity);
      finalMin = comValorMin < comPercMin ? comValorMin : comPercMin;
      finalMax = comValorMax < comPercMax ? comValorMax : comPercMax;
    }
    p['preco'] = finalMin;
    p['priceMin'] = finalMin;
    p['priceMax'] = finalMax;
  }
}

class _PublicCatalogScreenState extends State<PublicCatalogScreen> {
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier(0);
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _catalogScrollController = ScrollController();
  final ValueNotifier<double> _scrollOffsetNotifier = ValueNotifier(0);
  Timer? _searchDebounce;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String _ordenacaoProdutos =
      'nome'; // nome | preco_asc | preco_desc | novidade
  double? _precoMin;
  double? _precoMax;
  bool _apenasEmEstoque = false;

  // ✅ FONTE ÚNICA: lojaId resolvido de forma assíncrona
  String? _resolvedLojaId;
  bool _loadingLojaId = true;

  final List<Map<String, dynamic>> _cart = [];
  bool _publicando = false;

  /// Último pré-pedido criado nesta sessão do carrinho (evita vários pedidos ao trocar forma de pagamento)
  String? _ultimoPrePedidoId;
  Map<String, dynamic>? _ultimoPrePedidoData;

  /// Estado da roleta (persiste ao fechar/reabrir o carrinho; reseta em nova compra)
  bool _roletaJaGirada = false;
  String? _cupomRoletaCodigo;
  double? _cupomRoletaDesconto;
  String? _premioRoletaDescricao;
  bool _freteGratisRoleta = false;

  int _refreshCounter = 0;
  bool _isOffline = false;
  List<String> _recentIds = [];
  List<String> _favoritosIds = [];
  String? _clienteId;
  String? _clienteEmail;
  bool _modoEscuro = false;
  bool _mostrarEstoqueNoCatalogo = false;
  bool _mostrarQuantidadeNoCatalogo = false;
  bool _openedInitialPage = false;
  String? _pendingInitialProdutoId;
  bool _initialProdutoHandled = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static const String _keyModoEscuro = 'catalog_dark_mode';
  static const String _keyMostrarEstoqueCatalogo = 'mostrar_estoque_catalogo';
  static const String _keyMostrarQuantidadeCatalogo =
      'mostrar_quantidade_catalogo';
  static const Color _successColor = Color(0xFF22C55E);
  static const String _baseUrlCatalogo = 'https://app.mastepalm.com.br/loja';

  /// Cache de streams (evita recriação a cada rebuild = piscar)
  Stream<Map<String, dynamic>>? _cachedConfigStream;
  String? _cachedConfigStreamKey;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedProdutosStream;
  String? _cachedProdutosStreamKey;

  Stream<Map<String, dynamic>> _getConfigStream(String lojaId) {
    final key = '${lojaId}_${widget.preview}';
    if (_cachedConfigStreamKey == key && _cachedConfigStream != null) {
      return _cachedConfigStream!;
    }
    _cachedConfigStreamKey = key;
    _cachedConfigStream = _useCatalogCache && !widget.preview
        ? CatalogCacheService.getConfigStream(
            lojaId: lojaId,
            preview: widget.preview,
          )
        : _cfgStream(lojaId);
    return _cachedConfigStream!;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getProdutosStream(
      String lojaId) {
    final key = '${lojaId}_${widget.preview}_$_refreshCounter';
    if (_cachedProdutosStreamKey == key && _cachedProdutosStream != null) {
      return _cachedProdutosStream!;
    }
    _cachedProdutosStreamKey = key;
    _cachedProdutosStream = _useCatalogCache && !widget.preview
        ? CatalogCacheService.getProdutosStream(
            lojaId: lojaId,
            preview: widget.preview,
            forceRefresh: _refreshCounter > 0,
          )
        : _produtosStream(lojaId);
    return _cachedProdutosStream!;
  }

  @override
  void initState() {
    super.initState();
    _pendingInitialProdutoId = widget.initialProdutoId?.trim();
    _currentPageNotifier.addListener(_scrollToTopOnPageChange);
    _catalogScrollController.addListener(_onCatalogScroll);
    _resolveLojaId().catchError((e, st) {
      logD(
          '❌ [CATÁLOGO] Erro não tratado em _resolveLojaId (type=${e.runtimeType})');
      if (mounted) {
        setState(() {
          _loadingLojaId = false;
          _resolvedLojaId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Erro ao carregar: ${e is TimeoutException ? "Tempo esgotado" : e}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
    _initConnectivity();
    _loadModoEscuro();
  }

  void _debouncedSearchUpdate(String txt) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final normalized = txt.toLowerCase().trim();
      if (_searchNotifier.value != normalized) {
        _searchNotifier.value = normalized;
        _currentPageNotifier.value = 0;
      }
    });
  }

  void _onCatalogScroll() {
    if (_catalogScrollController.hasClients) {
      _scrollOffsetNotifier.value = _catalogScrollController.offset;
    }
  }

  void _scrollToTopOnPageChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _catalogScrollController.hasClients) {
        _catalogScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _catalogScrollController.removeListener(_onCatalogScroll);
    _scrollOffsetNotifier.dispose();
    _currentPageNotifier.removeListener(_scrollToTopOnPageChange);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchNotifier.dispose();
    _currentPageNotifier.dispose();
    _catalogScrollController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadModoEscuro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_keyModoEscuro);
      if (mounted) setState(() => _modoEscuro = v ?? false);
    } catch (_) {}
  }

  Future<void> _loadMostrarEstoqueNoCatalogo(String lojaId) async {
    if (lojaId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyMostrarEstoqueCatalogo}_$lojaId';
      final v = prefs.getBool(key);
      if (mounted) setState(() => _mostrarEstoqueNoCatalogo = v ?? false);
    } catch (_) {}
  }

  Future<void> _loadMostrarQuantidadeNoCatalogo(String lojaId) async {
    if (lojaId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyMostrarQuantidadeCatalogo}_$lojaId';
      final v = prefs.getBool(key);
      if (mounted) setState(() => _mostrarQuantidadeNoCatalogo = v ?? false);
    } catch (_) {}
  }

  Future<void> _toggleModoEscuro(bool value) async {
    setState(() => _modoEscuro = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyModoEscuro, value);
    } catch (_) {}
  }

  /// Logo do drawer com cor configurável por tema (tema claro: logo escura; tema escuro: logo clara).
  Widget _buildDrawerLogo({
    required BuildContext context,
    required String logoUrl,
    required bool isDark,
    int? colorClaro,
    int? colorEscuro,
  }) {
    const int defaultLogoColorClaro =
        0xFF212121; // escuro para tema claro (logo branca fica visível)
    final int? tintValue =
        isDark ? colorEscuro : (colorClaro ?? defaultLogoColorClaro);
    final Widget image = Image(
      image: mpImageProvider(logoUrl),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (tintValue != null) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(Color(tintValue), BlendMode.srcIn),
        child: image,
      );
    }
    return image;
  }

  Future<void> _initConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final offline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (mounted && _isOffline != offline) {
        setState(() => _isOffline = offline);
      }
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen((results) {
        final off = results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none);
        if (mounted && _isOffline != off) {
          setState(() => _isOffline = off);
        }
      });
    } catch (_) {}
  }

  Future<void> _onRefreshProducts(String lojaId) async {
    CatalogCacheService.invalidate(lojaId, preview: widget.preview);
    setState(() => _refreshCounter++);
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> _loadRecentIds() async {
    final lid = _resolvedLojaId;
    if (lid == null || lid.isEmpty) return;
    final ids = await CatalogRecentService.getRecentIds(lid);
    if (mounted) setState(() => _recentIds = ids);
  }

  void _onProductViewed(String productId) {
    final lid = _resolvedLojaId;
    if (lid == null) return;
    CatalogRecentService.addViewed(lid, productId)
        .then((_) => _loadRecentIds());
  }

  String _normalizeProdutoKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  bool _matchesProdutoDeepLink(Map<String, dynamic> produto, String target) {
    final id = safeStr(produto['id']).trim();
    final slug = safeStr(produto['slug']).trim();
    if (id.isNotEmpty && id == target) return true;
    if (slug.isNotEmpty && slug == target) return true;
    final normalizedTarget = _normalizeProdutoKey(target);
    return (id.isNotEmpty && _normalizeProdutoKey(id) == normalizedTarget) ||
        (slug.isNotEmpty && _normalizeProdutoKey(slug) == normalizedTarget);
  }

  void _tryHandleInitialProdutoDeepLink({
    required List<Map<String, dynamic>> produtos,
    required bool useMinimalLayout,
  }) {
    if (_initialProdutoHandled) return;
    final target = _pendingInitialProdutoId?.trim();
    if (target == null || target.isEmpty) return;
    if (produtos.isEmpty) return;
    _initialProdutoHandled = true;

    final product = produtos.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p != null && _matchesProdutoDeepLink(p, target),
          orElse: () => null,
        );

    if (product == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto do link não foi encontrado.'),
            duration: Duration(seconds: 3),
          ),
        );
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = product;
      final productId = safeStr(p['id']);
      if (productId.isNotEmpty) _onProductViewed(productId);
      Map<String, int>? mapEstoque(dynamic raw) {
        if (raw is! Map) return null;
        final out = <String, int>{};
        raw.forEach((k, v) {
          final n = v is num ? v.toInt() : int.tryParse('$v');
          if (n != null && n > 0) out[k.toString()] = n;
        });
        return out.isEmpty ? null : out;
      }
      final estoqueTam = mapEstoque(p['estoquePorTamanho']);
      final estoqueCor = mapEstoque(p['estoquePorCor']);

      if (useMinimalLayout) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CatalogProductDetailScreen(
              id: productId,
              name: safeStr(p['nome'], 'Produto'),
              descricao: safeStr(p['descricao']),
              slug: safeStr(p['slug']),
              peso: safeDouble(p['peso']),
              tipoEmbalagem: safeStr(p['tipoEmbalagem'], 'padrao'),
              price: safeDouble(p['preco']),
              priceMin: p['priceMin'] != null ? safeDouble(p['priceMin']) : null,
              priceMax: p['priceMax'] != null ? safeDouble(p['priceMax']) : null,
              precoPorTamanho: (p['precoPorTamanho'] is Map)
                  ? Map<String, double>.from(
                      (p['precoPorTamanho'] as Map).map(
                        (k, v) => MapEntry(
                          k.toString(),
                          v is num ? v.toDouble() : 0.0,
                        ),
                      ),
                    )
                  : null,
              precoOriginal: p['emPromocao'] == true ? safeDouble(p['precoFinal']) : null,
              emPromocao: safeBool(p['emPromocao']),
              percentualPromo: safeDouble(p['percentualPromo']),
              valorPromo: safeDouble(p['valorPromo']),
              imagens: safeListString(p['imagens']),
              quantidade: safeInt(p['quantidade']),
              estoquePorTamanho: estoqueTam,
              estoquePorCor: estoqueCor,
              variacoes: (p['variacoes'] != null && asMapDeep(p['variacoes']).isNotEmpty)
                  ? asMapDeep(p['variacoes'])
                  : null,
              prazoEntrega: null,
              percentualDescontoPix: safeDouble(p['percentualDescontoPix']),
              divideSemJuros: safeBool(p['divideSemJuros']),
              maxParcelas: safeInt(p['maxParcelasSemJuros'], 12).clamp(1, 24),
              catalogShareUrl: CatalogShareService.buildUrlWithParams(
                '$_baseUrlCatalogo/$lojaId',
                ref: widget.vendedorRef,
                indicacao: widget.indicacaoClienteRef,
                produto: safeStr(p['slug']).isNotEmpty ? safeStr(p['slug']) : productId,
              ),
              lojaId: lojaId,
              onAdd: (it) => _addToCart(it, produtos),
              onAbrirCarrinho: null,
            ),
          ),
        );
      } else {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => CatalogProductDetailsSheet(
            name: safeStr(p['nome'], 'Produto'),
            descricao: safeStr(p['descricao']),
            price: safeDouble(p['preco']),
            priceMin: p['priceMin'] != null ? safeDouble(p['priceMin']) : null,
            priceMax: p['priceMax'] != null ? safeDouble(p['priceMax']) : null,
            precoOriginal: p['emPromocao'] == true ? safeDouble(p['precoFinal']) : null,
            emPromocao: safeBool(p['emPromocao']),
            percentualPromo: safeDouble(p['percentualPromo']),
            valorPromo: safeDouble(p['valorPromo']),
            imagens: safeListString(p['imagens']),
            quantidade: safeInt(p['quantidade']),
            estoquePorTamanho: estoqueTam,
            estoquePorCor: estoqueCor,
            variacoes: (p['variacoes'] != null && asMapDeep(p['variacoes']).isNotEmpty)
                ? asMapDeep(p['variacoes'])
                : null,
            catalogShareUrl: CatalogShareService.buildUrlWithParams(
              '$_baseUrlCatalogo/$lojaId',
              ref: widget.vendedorRef,
              indicacao: widget.indicacaoClienteRef,
              produto: safeStr(p['slug']).isNotEmpty ? safeStr(p['slug']) : productId,
            ),
            prazoEntrega: null,
            percentualDescontoPix: safeDouble(p['percentualDescontoPix']),
            itensCombo: null,
            lojaId: lojaId,
          ),
        );
      }
    });
  }

  Future<void> _loadClienteAndFavoritos() async {
    final cliente = await ClienteAuthService.getClienteLogado();
    final lojaSessao = await ClienteAuthService.getLojaId();
    final lid = _resolvedLojaId;
    if (cliente != null && lojaSessao == lid && lid != null) {
      final cid = cliente['clienteId']?.toString();
      final email = cliente['email']?.toString().trim() ?? '';
      if (mounted) {
        setState(() {
          _clienteId = cid;
          _clienteEmail = email;
        });
      }
      await _loadFavoritos();
      await _loadCarrinho();
    } else if (mounted) {
      setState(() {
        _clienteId = null;
        _clienteEmail = null;
        _favoritosIds = [];
      });
    }
  }

  Future<void> _loadCarrinho() async {
    final lid = _resolvedLojaId;
    final cid = _clienteId;
    final email = _clienteEmail ?? '';
    if (lid == null || cid == null || email.isEmpty) return;
    final items = await ClienteAuthService.getCarrinho(
      lojaId: lid,
      clienteId: cid,
      email: email,
      onFalhaCarregamento: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível carregar o carrinho. Verifique sua conexão e tente novamente.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      },
    );
    if (mounted) {
      _cart.clear();
      _cart.addAll(items);
      _ultimoPrePedidoId = null;
      _ultimoPrePedidoData = null;
      setState(() {});
    }
  }

  Future<void> _saveCarrinho() async {
    final lid = _resolvedLojaId;
    final cid = _clienteId;
    if (lid == null || cid == null) return;
    await ClienteAuthService.saveCarrinho(
        lojaId: lid, clienteId: cid, items: _cart);
  }

  /// Reseta o estado da roleta (chamado quando inicia nova compra, ex: após checkout)
  void _resetRoletaState() {
    _roletaJaGirada = false;
    _cupomRoletaCodigo = null;
    _cupomRoletaDesconto = null;
    _premioRoletaDescricao = null;
    _freteGratisRoleta = false;
  }

  Future<void> _loadFavoritos() async {
    final lid = _resolvedLojaId;
    final cid = _clienteId;
    final email = _clienteEmail ?? '';
    if (lid == null || cid == null || email.isEmpty) return;
    final ids = await ClienteAuthService.getFavoritos(
      lojaId: lid,
      clienteId: cid,
      email: email,
      onFalhaCarregamento: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível carregar favoritos. Verifique sua conexão e tente novamente.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      },
    );
    if (mounted) setState(() => _favoritosIds = ids);
  }

  void _abrirLoginParaFavorito() {
    final lojaIdAuth = _resolvedLojaId ?? widget.lojaId;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border,
                  size: 48, color: Colors.pink.shade300),
              const SizedBox(height: 16),
              const Text(
                'Entre ou cadastre-se para salvar favoritos',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LoginScreenCliente(lojaId: lojaIdAuth),
                          ),
                        ).then((_) => _loadClienteAndFavoritos());
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CadastroScreenCliente(lojaId: lojaIdAuth),
                          ),
                        ).then((_) => _loadClienteAndFavoritos());
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text('Cadastrar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFavorito(String productId) async {
    final lid = _resolvedLojaId;
    final cid = _clienteId;
    final email = _clienteEmail ?? '';
    if (lid == null || cid == null || email.isEmpty) return;
    final result = await ClienteAuthService.toggleFavorito(
      lojaId: lid,
      clienteId: cid,
      email: email,
      productId: productId,
    );
    if (mounted && result['success'] == true) {
      setState(() => _favoritosIds = safeListString(result['favoritos']));
    }
  }

  Future<void> _resolveLojaId() async {
    try {
      final widgetId = widget.lojaId.trim();

      // Link muito curto (ex: /loja/r) geralmente é incompleto ou truncado
      if (widgetId.length < 3) {
        if (mounted) {
          setState(() {
            _loadingLojaId = false;
            _resolvedLojaId = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Link do catálogo inválido ou incompleto. Use o link completo da loja.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final isPublicContext = widgetId.isNotEmpty || kIsWeb;

      if (isPublicContext) {
        // Timeout para evitar travar na tela de loading
        final result = await StoreResolverFacade.resolveForPublicCatalog(
                lojaIdFromUrl: widgetId)
            .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException(
            'O catálogo demorou muito para carregar. Verifique sua conexão e tente novamente.',
          ),
        );

        if (!result.success) {
          logD('❌ [CATÁLOGO] ${result.errorMessage}');
          setState(() {
            _loadingLojaId = false;
            _resolvedLojaId = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.errorMessage ?? 'Loja não encontrada'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Verificar se precisa de redirect
        if (result.needsRedirect && result.redirectTo != null) {
          logD(
              '🔀 [CATÁLOGO] Redirect: ${result.storeId} → ${result.redirectTo}');
        }

        setState(() {
          _resolvedLojaId = result.canonicalStoreId;
          _loadingLojaId = false;
        });
        _loadMostrarEstoqueNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _loadMostrarQuantidadeNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _loadRecentIds();
        _loadClienteAndFavoritos();
        if (!widget.preview &&
            _resolvedLojaId != null &&
            _resolvedLojaId!.isNotEmpty) {
          CatalogVisitasService.incrementarVisita(_resolvedLojaId!);
        }
        logD('✅ [CATÁLOGO] lojaId FINAL (público): $_resolvedLojaId');
      } else {
        // ════════════════════════════════════════════════════════════
        // CONTEXTO ADMIN/PREVIEW: Usa loja do usuário logado
        // Apenas para preview no app mobile
        // ════════════════════════════════════════════════════════════
        final result = await StoreResolverFacade.resolveForAdminDashboard(
                lojaIdFromUrl: widgetId)
            .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException(
            'O catálogo demorou muito para carregar. Verifique sua conexão e tente novamente.',
          ),
        );

        if (!result.success) {
          logD('❌ [CATÁLOGO] ${result.errorMessage}');
          throw StateError(result.errorMessage ?? 'Nenhuma loja configurada');
        }

        if (result.needsRedirect && result.redirectTo != null) {
          logD(
              '🔀 [CATÁLOGO] Redirect: ${result.storeId} → ${result.redirectTo}');
        }

        setState(() {
          _resolvedLojaId = result.canonicalStoreId ?? result.storeId;
          _loadingLojaId = false;
        });
        _loadMostrarEstoqueNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _loadMostrarQuantidadeNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _loadRecentIds();
        _loadClienteAndFavoritos();
        if (!widget.preview &&
            _resolvedLojaId != null &&
            _resolvedLojaId!.isNotEmpty) {
          CatalogVisitasService.incrementarVisita(_resolvedLojaId!);
        }
        logD('✅ [CATÁLOGO] lojaId FINAL (admin): $_resolvedLojaId');
      }

      logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      logD('❌ Erro ao resolver lojaId (type=${e.runtimeType})');
      if (mounted) {
        setState(() {
          _loadingLojaId = false;
          _resolvedLojaId = null;
        });
        final msg = e is TimeoutException
            ? (e.message ?? 'Tempo esgotado. Tente novamente.')
            : 'Erro ao carregar: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  String get lojaId {
    if (_resolvedLojaId == null || _resolvedLojaId!.isEmpty) {
      throw StateError('lojaId ainda não foi resolvido');
    }
    return _resolvedLojaId!;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _mostrarIndicarAmigoSheet(BuildContext context,
      {required String lojaId, required String clienteId}) {
    final link = '$_baseUrlCatalogo/$lojaId?indicacao=$clienteId';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.card_giftcard,
                      color: _successColor, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Indicar amigo',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Quando seu amigo comprar pelo link abaixo, você e ele ganham um cupom de desconto. Seu cupom será ativado quando ele usar o cupom dele na primeira compra.',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    SelectableText(link, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link));
                        Navigator.pop(ctx);
                        _snack('Link copiado! Compartilhe com seu amigo.');
                      },
                      icon: const Icon(Icons.copy, size: 20),
                      label: const Text('Copiar link'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final uri = Uri.parse(
                          'https://wa.me/?text=${Uri.encodeComponent('Confira o catálogo e compre com desconto: $link')}',
                        );
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('Enviar no WhatsApp'),
                      style: FilledButton.styleFrom(
                          backgroundColor: _successColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removeFromCart(int index) {
    if (index < 0 || index >= _cart.length) return;
    setState(() {
      _cart.removeAt(index);
      _ultimoPrePedidoId = null;
      _ultimoPrePedidoData = null;
    });
    _saveCarrinho();
  }

  void _addToCart(
    Map<String, dynamic> item,
    List<Map<String, dynamic>> catalogProducts,
  ) {
    if (kDebugMode) {
      logD(
          '📦 [_addToCart] Item: ${item['nome']} tam:${item['tamanho']} cor:${item['cor']}');
    }

    final id = '${item['id'] ?? item['produtosId'] ?? ''}';
    final tam = (item['tamanho'] ?? '').toString().trim();
    final cor = (item['cor'] ?? '').toString().trim();
    final addQty = CatalogEstoqueHelper.parseCartItemQuantidade(item['quantidade']);
    final comboRaw = item['itensComboComSelecao'];
    final isComboLine =
        comboRaw is List && comboRaw.isNotEmpty;

    if (!isComboLine && id.isNotEmpty) {
      final p = CatalogEstoqueHelper.findProductInList(catalogProducts, id);
      if (p != null) {
        final avail =
            CatalogEstoqueHelper.estoqueDisponivelVariacao(p, tam, cor);
        final lineKey = CatalogEstoqueHelper.cartLineIdentity(item);
        var already = 0;
        for (final e in _cart) {
          if (CatalogEstoqueHelper.cartLineIdentity(e) == lineKey) {
            already +=
                CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
          }
        }
        if (already + addQty > avail) {
          _snack(avail <= 0
              ? 'Produto esgotado nesta variação.'
              : 'Estoque insuficiente. Disponível: $avail un.');
          return;
        }
      }
    }

    setState(() {
      final key = CatalogEstoqueHelper.cartLineIdentity(item);
      final idx = _cart.indexWhere(
          (e) => CatalogEstoqueHelper.cartLineIdentity(e) == key);
      if (idx >= 0) {
        final cur =
            CatalogEstoqueHelper.parseCartItemQuantidade(_cart[idx]['quantidade']);
        _cart[idx]['quantidade'] = cur + addQty;
      } else {
        final copy = Map<String, dynamic>.from(item);
        copy['quantidade'] = addQty;
        _cart.add(copy);
      }
      _ultimoPrePedidoId = null;
      _ultimoPrePedidoData = null;
    });
    _saveCarrinho();
  }

  // Flag para evitar spam de log de permission-denied
  static bool _cfgPermissionDeniedLogged = false;
  static bool _produtosPermissionDeniedLogged = false;

  Stream<Map<String, dynamic>> _cfgStream(String lojaId) {
    final db = FirebaseFirestore.instance;
    final baseRef = db.collection('lojas').doc(lojaId);

    final String cfgCol = widget.preview ? 'draft_config' : 'config';
    final configRef = baseRef.collection(cfgCol).doc('config');
    final paymentsRef = baseRef.collection(cfgCol).doc('payments');

    logD('═══════════════════════════════════════════════════════════');
    logD('🔥 [CATÁLOGO] CONFIGURAÇÃO');
    logD('   Loja: $lojaId');
    logD(
        '   Modo: ${widget.preview ? "PREVIEW (rascunho)" : "PRODUÇÃO (publicado)"}');
    logD('   Caminho: lojas/$lojaId/$cfgCol/config');
    logD(
        '   ⚠️  Se cores estão erradas, verifique se configuração foi PUBLICADA!');
    logD('═══════════════════════════════════════════════════════════');

    final controller = StreamController<Map<String, dynamic>>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;

    void startListening() {
      subscription = configRef.snapshots().listen(
        (cfgSnap) async {
          _cfgPermissionDeniedLogged = false;
          final cfg = asMapDeep(cfgSnap.data() ?? {});

          try {
            final paySnap = await paymentsRef.get();
            if (paySnap.exists) {
              cfg['payments'] = asMapDeep(paySnap.data());
            }
          } catch (_) {}

          // Fallback: carregar cupons da collection se config vazio (sincronização FretesCuponsScreen)
          final cuponsCfg = cfg['cupons'];
          final cuponsListCfg = cuponsCfg is List ? cuponsCfg : null;
          if (cuponsListCfg == null || cuponsListCfg.isEmpty) {
            try {
              final cuponsSnap = await FirebaseFirestore.instance
                  .collection('lojas')
                  .doc(lojaId)
                  .collection('cupons')
                  .where('ativo', isEqualTo: true)
                  .get()
                  .timeout(const Duration(seconds: 3));
              final cuponsList = <Map<String, dynamic>>[];
              final now = DateTime.now();
              for (final doc in cuponsSnap.docs) {
                final d = asMapDeep(doc.data());
                final cod = (d['codigo'] ?? d['code'] ?? '')
                    .toString()
                    .toUpperCase()
                    .trim();
                if (cod.isEmpty) continue;
                final dataFim = d['dataFim'];
                if (dataFim != null) {
                  final fim = dataFim is Timestamp ? dataFim.toDate() : null;
                  if (fim != null && now.isAfter(fim)) continue;
                }
                final tipoRaw =
                    (d['tipo'] ?? 'percent').toString().toLowerCase();
                final tipoNorm = tipoRaw == 'valor' || tipoRaw == 'fixo'
                    ? 'valor'
                    : tipoRaw.contains('frete')
                        ? 'frete_gratis'
                        : 'percent';
                cuponsList.add({
                  'codigo': cod,
                  'tipo': tipoNorm,
                  'ativo': true,
                  'valor': safeDouble(d['valor']),
                  'aplicarEm': (d['aplicarEm'] ?? 'produtos').toString(),
                  'freteGratis': d['freteGratis'] == true,
                  'valorMinimo': d['valorMinimo'] == null
                      ? null
                      : safeDouble(d['valorMinimo']),
                  'dataFim': dataFim,
                  'validade': d['validade'],
                  'dataValidade': d['dataValidade'],
                });
              }
              if (cuponsList.isNotEmpty) {
                cfg['cupons'] = cuponsList;
                logD(
                    '✅ [CATÁLOGO] Cupons carregados da collection: ${cuponsList.length}');
              }
            } catch (e) {
              logD(
                  '⚠️ [CATÁLOGO] Fallback cupons collection (type=${e.runtimeType})');
            }
          }

          controller.add(cfg);
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            if (!_cfgPermissionDeniedLogged) {
              _cfgPermissionDeniedLogged = true;
              logD('⚠️ [CATÁLOGO] Sem permissão para config - usando padrões');
            }
            // Retorna config vazio para UI usar padrões
            controller.add(<String, dynamic>{});
            subscription?.cancel();
          } else {
            logD(
                '❌ [CATÁLOGO] Erro no stream de config (type=${error.runtimeType})');
            controller.add(<String, dynamic>{});
          }
        },
        cancelOnError: false,
      );
    }

    controller.onListen = startListening;
    controller.onCancel = () => subscription?.cancel();

    return controller.stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _produtosStream(String lojaId) {
    final col = widget.preview ? kDraftProdutosCol : kLiveProdutosCol;

    logD('📦 [CATÁLOGO] produtos: lojas/$lojaId/$col');

    // Filtro apenas por ativo - demais filtros serão aplicados no código
    // (evita necessidade de índice composto no Firestore)
    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    void startListening() {
      subscription = FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection(col)
          .where('ativo', isEqualTo: true)
          .limit(1000)
          .snapshots()
          .listen(
        (snapshot) {
          _produtosPermissionDeniedLogged = false;
          controller.add(snapshot);
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            if (!_produtosPermissionDeniedLogged) {
              _produtosPermissionDeniedLogged = true;
              logD(
                  '⚠️ [CATÁLOGO] Sem permissão para produtos - catálogo vazio');
            }
            subscription?.cancel();
          } else {
            logD(
                '❌ [CATÁLOGO] Erro no stream de produtos (type=${error.runtimeType})');
          }
        },
        cancelOnError: false,
      );
    }

    controller.onListen = startListening;
    controller.onCancel = () => subscription?.cancel();

    return controller.stream;
  }

  Future<void> _mostrarDialogoFiltroPreco(Color textColor) async {
    final minCtrl =
        TextEditingController(text: _precoMin?.toStringAsFixed(2) ?? '');
    final maxCtrl =
        TextEditingController(text: _precoMax?.toStringAsFixed(2) ?? '');
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faixa de preço'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço mínimo (R\$)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: maxCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço máximo (R\$)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              minCtrl.clear();
              maxCtrl.clear();
              Navigator.pop(context);
              setState(() {
                _precoMin = null;
                _precoMax = null;
                _currentPageNotifier.value = 0;
              });
            },
            child: const Text('Limpar'),
          ),
          ElevatedButton(
            onPressed: () {
              final min =
                  double.tryParse(minCtrl.text.replaceAll(',', '.').trim());
              final max =
                  double.tryParse(maxCtrl.text.replaceAll(',', '.').trim());
              Navigator.pop(context);
              setState(() {
                _precoMin = min;
                _precoMax = max;
                _currentPageNotifier.value = 0;
              });
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  Future<void> publicarCatalogo() async {
    if (_publicando) return;
    setState(() => _publicando = true);

    try {
      final lojaDoc =
          FirebaseFirestore.instance.collection('lojas').doc(lojaId);

      final draftRef = lojaDoc.collection(kDraftProdutosCol);
      final liveRef = lojaDoc.collection(kLiveProdutosCol);

      final draftSnap = await draftRef.get();
      if (draftSnap.docs.isEmpty) {
        _snack('Rascunho vazio. Nada para publicar.');
        return;
      }

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int ops = 0;

      Future<void> commitIfNeeded() async {
        if (ops == 0) return;
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }

      for (final d in draftSnap.docs) {
        final data = asMapDeep(d.data());

        data['ativo'] = (data['ativo'] ?? true) == true;
        data['publishedAt'] = FieldValue.serverTimestamp();
        data['updatedAt'] = FieldValue.serverTimestamp();

        final liveDoc = liveRef.doc(d.id);
        batch.set(liveDoc, data, SetOptions(merge: true));
        ops++;

        if (ops >= 450) {
          await commitIfNeeded();
        }
      }

      await commitIfNeeded();

      await lojaDoc.collection('config').doc('config').set({
        'catalog_published_at': FieldValue.serverTimestamp(),
        'catalog_source': 'draft',
      }, SetOptions(merge: true));

      final draftCfgRef = lojaDoc.collection('draft_config').doc('config');
      final liveCfgRef = lojaDoc.collection('config').doc('config');

      final draftCfgSnap = await draftCfgRef.get();
      if (draftCfgSnap.exists) {
        await liveCfgRef.set(
            asMapDeep(draftCfgSnap.data() ?? {}), SetOptions(merge: true));
      }

      final draftPayRef = lojaDoc.collection('draft_config').doc('payments');
      final livePayRef = lojaDoc.collection('config').doc('payments');

      final draftPaySnap = await draftPayRef.get();
      if (draftPaySnap.exists) {
        await livePayRef.set(
            asMapDeep(draftPaySnap.data() ?? {}), SetOptions(merge: true));
      }

      _snack('Catálogo publicado com sucesso!');
    } catch (e) {
      _snack('Erro ao publicar: $e');
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _openCartSheet({
    required List<Map<String, dynamic>> fretes,
    required List<Map<String, dynamic>> cupons,
    required Color primary,
    required Color buttonText,
    required Color textColor,
    required Color cardColor,
    required Color? checkoutCardColor,
    required Color? checkoutFieldBg,
    required Color? checkoutFieldBorder,
    required Color? checkoutFieldTextColor,
    required Color? checkoutLabelColor,
    required Color? checkoutTotalColor,
    required Color? productNameColor,
    required Color? productPriceColor,
    required String whatsappVendedor,
    required String lojaNome,
    required Map<String, String> paymentAsset,
    required List<String> paymentCodes,
    required String instagramUrl,
    required String facebookUrl,
    required String empresaRazao,
    required String empresaCnpj,
    required String checkoutGateway,
    required String checkoutButtonLabel,
    required String pixKey,
    required String freightToken,
  }) async {
    if (_cart.isEmpty) {
      _snack('Seu carrinho está vazio.');
      return;
    }

    // Carregar dados do formulário salvos anteriormente (persistência ao sair/voltar)
    Map<String, dynamic>? initialFormData;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'catalog_cart_form_$lojaId';
      final json = prefs.getString(key);
      if (json != null && json.isNotEmpty) {
        initialFormData = Map<String, dynamic>.from(jsonDecode(json) as Map);
      }
    } catch (_) {}

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.only(top: 24),
          decoration: BoxDecoration(
            color: cardColor, // ✅ Usa cor do card configurada
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: CarrinhoSheetWeb(
            lojaId: lojaId,
            items: _cart,
            fretes: fretes,
            cupons: cupons,
            initialFormData: initialFormData,
            onFormDataToSave: (data) {
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString('catalog_cart_form_$lojaId', jsonEncode(data));
              });
            },
            initialRoletaJaGirada: _roletaJaGirada,
            initialCupomRoletaCodigo: _cupomRoletaCodigo,
            initialCupomRoletaDesconto: _cupomRoletaDesconto,
            initialPremioRoletaDescricao: _premioRoletaDescricao,
            initialFreteGratisRoleta: _freteGratisRoleta,
            onRoletaPremioGanho: ({
              required bool jaGirada,
              String? codigo,
              double? desconto,
              String? descricao,
              required bool freteGratis,
            }) {
              if (!mounted) return;
              setState(() {
                _roletaJaGirada = jaGirada;
                _cupomRoletaCodigo = codigo;
                _cupomRoletaDesconto = desconto;
                _premioRoletaDescricao = descricao;
                _freteGratisRoleta = freteGratis;
              });
            },
            primary: primary,
            buttonText: buttonText,
            textColor: textColor,
            cardColor: cardColor,
            checkoutCardColor: checkoutCardColor,
            checkoutFieldBg: checkoutFieldBg,
            checkoutFieldBorder: checkoutFieldBorder,
            checkoutFieldTextColor: checkoutFieldTextColor,
            checkoutLabelColor: checkoutLabelColor,
            checkoutTotalColor: checkoutTotalColor,
            productNameColor: productNameColor,
            productPriceColor: productPriceColor,
            checkoutGateway: checkoutGateway,
            checkoutButtonLabel: checkoutButtonLabel,
            pixKey: pixKey,
            freightToken: freightToken,
            onRemove: _removeFromCart,
            showSnack: _snack,
            onCheckoutPix:
                (checkoutGateway == 'pix' || checkoutGateway == 'whatsapp') &&
                        pixKey.trim().isNotEmpty
                    ? ({
                        required Map<String, dynamic> customer,
                        required Map<String, dynamic> entrega,
                        required double valorTotal,
                        String observacao = '',
                        String? cupomRoletaCodigo,
                        double? cupomRoletaDesconto,
                        String? premioRoletaDescricao,
                        void Function(String message)? showErrorInCart,
                      }) async {
                        void showErr(String msg) {
                          if (showErrorInCart != null) {
                            showErrorInCart(msg);
                          } else {
                            ScaffoldMessenger.of(Navigator.of(ctx).context)
                                .showSnackBar(SnackBar(content: Text(msg)));
                          }
                        }

                        String? vendaId;
                        try {
                          vendaId =
                              await CatalogoVendaService.registrarVendaCatalogo(
                            lojaId: lojaId,
                            customer: customer,
                            items: _cart,
                            entrega: entrega,
                            pagamento: 'PIX',
                            observacao: observacao,
                            cupomCodigo: null,
                            desconto: 0.0,
                            cupomRoletaCodigo: cupomRoletaCodigo,
                            cupomRoletaDesconto: cupomRoletaDesconto,
                            premioRoletaDescricao: premioRoletaDescricao,
                          );
                        } catch (e) {
                          logD(
                              '❌ Erro ao registrar venda PIX (type=${e.runtimeType})');
                          if (!ctx.mounted) return;
                          showErr('Erro ao criar pedido. Tente novamente.');
                          return;
                        }
                        final payload = gerarPixCopiaECola(
                          chavePix: pixKey,
                          valor: valorTotal,
                          nomeRecebedor: 'LOJA',
                          cidadeRecebedor: 'BRASIL',
                          txid: vendaId ?? '***',
                        );
                        if (ctx.mounted) {
                          setState(() {
                            _cart.clear();
                            _resetRoletaState();
                          });
                          _saveCarrinho();
                          showPixQrDialog(
                            context: ctx,
                            pixPayload: payload,
                            valor: valorTotal,
                            pedidoId: vendaId,
                          );
                          if (showErrorInCart == null) {
                            if (!ctx.mounted) return;
                            // ignore: use_build_context_synchronously
                            final messenger =
                                ScaffoldMessenger.of(Navigator.of(ctx).context);
                            messenger.showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Escaneie o QR Code ou copie o código para pagar.')),
                            );
                          }
                        }
                      }
                    : null,
            onCheckoutWhatsapp: ({
              required Map<String, dynamic> customer,
              required Map<String, dynamic> entrega,
              required String pagamento,
              String observacao = '',
              String? cupomRoletaCodigo,
              double? cupomRoletaDesconto,
              String? premioRoletaDescricao,
              Future<void> Function(String? pedidoId)? onSuccess,
              void Function(String message)? showErrorInCart,
            }) async {
              void showErr(String msg) {
                if (showErrorInCart != null) {
                  showErrorInCart(msg);
                } else {
                  _snack(msg);
                }
              }

              try {
                // ✨ Reutilizar pré-pedido se já foi criado (ex.: após erro em outra forma de pagamento)
                Map<String, dynamic>? prePedido;
                if (_ultimoPrePedidoId != null &&
                    _ultimoPrePedidoData != null) {
                  prePedido = _ultimoPrePedidoData;
                  logD(
                      '📦 [PRE-PEDIDO] Reutilizando pedido existente: $_ultimoPrePedidoId');
                } else {
                  try {
                    logD('📦 [PRE-PEDIDO] Criando para loja: $lojaId');
                    final clienteLogado =
                        await ClienteAuthService.getClienteLogado();

                    prePedido = await PrePedidoService.criarPrePedido(
                      lojaId: lojaId,
                      customer: customer,
                      items: _cart,
                      entrega: entrega,
                      pagamento: pagamento,
                      observacao: observacao,
                      cupomCodigo: null,
                      desconto: 0.0,
                      cupomRoletaCodigo: cupomRoletaCodigo,
                      cupomRoletaDesconto: cupomRoletaDesconto,
                      premioRoletaDescricao: premioRoletaDescricao,
                      vendedorRef: widget.vendedorRef,
                      indicacaoClienteId: widget.indicacaoClienteRef,
                      clienteId: clienteLogado?['clienteId']?.toString(),
                      origemCheckout: 'whatsapp',
                    );

                    if (prePedido == null) {
                      showErr('Erro ao criar pedido. Tente novamente.');
                      return;
                    }
                    if (mounted) {
                      setState(() {
                        _ultimoPrePedidoId = prePedido!['id']?.toString();
                        _ultimoPrePedidoData = prePedido;
                      });
                    }
                    logD('✅ [PRE-PEDIDO] Criado com ID: ${prePedido['id']}');
                  } catch (e) {
                    logD('❌ Erro ao criar pré-pedido (type=${e.runtimeType})');
                    showErr('Erro ao criar pedido. Tente novamente.');
                    return;
                  }
                }

                final prePedidoVal = prePedido;
                if (prePedidoVal == null) {
                  showErr('Erro ao criar pedido. Tente novamente.');
                  return;
                }

                // ✨ Buscar slug da loja para gerar link correto
                String? lojaSlug;
                try {
                  final lojaDoc = await FirebaseFirestore.instance
                      .collection('lojas')
                      .doc(lojaId)
                      .get();
                  if (lojaDoc.exists) {
                    lojaSlug =
                        asMap(lojaDoc.data())['slug']?.toString() ?? lojaId;
                  }
                } catch (e) {
                  logD(
                      '⚠️ Erro ao buscar slug da loja (type=${e.runtimeType})');
                  lojaSlug = lojaId;
                }

                // ✨ Formatar mensagem usando o serviço
                final msg = PrePedidoService.formatarParaWhatsApp(
                  prePedido: prePedidoVal,
                  lojaId: lojaId, // ✅ Usa lojaId resolvido
                  baseUrl: 'https://app.mastepalm.com.br',
                  lojaSlug: lojaSlug, // ✅ Passa slug para gerar link correto
                );

                // ⭐ GERAR CUPOM E NÚMERO DA SORTE
                final prePedidoId = prePedidoVal['id']?.toString();
                try {
                  final cliente = await ClienteAuthService.getClienteLogado();
                  if (cliente != null &&
                      prePedidoId != null &&
                      prePedidoId.isNotEmpty) {
                    logD('🎁 Gerando cupom e número da sorte...');

                    final total = prePedidoVal['total'] ?? 0.0;

                    final requestBody = {
                      'lojaId': lojaId,
                      'clienteId': cliente['clienteId'],
                      'pedidoId': prePedidoId,
                      'valorPedido': total,
                      'clienteEmail':
                          cliente['email'] ?? customer['email'] ?? '',
                      'clienteNome': cliente['nome'] ?? customer['nome'] ?? '',
                      'clienteTelefone': customer['telefone'] ?? '',
                    };

                    logD('📤 [CUPOM] Enviando requisição para Cloud Function:');
                    logD('   (request body com lojaId/clienteId)');
                    logD('   pedidoId: ${requestBody['pedidoId']}');
                    logD('   valorPedido: ${requestBody['valorPedido']}');
                    logD('   clienteEmail: ${requestBody['clienteEmail']}');
                    logD('   clienteNome: ${requestBody['clienteNome']}');
                    logD(
                        '   clienteTelefone: ${requestBody['clienteTelefone']}');

                    final response = await HttpClientHelper.post(
                      Uri.parse(
                          'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/gerarCupomNumeroSorte'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode(requestBody),
                      timeout: HttpTimeouts.cloudFunction,
                    );

                    logD('📥 [CUPOM] Status Code: ${response.statusCode}');
                    logD('📥 [CUPOM] Response Body: ${response.body}');

                    if (response.statusCode == 200) {
                      try {
                        final data = asMap(json.decode(response.body));
                        final cupom = asMap(data['cupom']);
                        final cupomCodigo = cupom['codigo']?.toString() ?? '';
                        final cupomDesconto =
                            cupom['desconto']?.toString() ?? '0';
                        final cupomValidade =
                            cupom['validade']?.toString() ?? '';
                        final numeroSorte =
                            data['numeroSorte']?.toString() ?? '';

                        logD('✅ Cupom: $cupomCodigo');
                        logD('✅ Número da sorte: $numeroSorte');

                        final cupomMsg = '\n\n🎁 *Parabéns!*\n\n'
                            'Você ganhou um cupom de $cupomDesconto% de desconto:\n'
                            '📌 *$cupomCodigo*\n'
                            '${cupomValidade.isNotEmpty ? 'Válido até $cupomValidade\n\n' : ''}'
                            '🎰 *Seu número da sorte:* $numeroSorte\n'
                            'Boa sorte! 🍀';

                        await _openWhatsappSimple(
                            whatsappVendedor, msg + cupomMsg);
                        if (mounted) {
                          setState(() {
                            _cart.clear();
                            _resetRoletaState();
                            _ultimoPrePedidoId = null;
                            _ultimoPrePedidoData = null;
                          });
                        }
                        _saveCarrinho();
                        await onSuccess?.call(prePedidoVal['id']?.toString());
                        return;
                      } catch (e) {
                        logD('Erro ao processar cupom (type=${e.runtimeType})');
                      }
                    } else {
                      logD('❌ [CUPOM] Erro HTTP ${response.statusCode}');
                      logD('   Response: ${response.body}');
                    }
                  }
                } catch (e, stackTrace) {
                  logD('❌ Erro ao gerar cupom/número (type=${e.runtimeType})');
                  logD('   Stack: $stackTrace');
                  // Continuar mesmo se houver erro
                }

                if (whatsappVendedor.trim().isEmpty) {
                  showErr('WhatsApp do vendedor não configurado.');
                  return;
                }

                await _openWhatsappSimple(whatsappVendedor, msg);
                if (mounted) {
                  setState(() {
                    _cart.clear();
                    _resetRoletaState();
                    _ultimoPrePedidoId = null;
                    _ultimoPrePedidoData = null;
                  });
                }
                _saveCarrinho();
                await onSuccess?.call(prePedidoVal['id']?.toString());
              } catch (e, st) {
                logD('❌ Erro no checkout WhatsApp (type=${e.runtimeType})');
                logD('   Stack: $st');
                showErr('Erro ao processar. Tente novamente.');
              }
            },
            onCheckoutMercadoPago: ({
              required Map<String, dynamic> customer,
              required Map<String, dynamic> entrega,
              required String pagamento,
              String observacao = '',
              String? cupomRoletaCodigo,
              double? cupomRoletaDesconto,
              String? premioRoletaDescricao,
              void Function(String message)? showErrorInCart,
            }) async {
              // Erros devem aparecer na tela do carrinho (não no catálogo)
              void showErr(String msg) {
                if (showErrorInCart != null) {
                  showErrorInCart(msg);
                } else {
                  ScaffoldMessenger.of(Navigator.of(context).context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              }

              // ✨ Reutilizar pré-pedido se já foi criado (evita vários pedidos ao trocar forma de pagamento)
              String? pedidoId = _ultimoPrePedidoId;
              if (pedidoId == null) {
                try {
                  logD(
                      '💳 [MERCADO-PAGO] Criando pré-pedido para loja: $lojaId');
                  final cliente = await ClienteAuthService.getClienteLogado();
                  final prePedido = await PrePedidoService.criarPrePedido(
                    lojaId: lojaId,
                    customer: customer,
                    items: _cart,
                    clienteId: cliente?['clienteId']?.toString(),
                    entrega: entrega,
                    pagamento: 'Mercado Pago',
                    observacao: observacao,
                    cupomCodigo: null,
                    desconto: 0.0,
                    cupomRoletaCodigo: cupomRoletaCodigo,
                    cupomRoletaDesconto: cupomRoletaDesconto,
                    premioRoletaDescricao: premioRoletaDescricao,
                    vendedorRef: widget.vendedorRef,
                    indicacaoClienteId: widget.indicacaoClienteRef,
                  );
                  pedidoId = prePedido?['id']?.toString();
                  if (pedidoId != null && mounted) {
                    setState(() {
                      _ultimoPrePedidoId = pedidoId;
                      _ultimoPrePedidoData = prePedido;
                    });
                    logD(
                        '✅ Pré-pedido criado (aguardando pagamento): $pedidoId');
                  } else {
                    logD('⚠️ Falha ao criar pré-pedido');
                    showErr('Erro ao criar pedido. Tente novamente.');
                    return;
                  }
                } catch (e) {
                  logD('❌ Erro ao criar pré-pedido (type=${e.runtimeType})');
                  showErr('Erro ao criar pedido. Tente novamente.');
                  return;
                }
              } else {
                logD('💳 [MERCADO-PAGO] Reutilizando pré-pedido: $pedidoId');
              }

              try {
                // Calcular valor total
                final subtotal = _cart.fold<double>(
                  0.0,
                  (s, e) {
                    final price = safeDouble(e['preco']);
                    final qty = safeInt(e['quantidade'], 1);
                    return s + price * qty;
                  },
                );

                final valorFrete = safeDouble(entrega['valor']);
                final valorTotal = subtotal + valorFrete;
                final isPix = pagamento.toUpperCase() == 'PIX';
                int? maxInstallmentsSemJuros;
                if (!isPix) {
                  final limites = _cart
                      .where((e) => e['divideSemJuros'] == true)
                      .map((e) => safeInt(e['maxParcelasSemJuros'], 12))
                      .where((v) => v > 0)
                      .toList();
                  if (limites.isNotEmpty) {
                    // Quando há produtos com sem juros, respeita o menor limite entre eles.
                    limites.sort();
                    maxInstallmentsSemJuros = limites.first.clamp(1, 24);
                  }
                }

                logD(
                    '💰 Criando pagamento - Valor total: R\$ ${valorTotal.toStringAsFixed(2)}');
                Map<String, dynamic>? paymentData;

                // Na WEB: usar Cloud Function (evita CORS ao chamar api.mercadopago.com)
                if (kIsWeb) {
                  try {
                    final body = <String, dynamic>{
                      'lojaId': lojaId,
                      'type': isPix ? 'pix' : 'preference',
                      if (isPix) ...{
                        'valor': valorTotal,
                        'descricao': 'Pedido #$pedidoId',
                        'email': customer['email']?.toString(),
                        'cpf': customer['cpf']?.toString(),
                        'externalReference': pedidoId,
                      } else ...{
                        'titulo': 'Pedido #$pedidoId',
                        'valor': valorTotal,
                        'quantidade': 1,
                        'descricao': 'Compra em $lojaId',
                        'externalReference': pedidoId,
                        'payer': customer['email'] != null
                            ? {'email': customer['email'].toString()}
                            : null,
                        if (maxInstallmentsSemJuros != null)
                          'maxInstallments': maxInstallmentsSemJuros,
                        if (maxInstallmentsSemJuros != null)
                          'paymentMethods': {
                            'installments': maxInstallmentsSemJuros,
                          },
                        'backUrls': {
                          'success':
                              'https://app.mastepalm.com.br/pagamento/sucesso?loja=$lojaId',
                          'failure':
                              'https://app.mastepalm.com.br/pagamento/falha?loja=$lojaId',
                          'pending':
                              'https://app.mastepalm.com.br/pagamento/pendente?loja=$lojaId',
                        },
                      },
                    };
                    final response = await HttpClientHelper.post(
                      Uri.parse(kMpCatalogPaymentUrl),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(body),
                      timeout: HttpTimeouts.payment,
                    );
                    if (response.statusCode >= 200 &&
                        response.statusCode < 300) {
                      final data = asMap(jsonDecode(response.body));
                      paymentData = data;
                    } else {
                      String errMsg =
                          'Erro ao criar pagamento no Mercado Pago. Tente novamente.';
                      if (response.body.isNotEmpty) {
                        try {
                          final errJson = asMap(jsonDecode(response.body));
                          if (errJson['error'] != null) {
                            errMsg = errJson['error'].toString();
                            if (errMsg.toLowerCase().contains('bad_request') ||
                                errMsg == 'bad_request') {
                              errMsg =
                                  'Dados inválidos para PIX. Verifique e-mail e CPF e tente novamente.';
                            }
                          }
                        } catch (_) {}
                      }
                      showErr(errMsg);
                      return;
                    }
                  } catch (e) {
                    logD('❌ [WEB] mpCatalogPayment (type=${e.runtimeType})');
                    showErr(
                        'Erro ao criar pagamento no Mercado Pago. Tente novamente.');
                    return;
                  }
                } else {
                  // APK/App: chamada direta à API; em falha usa Cloud Function (fallback)
                  try {
                    final configDoc = await FirebaseFirestore.instance
                        .collection('lojas')
                        .doc(lojaId)
                        .collection('config')
                        .doc('payments')
                        .get();

                    if (!configDoc.exists) {
                      showErr('Configurações de pagamento não encontradas.');
                      return;
                    }

                    final config = asMapDeep(configDoc.data() ?? {});
                    final mp = asMap(config['mp']);
                    final accessToken = mp['access_token'] ?? mp['token'];

                    if (accessToken == null || accessToken.toString().isEmpty) {
                      showErr(
                          'Access Token do Mercado Pago não configurado. Configure em Ajustes > Pagamentos.');
                      return;
                    }

                    if (isPix) {
                      logD('💳 Gerando PIX...');
                      paymentData = await MercadoPagoService.criarPagamentoPix(
                        accessToken: accessToken.toString(),
                        valor: valorTotal,
                        descricao: 'Pedido #$pedidoId',
                        email: customer['email']?.toString(),
                        cpf: customer['cpf']?.toString(),
                        externalReference: pedidoId,
                      );
                    } else {
                      logD('💳 Criando checkout para cartão...');
                      const baseUrl = 'https://app.mastepalm.com.br';
                      paymentData = await MercadoPagoService.criarPreferencia(
                        accessToken: accessToken.toString(),
                        titulo: 'Pedido #$pedidoId',
                        valor: valorTotal,
                        quantidade: 1,
                        descricao: 'Compra em $lojaId',
                        externalReference: pedidoId,
                        payer: customer['email'] != null
                            ? {'email': customer['email'].toString()}
                            : null,
                        maxInstallments: maxInstallmentsSemJuros,
                        backUrls: {
                          'success': '$baseUrl/pagamento/sucesso?loja=$lojaId',
                          'failure': '$baseUrl/pagamento/falha?loja=$lojaId',
                          'pending': '$baseUrl/pagamento/pendente?loja=$lojaId',
                        },
                      );
                    }
                  } catch (e) {
                    logD(
                        '❌ [APK] Mercado Pago direto falhou, usando Cloud Function (type=${e.runtimeType})');
                    paymentData = null;
                  }
                  // Fallback APK: usar proxy (mesma URL da web) se chamada direta falhou
                  if (paymentData == null) {
                    try {
                      final body = <String, dynamic>{
                        'lojaId': lojaId,
                        'type': isPix ? 'pix' : 'preference',
                        if (isPix) ...{
                          'valor': valorTotal,
                          'descricao': 'Pedido #$pedidoId',
                          'email': customer['email']?.toString(),
                          'cpf': customer['cpf']?.toString(),
                          'externalReference': pedidoId,
                        } else ...{
                          'titulo': 'Pedido #$pedidoId',
                          'valor': valorTotal,
                          'quantidade': 1,
                          'descricao': 'Compra em $lojaId',
                          'externalReference': pedidoId,
                          'payer': customer['email'] != null
                              ? {'email': customer['email'].toString()}
                              : null,
                          if (maxInstallmentsSemJuros != null)
                            'maxInstallments': maxInstallmentsSemJuros,
                          if (maxInstallmentsSemJuros != null)
                            'paymentMethods': {
                              'installments': maxInstallmentsSemJuros,
                            },
                          'backUrls': {
                            'success':
                                'https://app.mastepalm.com.br/pagamento/sucesso?loja=$lojaId',
                            'failure':
                                'https://app.mastepalm.com.br/pagamento/falha?loja=$lojaId',
                            'pending':
                                'https://app.mastepalm.com.br/pagamento/pendente?loja=$lojaId',
                          },
                        },
                      };
                      final response = await HttpClientHelper.post(
                        Uri.parse(kMpCatalogPaymentUrl),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode(body),
                        timeout: HttpTimeouts.payment,
                      );
                      if (response.statusCode >= 200 &&
                          response.statusCode < 300) {
                        final data = asMap(jsonDecode(response.body));
                        paymentData = data;
                      }
                    } catch (e2) {
                      logD(
                          '❌ [APK] Fallback mpCatalogPayment (type=${e2.runtimeType})');
                    }
                  }
                }

                if (paymentData == null) {
                  showErr(
                      'Erro ao criar pagamento no Mercado Pago. Tente novamente.');
                  return;
                }

                logD('✅ Pagamento criado: $paymentData');

                // Cupom/número da sorte em background (não bloqueia abertura do checkout)
                unawaited(_gerarCupomNumeroSorteBackground(
                  lojaId: lojaId,
                  pedidoId: pedidoId,
                  valorTotal: valorTotal,
                  customer: customer,
                ));

                // Obter QR Code ou URL de pagamento primeiro (para abrir o quanto antes)
                final qrCode = paymentData['qr_code']?.toString();
                final ticketUrl = paymentData['ticket_url']?.toString();
                final initPoint = paymentData['init_point']?.toString();

                // Se tiver init_point (checkout), abrir
                if (initPoint != null && initPoint.isNotEmpty) {
                  final uri = Uri.tryParse(initPoint);
                  if (uri != null) {
                    if (mounted) {
                      setState(() {
                        _cart.clear();
                        _resetRoletaState();
                        _ultimoPrePedidoId = null;
                        _ultimoPrePedidoData = null;
                      });
                    }
                    _saveCarrinho();
                    final ok = await _launchPaymentUrl(uri);
                    if (!mounted) return;
                    if (!ok) {
                      showErr('Não foi possível abrir o link de pagamento.');
                    } else if (showErrorInCart == null) {
                      ScaffoldMessenger.of(Navigator.of(context).context)
                          .showSnackBar(
                        const SnackBar(
                            content:
                                Text('Pagamento criado! Abrindo checkout...')),
                      );
                    }
                    return;
                  }
                }

                // Se tiver ticket_url (PIX direto), abrir
                if (ticketUrl != null && ticketUrl.isNotEmpty) {
                  final uri = Uri.tryParse(ticketUrl);
                  if (uri != null) {
                    if (mounted) {
                      setState(() {
                        _cart.clear();
                        _resetRoletaState();
                        _ultimoPrePedidoId = null;
                        _ultimoPrePedidoData = null;
                      });
                    }
                    _saveCarrinho();
                    final ok = await _launchPaymentUrl(uri);
                    if (!mounted) return;
                    if (!ok) {
                      showErr('Não foi possível abrir o comprovante PIX.');
                    } else if (showErrorInCart == null) {
                      ScaffoldMessenger.of(Navigator.of(context).context)
                          .showSnackBar(
                        const SnackBar(
                            content:
                                Text('PIX gerado! Abrindo comprovante...')),
                      );
                    }
                    return;
                  }
                }

                // Se tiver QR Code, mostrar dialog PIX
                if (qrCode != null && qrCode.isNotEmpty) {
                  if (mounted) {
                    setState(() {
                      _cart.clear();
                      _resetRoletaState();
                      _ultimoPrePedidoId = null;
                      _ultimoPrePedidoData = null;
                    });
                  }
                  _saveCarrinho();
                  if (!mounted) return;
                  if (showErrorInCart == null) {
                    ScaffoldMessenger.of(Navigator.of(context).context)
                        .showSnackBar(
                      const SnackBar(
                          content: Text(
                              'PIX gerado! Escaneie o QR Code para pagar.')),
                    );
                  }

                  // 🔔 O webhook processará a confirmação: pagamento concluído e novo pedido recebido
                  if (!ctx.mounted) return;
                  final scaffoldContext = Navigator.of(ctx).context;
                  if (scaffoldContext.mounted) {
                    showPixQrDialog(
                      context: scaffoldContext,
                      pixPayload: qrCode,
                      valor: valorTotal,
                      pedidoId: pedidoId,
                    );
                  }
                  return;
                }

                showErr('Pagamento criado, mas sem dados de QR Code.');
              } catch (e) {
                logD('❌ Erro ao processar pagamento (type=${e.runtimeType})');
                showErr('Erro ao processar pagamento: $e');
              }
            },
          ),
        );
      },
    );
  }

  /// Abre URL de pagamento (checkout MP, PIX etc.). Na web (ex.: Safari iPhone)
  /// usa mesma aba para evitar bloqueio de popup; no app usa aplicativo externo.
  Future<bool> _launchPaymentUrl(Uri uri) async {
    if (kIsWeb) {
      return launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Abre URL externa (Instagram, Facebook, etc.)
  Future<void> _openUrl(String url) async {
    if (url.trim().isEmpty) return;
    String finalUrl = url.trim();
    if (finalUrl.startsWith('@')) {
      final username = finalUrl.substring(1).split(RegExp(r'[\s/]')).first;
      if (username.isNotEmpty) {
        finalUrl = 'https://www.instagram.com/$username/';
        if (!kIsWeb && await openInstagramInApp(finalUrl)) return;
      }
    } else if (!finalUrl.startsWith('http://') &&
        !finalUrl.startsWith('https://')) {
      finalUrl = 'https://$finalUrl';
    }
    if (!kIsWeb && await openInstagramInApp(finalUrl)) return;
    final facebookMatch = RegExp(
      r'(?:https?://)?(?:www\.)?(?:m\.)?facebook\.com/([a-zA-Z0-9.]+)',
      caseSensitive: false,
    ).firstMatch(finalUrl);
    if (facebookMatch != null && !kIsWeb) {
      final pageId = facebookMatch.group(1);
      if (pageId != null &&
          pageId.isNotEmpty &&
          !_isFacebookReservedPath(pageId)) {
        final nativeUri = Uri.parse('fb://profile/$pageId');
        if (await canLaunchUrl(nativeUri)) {
          if (await launchUrl(nativeUri,
              mode: LaunchMode.externalApplication)) {
            return;
          }
        }
      }
    }
    final uri = Uri.tryParse(finalUrl);
    if (uri == null) {
      _snack('Link inválido.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Não foi possível abrir o link.');
    }
  }

  bool _isFacebookReservedPath(String path) {
    const reserved = [
      'watch',
      'gaming',
      'marketplace',
      'groups',
      'events',
      'pages',
      'home',
      'login',
      'admin'
    ];
    return reserved.contains(path.toLowerCase());
  }

  /// Gera cupom e número da sorte em background (não bloqueia o checkout)
  Future<void> _gerarCupomNumeroSorteBackground({
    required String lojaId,
    required String pedidoId,
    required double valorTotal,
    required Map<String, dynamic> customer,
  }) async {
    try {
      final clienteLogado = await ClienteAuthService.getClienteLogado();
      if (clienteLogado == null) return;
      final response = await HttpClientHelper.post(
        Uri.parse(
            'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/gerarCupomNumeroSorte'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'lojaId': lojaId,
          'clienteId': clienteLogado['clienteId'],
          'pedidoId': pedidoId,
          'valorPedido': valorTotal,
          'clienteEmail': clienteLogado['email'] ?? customer['email'] ?? '',
          'clienteNome': clienteLogado['nome'] ?? customer['nome'] ?? '',
          'clienteTelefone': customer['telefone'] ?? '',
        }),
        timeout: HttpTimeouts.cloudFunction,
      );
      if (response.statusCode == 200) {
        logD('✅ Cupom e número da sorte gerados em background');
      }
    } catch (e) {
      logD(
          '❌ Erro ao gerar cupom/número em background (type=${e.runtimeType})');
    }
  }

  Future<void> _openWhatsappSimple(String telefone, String msg) async {
    if (telefone.trim().isEmpty) return;
    final phone = telefone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length < 10) {
      _snack('Número de WhatsApp inválido. Digite pelo menos 10 dígitos.');
      return;
    }
    try {
      final url = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(msg.trim())}',
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      logD('❌ Erro ao abrir WhatsApp (type=${e.runtimeType})');
      _snack('Não foi possível abrir o WhatsApp. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = _modoEscuro ? ThemeData.dark() : ThemeData.light();
    // Usar tema do contexto (ex.: web) para loading/erro, evitando tela branca
    final themeForStates = Theme.of(context);
    if (_loadingLojaId) {
      return CatalogLoadingState(themeData: themeForStates);
    }

    if (_resolvedLojaId == null || _resolvedLojaId!.isEmpty) {
      return CatalogErrorLojaState(themeData: themeForStates);
    }

    if (kDebugMode) {
      logD('📱 [CATALOG] Renderizando loja: $_resolvedLojaId');
    }

    return Theme(
      data: themeData,
      child: StreamBuilder<Map<String, dynamic>>(
        stream: _getConfigStream(lojaId),
        builder: (context, cfgSnap) {
          // Usar tema do MaterialApp (themeForStates) para evitar tela branca na web
          if (cfgSnap.connectionState == ConnectionState.waiting) {
            return CatalogConfigLoadingState(themeData: themeForStates);
          }
          if (!cfgSnap.hasData) {
            return CatalogConfigErrorState(themeData: themeForStates);
          }

          final Map<String, dynamic> cfg =
              (cfgSnap.data ?? {}).map((k, v) => MapEntry(k.toString(), v));

          if (kDebugMode) {
            logD('📄 [CATÁLOGO] Config carregado: ${cfg.keys.length} chaves');
          }

          final whatsappVendedor =
              (cfg['whatsapp_vendedor'] ?? cfg['whatsapp'] ?? '').toString();

          // ✅ WhatsApp do rodapé: usa rodape['whatsapp'] quando configurado (sincronizado com Loja Config)
          final rodapeForWhatsapp = mpMapDyn(cfg['rodape']);
          final whatsappRodape =
              (rodapeForWhatsapp['whatsapp'] ?? '').toString().trim();
          final atendimentoWhatsapp =
              whatsappRodape.isNotEmpty ? whatsappRodape : whatsappVendedor;

          // =================== CONFIGURAÇÕES DE LAYOUT ===================
          final cardShowShadow = safeBool(cfg['cardShowShadow'], true);
          final cardBorderRadius = safeDouble(cfg['cardBorderRadius'], 18.0);
          final gridDesktopCols =
              safeInt(cfg['gridDesktopCols'], 4).clamp(2, 6);
          final gridMobileCols = safeInt(cfg['gridMobileCols'], 2).clamp(1, 4);

          // =================== CORES ===================
          // ✅ CORRIGIDO: Lê de 'theme' e 'checkoutTheme' (mesma estrutura do LojaConfig)
          final themeRaw = cfg['theme'];
          final themeMap = (themeRaw is Map
              ? themeRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{});

          final checkoutThemeRaw = cfg['checkoutTheme'];
          final checkoutThemeMap = (checkoutThemeRaw is Map
              ? checkoutThemeRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{});

          // ✅ NOVO: Lê de 'uiColors' (cores unificadas expandidas)
          final uiColorsRaw = cfg['uiColors'];
          final uiColorsMap = (uiColorsRaw is Map
              ? uiColorsRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{});

          // ✅ NOVO: Lê de 'catalogHeaderColors' (cores do cabeçalho)
          final headerColorsRaw = cfg['catalogHeaderColors'];
          final headerColorsMap = (headerColorsRaw is Map
              ? headerColorsRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{});

          // ✅ NOVO: Lê de 'catalogFooterColors' (cores do rodapé)
          final footerColorsRaw = cfg['catalogFooterColors'];
          final footerColorsMap = (footerColorsRaw is Map
              ? footerColorsRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{});

          // ✅ NOVO: Lê de 'catalogDicasColors' (cores da tela Dicas)
          final dicasColorsRaw = cfg['catalogDicasColors'];
          final dicasColorsMap = (dicasColorsRaw is Map
              ? dicasColorsRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{});

          Color colorFromTheme(String key, Color fallback) {
            final dynamic raw = themeMap[key];
            return readColorFromCfg(raw) ?? fallback;
          }

          Color colorFromCheckoutTheme(String key, Color fallback) {
            final dynamic raw = checkoutThemeMap[key];
            return readColorFromCfg(raw) ?? fallback;
          }

          Color colorFromUiColors(String key, Color fallback) {
            final dynamic raw = uiColorsMap[key];
            return readColorFromCfg(raw) ?? fallback;
          }

          Color colorFromHeaderColors(String key, Color fallback) {
            final dynamic raw = headerColorsMap[key];
            return readColorFromCfg(raw) ?? fallback;
          }

          Color colorFromFooterColors(String key, Color fallback) {
            final dynamic raw = footerColorsMap[key];
            return readColorFromCfg(raw) ?? fallback;
          }

          Color colorFromDicasColors(String key, Color fallback) {
            final dynamic raw = dicasColorsMap[key];
            return readColorFromCfg(raw) ?? fallback;
          }

          // ===== Tema geral (cards e produtos) =====
          // Prioriza uiColors > theme > fallback
          final primaryColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors('buttonPrimaryBg',
                  colorFromTheme('primaria', const Color(0xFF22C55E)))
              : colorFromTheme('primaria', const Color(0xFF22C55E));
          final bgColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors('background',
                  colorFromTheme('fundo', const Color(0xFF020617)))
              : colorFromTheme('fundo', const Color(0xFF020617));
          final cardColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors('cardBackground',
                  colorFromTheme('card', const Color(0xFF020617)))
              : colorFromTheme('card', const Color(0xFF020617));
          final textColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors('textPrimary',
                  colorFromTheme(
                      'texto', Colors.white.withValues(alpha: 0.95)))
              : colorFromTheme(
                  'texto', Colors.white.withValues(alpha: 0.95));
          final btnTextColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors('buttonPrimaryText',
                  colorFromTheme('botaoTexto', Colors.white))
              : colorFromTheme('botaoTexto', Colors.white);

          final cardTextPrimary =
              colorFromUiColors('cardTextPrimary', Colors.white);
          final priceHighlightColor =
              colorFromUiColors('priceHighlight', const Color(0xFF4ADE80));
          final buttonSecondaryBg =
              colorFromUiColors('buttonSecondaryBg', Colors.transparent);
          final buttonSecondaryText =
              colorFromUiColors('buttonSecondaryText', primaryColor);

          // ===== Cor do cabeçalho (separada do fundo geral) =====
          final headerColor = headerColorsMap.isNotEmpty
              ? colorFromHeaderColors(
                  'background', colorFromTheme('cabecalho', bgColor))
              : colorFromTheme('cabecalho', bgColor);
          final headerTextColor = colorFromHeaderColors('text', Colors.white);
          final headerIconColor = colorFromHeaderColors('icon', Colors.white);
          final headerSearchBg =
              colorFromHeaderColors('searchBackground', Colors.white10);
          final headerSearchText =
              colorFromHeaderColors('searchText', Colors.white);
          final headerSearchHint =
              colorFromHeaderColors('searchHint', Colors.white70);

          // ===== Cores do rodapé =====
          final footerBgColor = colorFromFooterColors('background', bgColor);
          final footerTextColor = colorFromFooterColors('text', Colors.white);
          final footerTextSecondary =
              colorFromFooterColors('textSecondary', Colors.white70);
          final footerIconColor = colorFromFooterColors('icon', Colors.white70);
          final footerLinkColor = colorFromFooterColors('link', primaryColor);
          final footerDividerColor =
              colorFromFooterColors('divider', Colors.white24);

          // ===== Cores da tela Dicas e Informações =====
          CatalogDicasColors? catalogDicasColors;
          if (dicasColorsMap.isNotEmpty) {
            catalogDicasColors = CatalogDicasColors(
              background:
                  colorFromDicasColors('background', const Color(0xFFF8F9FA)),
              footerBackground:
                  colorFromDicasColors('footerBackground', Colors.white),
              footerText: colorFromDicasColors('footerText', Colors.black87),
              buttonBackground: colorFromDicasColors(
                  'buttonBackground', const Color(0xFF22C55E)),
              buttonText: colorFromDicasColors('buttonText', Colors.white),
              topicPrimary:
                  colorFromDicasColors('topicPrimary', const Color(0xFF22C55E)),
            );
          }

          if (kDebugMode && themeMap.isEmpty && uiColorsMap.isEmpty) {
            logD(
                '⚠️ [CATÁLOGO] cfg["theme"] e cfg["uiColors"] vazios, usando padrão');
          }

          // ===== Cores do checkout / carrinho =====
          // Prioriza uiColors > checkoutTheme > fallback
          final checkoutCardColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors(
                  'cardBackground', colorFromCheckoutTheme('card', cardColor))
              : colorFromCheckoutTheme('card', cardColor);

          final checkoutFieldBg = uiColorsMap.isNotEmpty
              ? colorFromUiColors('fieldBackground',
                  colorFromCheckoutTheme('campo', const Color(0xFF0F172A)))
              : colorFromCheckoutTheme('campo', const Color(0xFF0F172A));

          final checkoutFieldTextColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors(
                  'fieldText', colorFromCheckoutTheme('texto', textColor))
              : colorFromCheckoutTheme('texto', textColor);

          final checkoutLabelColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors(
                  'labelText', colorFromCheckoutTheme('label', textColor))
              : colorFromCheckoutTheme('label', textColor);

          final checkoutTotalColor = uiColorsMap.isNotEmpty
              ? colorFromUiColors('priceHighlight',
                  colorFromCheckoutTheme('total', const Color(0xFF22C55E)))
              : colorFromCheckoutTheme('total', const Color(0xFF22C55E));
          final checkoutFieldBorder = uiColorsMap.isNotEmpty
              ? colorFromUiColors('fieldBorder', Colors.white.withValues(alpha: 0.25))
              : Colors.white.withValues(alpha: 0.25);

          // ===== Cores de nome e preço do produto =====
          final productNameColor = cardTextPrimary;
          final productPriceColor = priceHighlightColor;

          // =================== IDENTIDADE / LINKS ===================
          final lojaNome = (cfg['nomeLoja'] ??
                  cfg['nome_loja'] ??
                  cfg['nome'] ?? // ✅ CORRIGIDO: adiciona 'nome'
                  cfg['name'] ??
                  'Minha Loja')
              .toString()
              .trim();

          final links = mpMapDyn(cfg['links']);
          final rodapeLinks = mpMapDyn(cfg['rodape']);

          final instagramUrl =
              (rodapeLinks['instagram'] ?? links['instagram'] ?? '').toString();
          final facebookUrl =
              (rodapeLinks['facebook'] ?? links['facebook'] ?? '').toString();
          final tiktokUrl = (rodapeLinks['tiktok'] ?? '').toString();
          final telegramUrl = (rodapeLinks['telegram'] ?? '').toString();
          final kwaiUrl = (rodapeLinks['kwai'] ?? '').toString();
          final linkedinUrl = (rodapeLinks['linkedin'] ?? '').toString();
          final emailUrl = (rodapeLinks['email'] ?? '').toString();
          final whatsappUrl = (rodapeLinks['whatsapp'] ?? '').toString();
          final sobreUrl =
              (rodapeLinks['sobre'] ?? links['sobre'] ?? '').toString();
          final trocasUrl =
              (rodapeLinks['trocas'] ?? links['trocas'] ?? '').toString();
          final loginUrl =
              (rodapeLinks['login'] ?? links['login'] ?? '').toString();

          final empresa = asMap(cfg['empresa']);
          final empresaRazao =
              (rodapeLinks['razao'] ?? empresa['razao'] ?? '').toString();
          final empresaCnpj =
              (rodapeLinks['cnpj'] ?? empresa['cnpj'] ?? '').toString();

          // ✅ CORRIGIDO: Token de frete unificado
          final freightToken = (cfg['melhorEnvioToken'] ??
                  cfg['correiosUser'] ??
                  cfg['frenetToken'] ??
                  cfg['frete_token'] ??
                  cfg['freight_token'] ??
                  cfg['freightToken'] ??
                  '')
              .toString()
              .trim();

          // ✅ CORRIGIDO: Lê payments de 'rodape' (onde o LojaConfig salva)
          final rodapeRaw = cfg['rodape'];
          final rodapeMap = rodapeRaw is Map
              ? rodapeRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};

          final paymentsFromRodape = rodapeMap['payments'];
          final paymentCodes = <String>[
            if (paymentsFromRodape is List)
              ...paymentsFromRodape.map((e) => e.toString()),
          ];

          final paymentAssets = <String, String>{
            'visa': 'assets/payments/visa.png',
            'mastercard': 'assets/payments/mastercard.png',
            'hipercard': 'assets/payments/hipercard.png',
            'elo': 'assets/payments/elo.png',
            'amex': 'assets/payments/amex.png',
            'diners': 'assets/payments/diners.png',
            'pix': 'assets/payments/pix.png',
            'boleto': 'assets/payments/boleto.png',
            'transfer': 'assets/payments/transfer.png',
            'barcode': 'assets/payments/barcode.png',
          };

          // =================== CHECKOUT / GATEWAY ===================
          final checkoutCfg = resolveCheckoutCfgFromData(cfg);

          logD('[PUBLIC] checkoutCfg = $checkoutCfg');

          final Map<String, dynamic> checkoutInner =
              mpMapDyn(checkoutCfg['checkout']);

          String normalizeGateway(dynamic v) {
            final s = v?.toString().toLowerCase().trim() ?? '';
            if (s.isEmpty) return '';
            final compact = s.replaceAll(RegExp(r'[\s_-]+'), '');
            if (compact.contains('mercadopago') || compact == 'mp') {
              return 'mp';
            }
            if (compact.contains('pagseguro') || compact == 'ps') {
              return 'pagseguro';
            }
            if (compact.contains('ton')) {
              return 'ton';
            }
            if (compact.contains('infinitepay') ||
                compact.contains('infinite')) {
              return 'infinitepay';
            }
            if (compact.contains('whatsapp') || compact == 'zap') {
              return 'whatsapp';
            }
            return s;
          }

          String readGateway() {
            dynamic g = checkoutInner['gateway'] ??
                checkoutInner['gatewayPadrao'] ??
                checkoutInner['principal'] ??
                checkoutInner['principalGateway'] ??
                checkoutInner['gatewayPrincipal'];

            g ??= checkoutCfg['gateway'] ??
                checkoutCfg['gatewayPadrao'] ??
                checkoutCfg['principalGateway'] ??
                checkoutCfg['gateway_default'] ??
                cfg['checkoutGateway'] ??
                cfg['gateway'] ??
                cfg['gatewayPadrao'];

            String s = normalizeGateway(g);
            if (s.isEmpty) s = 'mp';
            return s;
          }

          final safeGateway = readGateway();

          // Por enquanto apenas Mercado Pago ativo; outras gateways inativadas
          String checkoutGateway;
          switch (safeGateway) {
            case 'mp':
            case 'mercadopago':
            case 'mercado_pago':
              checkoutGateway = 'mp';
              break;
            case 'pagseguro':
            case 'ps':
            case 'ton':
            case 'infinitepay':
            case 'pix':
            case 'pix_manual':
              // Gateways inativadas temporariamente – usar apenas Mercado Pago
              checkoutGateway = 'mp';
              break;
            case 'whatsapp':
              checkoutGateway = 'whatsapp';
              break;
            default:
              checkoutGateway = 'mp';
          }

          String extractPixKey() {
            String? fromCheckout = (checkoutInner['pixKey'] ??
                    checkoutInner['chavePix'] ??
                    checkoutInner['pix_chave'] ??
                    checkoutInner['pix_key'])
                ?.toString()
                .trim();

            if (fromCheckout != null && fromCheckout.isNotEmpty) {
              return fromCheckout;
            }

            fromCheckout = (checkoutCfg['pixKey'] ??
                    checkoutCfg['chavePix'] ??
                    checkoutCfg['pix_chave'] ??
                    checkoutCfg['pix_key'])
                ?.toString()
                .trim();

            if (fromCheckout != null && fromCheckout.isNotEmpty) {
              return fromCheckout;
            }

            // tenta em um bloco "pix" aninhado
            final pixRaw = checkoutCfg['pix'];
            if (pixRaw is Map) {
              final pixMap = pixRaw.map((k, v) => MapEntry(k.toString(), v));
              final nested = (pixMap['key'] ??
                      pixMap['chave'] ??
                      pixMap['chavePix'] ??
                      pixMap['pixKey'])
                  ?.toString()
                  .trim();
              if (nested != null && nested.isNotEmpty) {
                return nested;
              }
            }

            // último fallback: campos soltos na config raiz
            final fromRoot = (cfg['pixKey'] ??
                    cfg['chavePix'] ??
                    cfg['pix_chave'] ??
                    cfg['pix_key'])
                ?.toString()
                .trim();

            return fromRoot ?? '';
          }

          final pixKey = extractPixKey();

          if (kDebugMode) {
            logD('[PUBLIC] gateway = $checkoutGateway');
          }

          // ===== LABEL DO BOTÃO DE CHECKOUT =====
          String checkoutButtonLabel;

          switch (checkoutGateway) {
            case 'mp':
              checkoutButtonLabel = 'Pagar com Mercado Pago';
              break;
            case 'pagseguro':
              checkoutButtonLabel = 'Pagar com PagSeguro';
              break;
            case 'ton':
              checkoutButtonLabel = 'Pagar com TON';
              break;
            case 'infinitepay':
              checkoutButtonLabel = 'Pagar com InfinitePay';
              break;
            case 'pix':
              checkoutButtonLabel = 'Pagar com PIX';
              break;
            default:
              checkoutButtonLabel = 'Finalizar pedido';
          }

          // Juros de parcelamento (percentual ao mês, ex: 1.99 para Mercado Pago)
          final jurosRaw = checkoutInner['jurosParcelamento'] ??
              checkoutCfg['jurosParcelamento'] ??
              cfg['jurosParcelamento'];
          final jurosParcelamento = (jurosRaw is num)
              ? jurosRaw.toDouble()
              : (double.tryParse(jurosRaw?.toString() ?? '') ?? 1.99);

          final maxParcelasRaw = checkoutInner['maxParcelas'] ??
              checkoutCfg['maxParcelas'] ??
              cfg['maxParcelas'];
          final maxParcelas = (maxParcelasRaw is int)
              ? maxParcelasRaw
              : (int.tryParse(maxParcelasRaw?.toString() ?? '') ?? 12);
          final maxParcelasClamped = maxParcelas.clamp(1, 24);

          // =================== FRETES, CUPONS, MÍDIA ===================
          final fretes = parseFretes(cfg);
          final cupons = parseCupons(cfg);

          final size = MediaQuery.of(context).size;
          final isWide = size.width >= 900;
          final mediaConfig = parseMedia(cfg, isWide: isWide);
          final logoUrl = mediaConfig.logoUrl;
          final banners = mediaConfig.banners;
          final bannerH = mediaConfig.bannerH;
          return Theme(
            data: Theme.of(context).copyWith(
              scaffoldBackgroundColor: bgColor,
              colorScheme: ColorScheme.fromSeed(
                seedColor: primaryColor,
                brightness: _modoEscuro ? Brightness.dark : Brightness.light,
                primary: primaryColor,
                surface: cardColor,
              ),
              cardColor: cardColor,
              textTheme: Theme.of(context).textTheme.apply(
                    bodyColor: textColor,
                    displayColor: textColor,
                  ),
              extensions: [
                ...Theme.of(context)
                    .extensions
                    .values
                    .where((e) => e.runtimeType != CatalogThemeExtension),
                CatalogThemeExtension(
                  productNameColor: productNameColor,
                  productPriceColor: productPriceColor,
                  buttonComprarBg: primaryColor,
                  buttonComprarText: btnTextColor,
                  buttonVerBg: buttonSecondaryBg,
                  buttonVerText: buttonSecondaryText,
                  chipFilterSelectedBg: primaryColor,
                  chipFilterSelectedText: btnTextColor,
                ),
              ],
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey('produtos_${lojaId}_$_refreshCounter'),
              stream: _getProdutosStream(lojaId),
              builder: (context, prodSnap) {
                if (prodSnap.hasError) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 64, color: Colors.red.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'Erro ao carregar produtos',
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${prodSnap.error}',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => _onRefreshProducts(lojaId),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final docs = prodSnap.hasData && prodSnap.data != null
                    ? prodSnap.data!.docs
                    : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                final produtos = docs.isEmpty
                    ? <Map<String, dynamic>>[]
                    : _processDocsToProducts(docs);

                const badgeSSL = 'assets/badges/ssl.png';
                const badgeGoogle = 'assets/badges/google-safe-browsing.png';

                final footerLinks = <Map<String, String>>[
                  if (sobreUrl.isNotEmpty)
                    {'label': 'Sobre a loja', 'url': sobreUrl},
                  if (trocasUrl.isNotEmpty)
                    {'label': 'Trocas e devoluções', 'url': trocasUrl},
                  if (loginUrl.isNotEmpty)
                    {'label': 'Área do cliente', 'url': loginUrl},
                ];

                // Prazo de entrega (primeiro frete com prazo preenchido)
                String prazoEntregaTexto = 'Conforme opção no checkout';
                for (final f in fretes) {
                  final p = (f['prazo'] ?? '').toString().trim();
                  if (p.isNotEmpty) {
                    prazoEntregaTexto = p;
                    break;
                  }
                }

                // FAQ e links institucionais (opcionais no config)
                List<Map<String, String>> faqItems = [];
                if (cfg['faq'] is List) {
                  for (final e in asList(cfg['faq'])) {
                    if (e is Map) {
                      final m = Map<String, String>.from(e.map((k, v) =>
                          MapEntry(k.toString(), v?.toString() ?? '')));
                      if ((m['pergunta'] ?? '').trim().isNotEmpty) {
                        faqItems.add(m);
                      }
                    }
                  }
                }
                if (faqItems.isEmpty) {
                  faqItems = [
                    {
                      'pergunta': 'Qual o prazo de entrega?',
                      'resposta':
                          'O prazo varia conforme sua região e a opção de frete escolhida no checkout. Consulte as opções disponíveis no carrinho.'
                    },
                    {
                      'pergunta': 'Como funciona a troca ou devolução?',
                      'resposta':
                          'Entre em contato pelo WhatsApp para solicitar troca ou devolução. Guarde o produto na embalagem original.'
                    },
                    {
                      'pergunta': 'Quais formas de pagamento são aceitas?',
                      'resposta':
                          'Aceitamos PIX, cartão de crédito e outras formas conforme indicado no checkout. Entre em contato para dúvidas.'
                    },
                  ];
                }
                final politicaPrivacidadeUrl = (cfg['politicaPrivacidadeUrl'] ??
                        cfg['politica_privacidade_url'] ??
                        '')
                    .toString()
                    .trim();
                final termosUsoUrl =
                    (cfg['termosUsoUrl'] ?? cfg['termos_uso_url'] ?? '')
                        .toString()
                        .trim();

                // 🔢 qtde de itens no carrinho (para badge do ícone)
                final cartCount = _cart.fold<int>(
                    0,
                    (s, e) =>
                        s +
                        CatalogEstoqueHelper.parseCartItemQuantidade(
                            e['quantidade']));

                final layoutCatalogo =
                    (cfg['layoutCatalogo'] ?? cfg['layout_catalogo'] ?? 'padrao')
                        .toString()
                        .trim()
                        .toLowerCase();
                final bool useMinimalLayout =
                    layoutCatalogo == 'minimalista_nuvemshop';
                _tryHandleInitialProdutoDeepLink(
                  produtos: produtos,
                  useMinimalLayout: useMinimalLayout,
                );
                final promoBarCfg = mpMapDyn(cfg['promoBar']);
                final minimalSearchCfg = mpMapDyn(cfg['minimalSearch']);
                final categoryVisualsCfg = mpMapDyn(cfg['categoryVisuals']);
                final heroBannerCfg = mpMapDyn(cfg['heroBanner']);
                final minimalGridCfg = mpMapDyn(cfg['minimalProductGrid']);
                final productCardSize = CatalogProductCardSize.normalize(
                  cfg['productCardSize'],
                );
                final minimalBestSellersCfg =
                    mpMapDyn(cfg['minimalBestSellers']);
                final bestSellersSectionEnabled = safeBool(
                    minimalBestSellersCfg['enabled'], true);
                final bestSellersTitle =
                    (minimalBestSellersCfg['title'] ?? 'Mais vendidos')
                        .toString();
                final bestSellersLimit = safeInt(
                    minimalBestSellersCfg['count'], 10)
                    .clamp(3, 24);

                TextAlign parseTextAlign(dynamic raw, TextAlign fallback) {
                  final v = (raw ?? '').toString().trim().toLowerCase();
                  switch (v) {
                    case 'left':
                      return TextAlign.left;
                    case 'right':
                      return TextAlign.right;
                    case 'center':
                      return TextAlign.center;
                    case 'justify':
                      return TextAlign.justify;
                    default:
                      return fallback;
                  }
                }

                // Mostrar quantidade / estoque no catálogo (Firestore > prefs)
                final mostrarQuantidadeNoCatalogo =
                    cfg['mostrarQuantidadeNoCatalogo'] as bool? ??
                        _mostrarQuantidadeNoCatalogo;
                final mostrarEstoqueNoCatalogo =
                    cfg['mostrarEstoqueNoCatalogo'] as bool? ??
                        _mostrarEstoqueNoCatalogo;

                // categorias únicas para o menu lateral
                // Compatibilidade: lê tanto 'categoria' quanto 'categoriaId'
                final categoriasSet = <String>{};
                final categoryAliasesByName = <String, Set<String>>{};
                for (final p in produtos) {
                  final c = (p['categoria'] ?? p['categoriaId'] ?? '')
                      .toString()
                      .trim();
                  if (c.isNotEmpty) {
                    categoriasSet.add(c);
                    final aliases = categoryAliasesByName.putIfAbsent(c, () => <String>{});
                    final cid = (p['categoriaId'] ?? '').toString().trim();
                    if (cid.isNotEmpty) aliases.add(cid);
                    aliases.add(c.toLowerCase());
                  }
                }
                final categoriasMenu = categoriasSet.toList()..sort();

                // =================== MENU & PÁGINAS ===================
                // Lê configurações do menu (quais itens mostrar/ocultar)
                final menuRaw = cfg['menu'];
                final menuMap = menuRaw is Map
                    ? menuRaw.map((k, v) => MapEntry(k.toString(), v))
                    : <String, dynamic>{};

                final menuShowCategorias =
                    safeBool(menuMap['categorias'], true);
                final menuShowEntrar = safeBool(menuMap['entrar'], true);
                final menuShowContato = safeBool(menuMap['contato'], true);
                final menuShowSac = safeBool(menuMap['sac'], true);
                final menuShowQuemSomos = safeBool(menuMap['quemSomos'], true);
                final menuShowDicas = safeBool(menuMap['dicas'], true);
                final indicacaoRaw = cfg['indicacao'];
                final indicacaoAtivo =
                    indicacaoRaw is Map && (indicacaoRaw['ativo'] == true);

                // DEBUG: Ver se está lendo as configurações do menu
                logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                logD('📋 [MENU CONFIG] Configurações do menu:');
                logD('   menuRaw existe: ${menuRaw != null}');
                logD('   menuMap: $menuMap');
                logD('   Categorias: $menuShowCategorias');
                logD('   Entrar: $menuShowEntrar');
                logD('   Contato: $menuShowContato');
                logD('   SAC: $menuShowSac');
                logD('   Quem Somos: $menuShowQuemSomos');
                logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

                // Lê dados da página "Quem Somos"
                final quemSomosRaw = cfg['quemSomos'];
                final quemSomosMap = quemSomosRaw is Map
                    ? quemSomosRaw.map((k, v) => MapEntry(k.toString(), v))
                    : <String, dynamic>{};

                final quemSomosTitulo =
                    (quemSomosMap['titulo'] ?? 'Quem somos').toString();
                final quemSomosTexto = (quemSomosMap['texto'] ??
                        cfg['quem_somos'] ??
                        cfg['sobre_texto'] ??
                        '')
                    .toString();

                // Lê dados do SAC
                final sacRaw = cfg['sac'];
                final sacMap = sacRaw is Map
                    ? sacRaw.map((k, v) => MapEntry(k.toString(), v))
                    : <String, dynamic>{};

                final sacWhatsapp =
                    (sacMap['whatsapp'] ?? whatsappVendedor).toString();

                // Lista de dicas (cuidados, garantias, qualidade etc.) – só ativas com título
                final dicasRaw = cfg['dicas'];
                final dicasList = <DicaItem>[];
                if (dicasRaw is List) {
                  for (final e in dicasRaw) {
                    if (e is! Map) continue;
                    final d = DicaItem.fromMap(Map<String, dynamic>.from(
                        e.map((k, v) => MapEntry(k.toString(), v))));
                    if (d.ativo && d.titulo.trim().isNotEmpty) dicasList.add(d);
                  }
                }

                final w = MediaQuery.of(context).size.width;
                final isDesktop = w >= 1024;

                // Link direto: ?page=dicas abre a página de dicas ao carregar
                if (widget.initialPage == 'dicas' && !_openedInitialPage) {
                  _openedInitialPage = true;
                  final contact = DicasContactInfo(
                    whatsappNumber: atendimentoWhatsapp,
                    instagramUrl: instagramUrl.isNotEmpty ? instagramUrl : null,
                    facebookUrl: facebookUrl.isNotEmpty ? facebookUrl : null,
                  );
                  final dicasW = MediaQuery.of(context).size.width;
                  final dicasIsWide = dicasW >= 900;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CatalogDicasScreen(
                          lojaId: _resolvedLojaId ?? widget.lojaId,
                          lojaNome: lojaNome,
                          dicas: dicasList,
                          primaryColor: primaryColor,
                          logoUrl: logoUrl.isNotEmpty ? logoUrl : null,
                          logoHeight: dicasIsWide ? 90 : 80,
                          bannerHeightCard: mediaConfig.bannerH * 0.65,
                          bannerHeightDetail: mediaConfig.bannerH * 0.85,
                          dicasColors: catalogDicasColors,
                          contactInfo: contact,
                        ),
                      ),
                    );
                  });
                }

                return Scaffold(
                  // ================= DRAWER =================
                  drawer: Drawer(
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // topo com logo (fixo) – cor configurável para tema claro/escuro
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Row(
                              children: [
                                if (logoUrl.isNotEmpty)
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: _buildDrawerLogo(
                                        context: context,
                                        logoUrl: logoUrl,
                                        isDark: _modoEscuro,
                                        colorClaro: mediaConfig.logoColorClaro,
                                        colorEscuro:
                                            mediaConfig.logoColorEscuro,
                                      ),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: Text(
                                      lojaNome,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: _modoEscuro
                                            ? headerTextColor
                                            : textColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Conteúdo rolável (evita overflow com muitas categorias)
                          Expanded(
                            child: ListView(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              children: [
                                // HOME
                                ListTile(
                                  leading: const Icon(Icons.home_outlined),
                                  title: const Text('Home'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _searchController.clear();
                                    _searchNotifier.value = '';
                                    setState(() {
                                      _selectedCategory = null;
                                      _selectedSubcategory = null;
                                      _currentPageNotifier.value = 0;
                                    });
                                  },
                                ),

                                // PRODUTOS (sem filtro, mostra todos)
                                ListTile(
                                  leading: const Icon(Icons.grid_view_outlined),
                                  title: const Text('Produtos'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    setState(() {
                                      _selectedCategory = null;
                                      _selectedSubcategory = null;
                                      _currentPageNotifier.value = 0;
                                    });
                                  },
                                ),

                                // CATEGORIAS E SUBCATEGORIAS (condicional)
                                if (menuShowCategorias &&
                                    categoriasMenu.isNotEmpty) ...[
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                                    child: Text(
                                      'Categorias',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  ...categoriasMenu.expand((cat) {
                                    final subcategoriasSet = <String>{};
                                    for (final p in produtos) {
                                      final c = (p['categoria'] ??
                                              p['categoriaId'] ??
                                              '')
                                          .toString()
                                          .trim();
                                      final sub = (p['subcategoria'] ??
                                              p['subcategoriaId'] ??
                                              '')
                                          .toString()
                                          .trim();
                                      if (c == cat && sub.isNotEmpty) {
                                        subcategoriasSet.add(sub);
                                      }
                                    }
                                    final subcategorias =
                                        subcategoriasSet.toList()..sort();
                                    return [
                                      ListTile(
                                        dense: true,
                                        leading:
                                            const Icon(Icons.chevron_right),
                                        title: Text(cat),
                                        onTap: () {
                                          Navigator.pop(context);
                                          setState(() {
                                            _selectedCategory = cat;
                                            _selectedSubcategory = null;
                                            _currentPageNotifier.value = 0;
                                          });
                                        },
                                      ),
                                      ...subcategorias.map((sub) {
                                        final isDark =
                                            Theme.of(context).brightness ==
                                                Brightness.dark;
                                        final subcatColor = isDark
                                            ? Colors.white
                                            : Colors.black87;
                                        return ListTile(
                                          dense: true,
                                          leading: Icon(
                                              Icons.subdirectory_arrow_right,
                                              size: 18,
                                              color: primaryColor
                                                  .withValues(alpha: 0.7)),
                                          title: Text(
                                            sub,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: subcatColor,
                                            ),
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            setState(() {
                                              _selectedCategory = cat;
                                              _selectedSubcategory = sub;
                                              _currentPageNotifier.value = 0;
                                            });
                                          },
                                        );
                                      }),
                                    ];
                                  }),
                                ],
                              ],
                            ),
                          ),

                          const Divider(height: 1),

                          // ENTRAR/CADASTRAR ou PERFIL - depende se está logado (NOVO SISTEMA)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: ClienteAuthService.getClienteLogado(),
                            builder: (context, snapshot) {
                              final cliente = snapshot.data;

                              if (cliente != null) {
                                // Cliente LOGADO - mostrar perfil e opcionalmente Indicar amigo
                                final nome = cliente['nome'] ?? 'Cliente';
                                final clienteId =
                                    (cliente['clienteId'] ?? '').toString();
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue,
                                        child: Text(
                                          nome.isNotEmpty
                                              ? nome[0].toUpperCase()
                                              : 'C',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ),
                                      title: Text(
                                        nome,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: const Text('Ver meu perfil'),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        final lojaIdSessao =
                                            await ClienteAuthService
                                                .getLojaId();
                                        final lojaIdPerfil = lojaIdSessao ??
                                            _resolvedLojaId ??
                                            widget.lojaId;
                                        if (!context.mounted) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PerfilClienteScreenNovo(
                                              lojaId: lojaIdPerfil,
                                              clienteId: clienteId,
                                            ),
                                          ),
                                        ).then(
                                            (_) => _loadClienteAndFavoritos());
                                      },
                                    ),
                                    if (indicacaoAtivo && clienteId.isNotEmpty)
                                      ListTile(
                                        leading: Icon(Icons.card_giftcard,
                                            color: _successColor),
                                        title: const Text('Indicar amigo'),
                                        subtitle: const Text(
                                          'Compartilhe o link; você e seu amigo ganham cupom',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _mostrarIndicarAmigoSheet(
                                            context,
                                            lojaId: _resolvedLojaId ??
                                                widget.lojaId,
                                            clienteId: clienteId,
                                          );
                                        },
                                      ),
                                  ],
                                );
                              }

                              // Cliente NÃO LOGADO - mostrar botões Entrar/Cadastrar
                              if (menuShowEntrar) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.login),
                                      title: const Text('Entrar'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        final lojaIdAuth =
                                            _resolvedLojaId ?? widget.lojaId;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LoginScreenCliente(
                                                lojaId: lojaIdAuth),
                                          ),
                                        ).then(
                                            (_) => _loadClienteAndFavoritos());
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.person_add),
                                      title: const Text('Cadastrar'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        final lojaIdAuth =
                                            _resolvedLojaId ?? widget.lojaId;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CadastroScreenCliente(
                                                    lojaId: lojaIdAuth),
                                          ),
                                        ).then(
                                            (_) => _loadClienteAndFavoritos());
                                      },
                                    ),
                                  ],
                                );
                              }

                              return const SizedBox.shrink();
                            },
                          ),

                          // Modo escuro
                          SwitchListTile(
                            value: _modoEscuro,
                            onChanged: (value) => _toggleModoEscuro(value),
                            title: const Text('Modo escuro'),
                            secondary: Icon(
                              _modoEscuro ? Icons.dark_mode : Icons.light_mode,
                              color: primaryColor,
                            ),
                          ),

                          // SAC (elogios, sugestões e críticas) - condicional
                          if (menuShowSac)
                            ListTile(
                              leading: const Icon(Icons.support_agent_outlined),
                              title: const Text(
                                  'SAC – elogios, sugestões e críticas',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () {
                                Navigator.pop(context);

                                final sacNumber = sacWhatsapp.trim().isNotEmpty
                                    ? sacWhatsapp.trim()
                                    : whatsappVendedor.trim();

                                if (sacNumber.isEmpty) {
                                  _snack(
                                      'WhatsApp de atendimento não configurado.');
                                } else {
                                  _openWhatsappSimple(
                                    sacNumber,
                                    'Olá! Gostaria de falar com o SAC (elogios, sugestões ou críticas).',
                                  );
                                }
                              },
                            ),

                          // QUEM SOMOS - condicional
                          if (menuShowQuemSomos)
                            ListTile(
                              leading: const Icon(Icons.info_outline),
                              title: Text(quemSomosTitulo),
                              onTap: () {
                                Navigator.pop(context);
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  builder: (_) {
                                    final texto = quemSomosTexto.trim().isEmpty
                                        ? 'Texto de "$quemSomosTitulo" ainda não configurado.\n\nVocê poderá editar esse conteúdo na tela Loja Config.'
                                        : quemSomosTexto.trim();
                                    return Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        MediaQuery.of(context)
                                                .viewInsets
                                                .bottom +
                                            24,
                                      ),
                                      child: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              quemSomosTitulo,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge!
                                                  .copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              texto,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          // DICAS E INFORMAÇÕES (cuidados, garantias, qualidade) - condicional
                          if (menuShowDicas)
                            ListTile(
                              leading: const Icon(Icons.lightbulb_outline),
                              title: const Text(
                                'Dicas e informações',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: const Text(
                                'Cuidados, garantias e qualidade',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                final w = MediaQuery.of(context).size.width;
                                final isWide = w >= 900;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => CatalogDicasScreen(
                                      lojaId: _resolvedLojaId ?? widget.lojaId,
                                      lojaNome: lojaNome,
                                      dicas: dicasList,
                                      primaryColor: primaryColor,
                                      logoUrl:
                                          logoUrl.isNotEmpty ? logoUrl : null,
                                      logoHeight: isWide ? 90 : 80,
                                      bannerHeightCard:
                                          mediaConfig.bannerH * 0.65,
                                      bannerHeightDetail:
                                          mediaConfig.bannerH * 0.85,
                                      dicasColors: catalogDicasColors,
                                      contactInfo: DicasContactInfo(
                                        whatsappNumber: atendimentoWhatsapp,
                                        instagramUrl: instagramUrl.isNotEmpty
                                            ? instagramUrl
                                            : null,
                                        facebookUrl: facebookUrl.isNotEmpty
                                            ? facebookUrl
                                            : null,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ================= APPBAR =================
                  appBar: AppBar(
                    backgroundColor: headerColor,
                    elevation: 0,
                    // Altura dinâmica: desktop maior; mobile inalterado
                    toolbarHeight: useMinimalLayout
                        ? (isDesktop ? 100 : 88)
                        : (isDesktop
                            ? (categoriasMenu.isEmpty
                                ? 140
                                : (_selectedCategory != null ? 236 : 186))
                            : (categoriasMenu.isEmpty
                                ? 120
                                : (_selectedCategory != null ? 216 : 166))),
                    titleSpacing: 0,
                    automaticallyImplyLeading: false,
                    title: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // ======= LINHA SUPERIOR: MENU + LOGO + PUBLICAR + CARRINHO =======
                        Row(
                          children: [
                            // ☰ MENU – abre o drawer à esquerda
                            Builder(
                              builder: (ctx) => IconButton(
                                icon: Icon(
                                  Icons.menu,
                                  size: 28,
                                  color:
                                      headerIconColor, // ✅ Usa cor do cabeçalho
                                ),
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                              ),
                            ),

                            // LOGO CENTRALIZADA (desktop: maior e nítida; mobile: inalterado)
                            Expanded(
                              child: Center(
                                child: logoUrl.isNotEmpty
                                    ? SizedBox(
                                        height: isDesktop ? 68 : 56,
                                        child: Image(
                                          image: mpImageProvider(logoUrl),
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      )
                                    : Text(
                                        lojaNome,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 22,
                                          color:
                                              headerTextColor, // ✅ Usa cor do cabeçalho
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                            ),

                            // 🌐 BOTÃO ABRIR CATÁLOGO WEB (sempre visível)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: IconButton(
                                icon: Icon(
                                  Icons.language,
                                  size: 26,
                                  color:
                                      headerIconColor, // ✅ Usa cor do cabeçalho
                                ),
                                tooltip: 'Abrir catálogo online',
                                onPressed: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final lojaId =
                                      _resolvedLojaId ?? widget.lojaId;
                                  final url =
                                      'https://app.mastepalm.com.br/loja/$lojaId';
                                  logD('🌐 Abrindo catálogo web: $url');

                                  final uri = Uri.parse(url);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );

                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                              'Abrindo navegador...'),
                                          duration: const Duration(seconds: 2),
                                          backgroundColor: primaryColor,
                                        ),
                                      );
                                    }
                                  } else {
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Não foi possível abrir: $url'),
                                          backgroundColor: Colors.red,
                                          action: SnackBarAction(
                                            label: 'Copiar',
                                            textColor: Colors.white,
                                            onPressed: () {
                                              Clipboard.setData(
                                                  ClipboardData(text: url));
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),

                            // ✅ Fallback para link direto: se não há histórico confiável,
                            // permite voltar explicitamente para Home.
                            if (kIsWeb && !Navigator.of(context).canPop())
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: IconButton(
                                  icon: const Icon(Icons.home_outlined),
                                  color: headerIconColor,
                                  tooltip: 'Voltar para Home',
                                  onPressed: () {
                                    Navigator.of(context).pushNamed('/home');
                                  },
                                ),
                              ),

                            // BOTÃO PUBLICAR (só no preview, dentro do app)
                            if (widget.preview)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    backgroundColor: primaryColor,
                                    foregroundColor: btnTextColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  onPressed:
                                      _publicando ? null : publicarCatalogo,
                                  child: Text(
                                    _publicando ? 'Publicando...' : 'Publicar',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                            // ÍCONE DO CARRINHO (SEM TEXTO)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    icon:
                                        const Icon(Icons.shopping_bag_outlined),
                                    color:
                                        headerIconColor, // ✅ Usa cor do cabeçalho
                                    onPressed: () => _openCartSheet(
                                      fretes: fretes,
                                      cupons: cupons,
                                      primary: primaryColor,
                                      buttonText: btnTextColor,
                                      textColor: textColor,
                                      cardColor: cardColor,
                                      checkoutCardColor: checkoutCardColor,
                                      checkoutFieldBg: checkoutFieldBg,
                                      checkoutFieldBorder: checkoutFieldBorder,
                                      checkoutFieldTextColor:
                                          checkoutFieldTextColor,
                                      checkoutLabelColor: checkoutLabelColor,
                                      checkoutTotalColor: checkoutTotalColor,
                                      productNameColor: productNameColor,
                                      productPriceColor: productPriceColor,
                                      whatsappVendedor: whatsappVendedor,
                                      lojaNome: lojaNome,
                                      paymentAsset: paymentAssets,
                                      paymentCodes: paymentCodes,
                                      instagramUrl: instagramUrl,
                                      facebookUrl: facebookUrl,
                                      empresaRazao: empresaRazao,
                                      empresaCnpj: empresaCnpj,
                                      checkoutGateway: checkoutGateway,
                                      checkoutButtonLabel: checkoutButtonLabel,
                                      pixKey: pixKey,
                                      freightToken: freightToken,
                                    ),
                                  ),
                                  if (cartCount > 0)
                                    Positioned(
                                      right: 4,
                                      top: 6,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$cartCount',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // ======= BARRA DE PESQUISA + CATEGORIAS (mobile; desktop = sidebar) =======
                        CatalogSearchBar(
                          controller: _searchController,
                          headerSearchText: headerSearchText,
                          headerSearchHint: headerSearchHint,
                          headerSearchBg: useMinimalLayout
                              ? (readColorFromCfg(minimalSearchCfg['background']) ??
                                  Colors.white)
                              : headerSearchBg,
                          hintText: (minimalSearchCfg['placeholder'] ??
                                  'O que voce esta procurando?')
                              .toString(),
                          iconOnRight: useMinimalLayout,
                          borderColor: useMinimalLayout
                              ? (readColorFromCfg(minimalSearchCfg['borderColor']) ??
                                  Colors.black12)
                              : null,
                          borderRadius: useMinimalLayout
                              ? safeDouble(minimalSearchCfg['radius'], 10)
                              : 12,
                          height: useMinimalLayout
                              ? safeDouble(minimalSearchCfg['height'], 44)
                              : 42,
                          onChanged: _debouncedSearchUpdate,
                          onClear: () {
                            _searchDebounce?.cancel();
                            _searchController.clear();
                            _searchNotifier.value = '';
                            _currentPageNotifier.value = 0;
                          },
                        ),
                        if (!isDesktop && !useMinimalLayout)
                          CatalogCategorySubcategoryFilters(
                            categoriasMenu: categoriasMenu,
                            selectedCategory: _selectedCategory,
                            selectedSubcategory: _selectedSubcategory,
                            produtos: produtos,
                            textColor: textColor,
                            cardColor: cardColor,
                            primaryColor: primaryColor,
                            onCategorySelectedNull: () {
                              setState(() {
                                _selectedCategory = null;
                                _selectedSubcategory = null;
                                _currentPageNotifier.value = 0;
                              });
                            },
                            onCategorySelected: (cat) {
                              setState(() {
                                _selectedCategory = cat;
                                _selectedSubcategory = null;
                                _currentPageNotifier.value = 0;
                              });
                            },
                            onSubcategorySelectedNull: () {
                              setState(() {
                                _selectedSubcategory = null;
                                _currentPageNotifier.value = 0;
                              });
                            },
                            onSubcategorySelected: (subcat) {
                              setState(() {
                                _selectedSubcategory = subcat;
                                _currentPageNotifier.value = 0;
                              });
                            },
                          ),
                      ],
                    ),
                  ),

                  // ========== FAB DO CARRINHO ==========
                  floatingActionButton: _cart.isEmpty
                      ? null
                      : FloatingActionButton.extended(
                          onPressed: () => _openCartSheet(
                            fretes: fretes,
                            cupons: cupons,
                            primary: primaryColor,
                            buttonText: btnTextColor,
                            textColor: textColor,
                            cardColor: cardColor,
                            checkoutCardColor: checkoutCardColor,
                            checkoutFieldBg: checkoutFieldBg,
                            checkoutFieldBorder: checkoutFieldBorder,
                            checkoutFieldTextColor: checkoutFieldTextColor,
                            checkoutLabelColor: checkoutLabelColor,
                            checkoutTotalColor: checkoutTotalColor,
                            productNameColor: productNameColor,
                            productPriceColor: productPriceColor,
                            whatsappVendedor: whatsappVendedor,
                            lojaNome: lojaNome,
                            paymentAsset: paymentAssets,
                            paymentCodes: paymentCodes,
                            instagramUrl: instagramUrl,
                            facebookUrl: facebookUrl,
                            empresaRazao: empresaRazao,
                            empresaCnpj: empresaCnpj,
                            checkoutGateway: checkoutGateway,
                            checkoutButtonLabel: checkoutButtonLabel,
                            pixKey: pixKey,
                            freightToken: freightToken,
                          ),
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text('Carrinho ($cartCount)'),
                        ),

// ================= CORPO =================
                  body: Stack(
                    children: [
                      Column(
                        children: [
                          if (useMinimalLayout &&
                              safeBool(promoBarCfg['enabled'], false))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                              child: CatalogPromoBar(
                                enabled: true,
                              text: (promoBarCfg['text'] ?? '').toString(),
                              backgroundColor: readColorFromCfg(
                                      promoBarCfg['backgroundColor']) ??
                                  const Color(0xFFFF4F96),
                              textColor:
                                  readColorFromCfg(promoBarCfg['textColor']) ??
                                      Colors.white,
                              icon: safeBool(promoBarCfg['showIcon'], false)
                                  ? Icons.local_offer_outlined
                                  : null,
                              height: safeDouble(promoBarCfg['height'], 34),
                              textAlign: parseTextAlign(
                                  promoBarCfg['alignment'], TextAlign.center),
                              bold: safeBool(promoBarCfg['bold'], true),
                                marqueeWhenOverflow:
                                    safeBool(promoBarCfg['marquee'], true),
                              onTap: () {
                                final link = (promoBarCfg['link'] ?? '')
                                    .toString()
                                    .trim();
                                if (link.isEmpty) return;
                                _openUrl(link);
                                },
                              ),
                            ),
                          if (_isOffline)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: Colors.orange.shade800,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.wifi_off,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Sem conexão com a internet',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () => _onRefreshProducts(lojaId),
                              child: ValueListenableBuilder<String>(
                                valueListenable: _searchNotifier,
                                builder: (context, search, _) =>
                                    ValueListenableBuilder<int>(
                                  valueListenable: _currentPageNotifier,
                                  builder: (context, currentPage, _) =>
                                      LayoutBuilder(
                                    builder: (context, c) {
                                      final isDesktopBody = c.maxWidth >= 1024;
                                      // 👉 aplica filtro da busca + categoria + subcategoria
                                      final listaFiltrada = produtos.where((p) {
                                        final n = (p['nome'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final d = (p['descricao'] ?? '')
                                            .toString()
                                            .toLowerCase();
                                        final matchText = search.trim().isEmpty
                                            ? true
                                            : n.contains(search) ||
                                                d.contains(search);
                                        final cat = (p['categoria'] ??
                                                p['categoriaId'] ??
                                                '')
                                            .toString()
                                            .trim();
                                        final matchCat =
                                            _selectedCategory == null ||
                                                    _selectedCategory!.isEmpty
                                                ? true
                                                : cat == _selectedCategory;
                                        // Filtro por subcategoria (compatível com subcategoriaId)
                                        final subcat = (p['subcategoria'] ??
                                                p['subcategoriaId'] ??
                                                '')
                                            .toString()
                                            .trim();
                                        final matchSubcat =
                                            _selectedSubcategory == null ||
                                                    _selectedSubcategory!
                                                        .isEmpty
                                                ? true
                                                : subcat ==
                                                    _selectedSubcategory;
                                        final preco = (p['preco'] ??
                                                p['valor'] ??
                                                0.0) is num
                                            ? (p['preco'] ?? p['valor'] ?? 0.0)
                                                as num
                                            : (double.tryParse(
                                                    '${p['preco'] ?? p['valor'] ?? 0}') ??
                                                0.0);
                                        final matchPrecoMin =
                                            _precoMin == null ||
                                                preco >= _precoMin!;
                                        final matchPrecoMax =
                                            _precoMax == null ||
                                                preco <= _precoMax!;
                                        final matchEstoque =
                                            !_apenasEmEstoque ||
                                                CatalogEstoqueHelper
                                                    .produtoPassaFiltroApenasEmEstoque(
                                                        p);
                                        return matchText &&
                                            matchCat &&
                                            matchSubcat &&
                                            matchPrecoMin &&
                                            matchPrecoMax &&
                                            matchEstoque;
                                      }).toList();

                                      // Ordenação
                                      final listaOrdenada =
                                          List<Map<String, dynamic>>.from(
                                              listaFiltrada);
                                      if (_ordenacaoProdutos == 'preco_asc') {
                                        listaOrdenada.sort((a, b) {
                                          final va = (a['valor'] ??
                                                  a['preco'] ??
                                                  0.0) is num
                                              ? (a['valor'] ??
                                                  a['preco'] ??
                                                  0.0) as num
                                              : (double.tryParse(
                                                      '${a['valor'] ?? a['preco'] ?? 0}') ??
                                                  0.0);
                                          final vb = (b['valor'] ??
                                                  b['preco'] ??
                                                  0.0) is num
                                              ? (b['valor'] ??
                                                  b['preco'] ??
                                                  0.0) as num
                                              : (double.tryParse(
                                                      '${b['valor'] ?? b['preco'] ?? 0}') ??
                                                  0.0);
                                          return va.compareTo(vb);
                                        });
                                      } else if (_ordenacaoProdutos ==
                                          'preco_desc') {
                                        listaOrdenada.sort((a, b) {
                                          final va = (a['valor'] ??
                                                  a['preco'] ??
                                                  0.0) is num
                                              ? (a['valor'] ??
                                                  a['preco'] ??
                                                  0.0) as num
                                              : (double.tryParse(
                                                      '${a['valor'] ?? a['preco'] ?? 0}') ??
                                                  0.0);
                                          final vb = (b['valor'] ??
                                                  b['preco'] ??
                                                  0.0) is num
                                              ? (b['valor'] ??
                                                  b['preco'] ??
                                                  0.0) as num
                                              : (double.tryParse(
                                                      '${b['valor'] ?? b['preco'] ?? 0}') ??
                                                  0.0);
                                          return vb.compareTo(va);
                                        });
                                      } else if (_ordenacaoProdutos ==
                                          'novidade') {
                                        // Mais recentes primeiro (dataCriacao)
                                        listaOrdenada.sort((a, b) {
                                          final dtA =
                                              asDateTime(a['dataCriacao']);
                                          final dtB =
                                              asDateTime(b['dataCriacao']);
                                          if (dtA == null && dtB == null)
                                            return 0;
                                          if (dtA == null) return 1;
                                          if (dtB == null) return -1;
                                          return dtB.compareTo(dtA);
                                        });
                                      } else {
                                        // nome (alfabética)
                                        listaOrdenada.sort((a, b) {
                                          final an = (a['nome'] ?? '')
                                              .toString()
                                              .toLowerCase();
                                          final bn = (b['nome'] ?? '')
                                              .toString()
                                              .toLowerCase();
                                          return an.compareTo(bn);
                                        });
                                      }

                                      // Paginação: 20 produtos por página
                                      final totalPaginas =
                                          (listaOrdenada.length /
                                                  _produtosPorPagina)
                                              .ceil()
                                              .clamp(1, 999999);
                                      final paginaAtual = currentPage.clamp(
                                          0, totalPaginas - 1);
                                      final start =
                                          paginaAtual * _produtosPorPagina;
                                      final listaPaginated = listaOrdenada
                                          .skip(start)
                                          .take(_produtosPorPagina)
                                          .toList();

                                      final scrollBody = CustomScrollView(
                                        controller: _catalogScrollController,
                                        cacheExtent: 800,
                                        physics: const ClampingScrollPhysics(
                                            parent:
                                                AlwaysScrollableScrollPhysics()),
                                        slivers: [
                                          SliverToBoxAdapter(
                                            child: Column(
                                              children: [
                                                if (banners.isNotEmpty)
                                                  CatalogBannerCarousel(
                                                    banners: banners,
                                                    height: bannerH,
                                                  ),
                                                if (useMinimalLayout)
                                                  CatalogMinimalCategoryImageStrip(
                                                    categories: categoriasMenu,
                                                    selectedCategory:
                                                        _selectedCategory,
                                                    categoryVisuals:
                                                        categoryVisualsCfg,
                                                    categoryAliasesByName:
                                                        categoryAliasesByName,
                                                    onSelect: (cat) {
                                                      setState(() {
                                                        _selectedCategory = cat;
                                                        _selectedSubcategory =
                                                            null;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                    },
                                                    onClear: () {
                                                      setState(() {
                                                        _selectedCategory = null;
                                                        _selectedSubcategory =
                                                            null;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                    },
                                                    textColor: textColor,
                                                    fallbackBg: cardColor,
                                                  ),
                                                if (useMinimalLayout)
                                                  CatalogMinimalHeroBanner(
                                                    enabled: safeBool(
                                                        heroBannerCfg['enabled'],
                                                        false),
                                                    title: (heroBannerCfg[
                                                                'title'] ??
                                                            '')
                                                        .toString(),
                                                    subtitle: (heroBannerCfg[
                                                                'subtitle'] ??
                                                            '')
                                                        .toString(),
                                                    buttonText:
                                                        (heroBannerCfg[
                                                                    'buttonText'] ??
                                                                '')
                                                            .toString(),
                                                    imageUrl: (isDesktop
                                                                ? heroBannerCfg[
                                                                    'image']
                                                                : heroBannerCfg[
                                                                    'mobileImage']) ??
                                                            heroBannerCfg[
                                                                'image'] ??
                                                            '',
                                                    textColor: readColorFromCfg(
                                                            heroBannerCfg[
                                                                'textColor']) ??
                                                        Colors.white,
                                                    buttonColor:
                                                        readColorFromCfg(
                                                                heroBannerCfg[
                                                                    'buttonColor']) ??
                                                            primaryColor,
                                                    backgroundColor:
                                                        readColorFromCfg(
                                                                heroBannerCfg[
                                                                    'backgroundColor']) ??
                                                            cardColor,
                                                    height: safeDouble(
                                                        heroBannerCfg['height'],
                                                        isDesktop ? 210 : 164),
                                                    borderRadius: safeDouble(
                                                        heroBannerCfg[
                                                            'borderRadius'],
                                                        18),
                                                    overlayOpacity: safeDouble(
                                                        heroBannerCfg[
                                                            'overlayOpacity'],
                                                        0.16),
                                                    onTap: () {
                                                      final link = (heroBannerCfg[
                                                                  'buttonLink'] ??
                                                              '')
                                                          .toString()
                                                          .trim();
                                                      if (link.isEmpty) return;
                                                      _openUrl(link);
                                                    },
                                                  ),
                                                if (useMinimalLayout &&
                                                    bestSellersSectionEnabled &&
                                                    produtos.isNotEmpty)
                                                  CatalogMinimalBestSellersSection(
                                                    title: bestSellersTitle,
                                                    productCardSize:
                                                        productCardSize,
                                                    products:
                                                        pickBestSellersForMinimalCatalog(
                                                      produtos,
                                                      limit: bestSellersLimit,
                                                    ),
                                                    lojaId: lojaId,
                                                    todosProdutos: produtos,
                                                    onAdd: (it) =>
                                                        _addToCart(
                                                            it, produtos),
                                                    onAbrirCarrinho: () =>
                                                        _openCartSheet(
                                                      fretes: fretes,
                                                      cupons: cupons,
                                                      primary: primaryColor,
                                                      buttonText: btnTextColor,
                                                      textColor: textColor,
                                                      cardColor: cardColor,
                                                      checkoutCardColor:
                                                          checkoutCardColor,
                                                      checkoutFieldBg:
                                                          checkoutFieldBg,
                                                      checkoutFieldBorder:
                                                          checkoutFieldBorder,
                                                      checkoutFieldTextColor:
                                                          checkoutFieldTextColor,
                                                      checkoutLabelColor:
                                                          checkoutLabelColor,
                                                      checkoutTotalColor:
                                                          checkoutTotalColor,
                                                      productNameColor:
                                                          productNameColor,
                                                      productPriceColor:
                                                          productPriceColor,
                                                      whatsappVendedor:
                                                          whatsappVendedor,
                                                      lojaNome: lojaNome,
                                                      paymentAsset:
                                                          paymentAssets,
                                                      paymentCodes:
                                                          paymentCodes,
                                                      instagramUrl:
                                                          instagramUrl,
                                                      facebookUrl: facebookUrl,
                                                      empresaRazao: empresaRazao,
                                                      empresaCnpj: empresaCnpj,
                                                      checkoutGateway:
                                                          checkoutGateway,
                                                      checkoutButtonLabel:
                                                          checkoutButtonLabel,
                                                      pixKey: pixKey,
                                                      freightToken:
                                                          freightToken,
                                                    ),
                                                    catalogShareUrl:
                                                        CatalogShareService
                                                            .buildUrlWithParams(
                                                      '$_baseUrlCatalogo/$lojaId',
                                                      ref: widget.vendedorRef,
                                                      indicacao: widget
                                                          .indicacaoClienteRef,
                                                    ),
                                                    textColor: textColor,
                                                    cardColor: cardColor,
                                                    priceColor:
                                                        productPriceColor,
                                                    prazoEntregaTexto:
                                                        prazoEntregaTexto,
                                                    nomeLoja: lojaNome,
                                                    contatoWhatsapp:
                                                        whatsappVendedor,
                                                    politicaFrete: null,
                                                    onProductViewed:
                                                        _onProductViewed,
                                                  ),
                                                const SizedBox(height: 16),

                                                // ✨ BANNER DE CAMPANHAS
                                                CampanhaBannerWidget(
                                                    lojaId: lojaId),
                                              ],
                                            ),
                                          ),
                                          if (prodSnap.connectionState ==
                                              ConnectionState.waiting)
                                            CatalogSkeletonGrid(
                                                isDesktop: isDesktopBody,
                                                desktopCols: gridDesktopCols,
                                                mobileCols: gridMobileCols)
                                          else if (listaOrdenada.isEmpty)
                                            const CatalogEmptyProductsState()
                                          else ...[
                                            // Ordenação (filtros) - linha separada da paginação para evitar sobreposição
                                            SliverToBoxAdapter(
                                              child: CatalogSortFiltersSection(
                                                ordenacaoProdutos:
                                                    _ordenacaoProdutos,
                                                apenasEmEstoque:
                                                    _apenasEmEstoque,
                                                precoMin: _precoMin,
                                                precoMax: _precoMax,
                                                primaryColor: primaryColor,
                                                cardColor: cardColor,
                                                textColor: textColor,
                                                onSortChanged: (value) {
                                                  setState(() {
                                                    _ordenacaoProdutos = value;
                                                    _currentPageNotifier.value =
                                                        0;
                                                  });
                                                },
                                                onFilterEmEstoqueToggled: () {
                                                  setState(() {
                                                    _apenasEmEstoque =
                                                        !_apenasEmEstoque;
                                                    _currentPageNotifier.value =
                                                        0;
                                                  });
                                                },
                                                onFilterPrecoTap: () =>
                                                    _mostrarDialogoFiltroPreco(
                                                        textColor),
                                                paginaAtual: paginaAtual,
                                                totalPaginas: totalPaginas,
                                                onPageChanged: (p) {
                                                  _currentPageNotifier.value =
                                                      p;
                                                },
                                              ),
                                            ),
                                            if (_recentIds.isNotEmpty)
                                              buildCatalogRecentSectionSliver(
                                                recentProducts: () {
                                                  final pm = {
                                                    for (final p in produtos)
                                                      safeStr(p['id']): p
                                                  };
                                                  return _recentIds
                                                      .where((id) =>
                                                          pm.containsKey(id))
                                                      .take(8)
                                                      .map((id) => pm[id]!)
                                                      .toList();
                                                }(),
                                                todosProdutos: produtos,
                                                lojaId: lojaId,
                                                onAdd: (it) =>
                                                    _addToCart(it, produtos),
                                                onProductViewed:
                                                    _onProductViewed,
                                                onToggleFavorito:
                                                    _toggleFavorito,
                                                onAbrirLoginParaFavorito:
                                                    _abrirLoginParaFavorito,
                                                onAbrirCarrinho: () =>
                                                    _openCartSheet(
                                                  fretes: fretes,
                                                  cupons: cupons,
                                                  primary: primaryColor,
                                                  buttonText: btnTextColor,
                                                  textColor: textColor,
                                                  cardColor: cardColor,
                                                  checkoutCardColor:
                                                      checkoutCardColor,
                                                  checkoutFieldBg:
                                                      checkoutFieldBg,
                                                  checkoutFieldBorder:
                                                      checkoutFieldBorder,
                                                  checkoutFieldTextColor:
                                                      checkoutFieldTextColor,
                                                  checkoutLabelColor:
                                                      checkoutLabelColor,
                                                  checkoutTotalColor:
                                                      checkoutTotalColor,
                                                  productNameColor:
                                                      productNameColor,
                                                  productPriceColor:
                                                      productPriceColor,
                                                  whatsappVendedor:
                                                      whatsappVendedor,
                                                  lojaNome: lojaNome,
                                                  paymentAsset: paymentAssets,
                                                  paymentCodes: paymentCodes,
                                                  instagramUrl: instagramUrl,
                                                  facebookUrl: facebookUrl,
                                                  empresaRazao: empresaRazao,
                                                  empresaCnpj: empresaCnpj,
                                                  checkoutGateway:
                                                      checkoutGateway,
                                                  checkoutButtonLabel:
                                                      checkoutButtonLabel,
                                                  pixKey: pixKey,
                                                  freightToken: freightToken,
                                                ),
                                                clienteId: _clienteId,
                                                favoritosIds: _favoritosIds,
                                                mostrarEstoqueNoCatalogo:
                                                    mostrarEstoqueNoCatalogo,
                                                mostrarQuantidadeNoCatalogo:
                                                    mostrarQuantidadeNoCatalogo,
                                                cardBorderRadius:
                                                    cardBorderRadius,
                                                cardShowShadow: cardShowShadow,
                                                prazoEntregaTexto:
                                                    prazoEntregaTexto,
                                                jurosParcelamento:
                                                    jurosParcelamento,
                                                maxParcelas: maxParcelasClamped,
                                                textColor: textColor,
                                                useMinimalLayout: useMinimalLayout,
                                                productCardSize:
                                                    productCardSize,
                                                cardColor: cardColor,
                                                priceColor: productPriceColor,
                                                catalogShareUrl:
                                                    CatalogShareService
                                                        .buildUrlWithParams(
                                                  '$_baseUrlCatalogo/$lojaId',
                                                  ref: widget.vendedorRef,
                                                  indicacao: widget
                                                      .indicacaoClienteRef,
                                                ),
                                                nomeLoja: lojaNome,
                                                contatoWhatsapp: whatsappVendedor,
                                                politicaFrete: null,
                                              ),
                                            buildCatalogProductsGridSliver(
                                              products: listaPaginated,
                                              todosProdutosParaCombo: produtos,
                                              lojaId: lojaId,
                                              isDesktop: isDesktopBody,
                                              desktopCols: gridDesktopCols,
                                              mobileCols: gridMobileCols,
                                              onAdd: (it) =>
                                                  _addToCart(it, produtos),
                                              onProductViewed: _onProductViewed,
                                              onToggleFavorito: _toggleFavorito,
                                              onAbrirLoginParaFavorito:
                                                  _abrirLoginParaFavorito,
                                              onAbrirCarrinho: () =>
                                                  _openCartSheet(
                                                fretes: fretes,
                                                cupons: cupons,
                                                primary: primaryColor,
                                                buttonText: btnTextColor,
                                                textColor: textColor,
                                                cardColor: cardColor,
                                                checkoutCardColor:
                                                    checkoutCardColor,
                                                checkoutFieldBg:
                                                    checkoutFieldBg,
                                                checkoutFieldBorder:
                                                    checkoutFieldBorder,
                                                checkoutFieldTextColor:
                                                    checkoutFieldTextColor,
                                                checkoutLabelColor:
                                                    checkoutLabelColor,
                                                checkoutTotalColor:
                                                    checkoutTotalColor,
                                                productNameColor:
                                                    productNameColor,
                                                productPriceColor:
                                                    productPriceColor,
                                                whatsappVendedor:
                                                    whatsappVendedor,
                                                lojaNome: lojaNome,
                                                paymentAsset: paymentAssets,
                                                paymentCodes: paymentCodes,
                                                instagramUrl: instagramUrl,
                                                facebookUrl: facebookUrl,
                                                empresaRazao: empresaRazao,
                                                empresaCnpj: empresaCnpj,
                                                checkoutGateway:
                                                    checkoutGateway,
                                                checkoutButtonLabel:
                                                    checkoutButtonLabel,
                                                pixKey: pixKey,
                                                freightToken: freightToken,
                                              ),
                                              clienteId: _clienteId,
                                              favoritosIds: _favoritosIds,
                                              mostrarEstoqueNoCatalogo:
                                                  mostrarEstoqueNoCatalogo,
                                              mostrarQuantidadeNoCatalogo:
                                                  mostrarQuantidadeNoCatalogo,
                                              cardBorderRadius:
                                                  useMinimalLayout
                                                      ? safeDouble(
                                                          minimalGridCfg[
                                                              'cardBorderRadius'],
                                                          cardBorderRadius)
                                                      : cardBorderRadius,
                                              cardShowShadow: useMinimalLayout
                                                  ? safeBool(
                                                      minimalGridCfg[
                                                          'cardShowShadow'],
                                                      false)
                                                  : cardShowShadow,
                                              prazoEntregaTexto:
                                                  prazoEntregaTexto,
                                              jurosParcelamento:
                                                  jurosParcelamento,
                                              maxParcelas: maxParcelasClamped,
                                              imageCacheWidth: useMinimalLayout
                                                  ? safeInt(
                                                      minimalGridCfg[
                                                          'imageCacheWidth'],
                                                      CatalogProductCardSize
                                                          .gridImageCache(
                                                        size: productCardSize,
                                                        minimalLayout: true,
                                                        isWeb: kIsWeb,
                                                      ).width,
                                                    )
                                                  : CatalogProductCardSize
                                                      .gridImageCache(
                                                    size: productCardSize,
                                                    minimalLayout: false,
                                                    isWeb: kIsWeb,
                                                  ).width,
                                              imageCacheHeight: useMinimalLayout
                                                  ? safeInt(
                                                      minimalGridCfg[
                                                          'imageCacheHeight'],
                                                      CatalogProductCardSize
                                                          .gridImageCache(
                                                        size: productCardSize,
                                                        minimalLayout: true,
                                                        isWeb: kIsWeb,
                                                      ).height,
                                                    )
                                                  : CatalogProductCardSize
                                                      .gridImageCache(
                                                    size: productCardSize,
                                                    minimalLayout: false,
                                                    isWeb: kIsWeb,
                                                  ).height,
                                              childAspectRatio: useMinimalLayout
                                                  ? safeDouble(
                                                      minimalGridCfg[
                                                          'aspectRatio'],
                                                      CatalogProductCardSize
                                                          .minimalAspectRatio(
                                                              productCardSize),
                                                    )
                                                  : CatalogProductCardSize
                                                      .standardAspectRatio(
                                                          productCardSize),
                                              mainAxisSpacing: useMinimalLayout
                                                  ? safeDouble(minimalGridCfg[
                                                      'mainAxisSpacing'], 14)
                                                  : 16,
                                              crossAxisSpacing: useMinimalLayout
                                                  ? safeDouble(minimalGridCfg[
                                                      'crossAxisSpacing'], 12)
                                                  : 16,
                                              padding: useMinimalLayout
                                                  ? const EdgeInsets.fromLTRB(
                                                      12, 0, 12, 24)
                                                  : const EdgeInsets.fromLTRB(
                                                      12, 0, 12, 24),
                                              catalogShareUrl: CatalogShareService.buildUrlWithParams(
                                                '$_baseUrlCatalogo/$lojaId',
                                                ref: widget.vendedorRef,
                                                indicacao: widget.indicacaoClienteRef,
                                              ),
                                              useMinimalLayout: useMinimalLayout,
                                              productCardSize: productCardSize,
                                            ),
                                            // Paginação: Anterior | Página X de Y | Próxima (sempre visível)
                                            if (totalPaginas > 1)
                                              SliverToBoxAdapter(
                                                child: CatalogPaginacaoRow(
                                                  paginaAtual: paginaAtual,
                                                  totalPaginas: totalPaginas,
                                                  primaryColor: primaryColor,
                                                  cardColor: cardColor,
                                                  textColor: textColor,
                                                  onPagePrev: paginaAtual > 0
                                                      ? () =>
                                                          _currentPageNotifier
                                                                  .value =
                                                              paginaAtual - 1
                                                      : null,
                                                  onPageNext: paginaAtual <
                                                          totalPaginas - 1
                                                      ? () =>
                                                          _currentPageNotifier
                                                                  .value =
                                                              paginaAtual + 1
                                                      : null,
                                                ),
                                              ),
                                          ],
                                          // Espaçamento entre o grid e o rodapé para evitar sobreposição
                                          const SliverToBoxAdapter(
                                            child: SizedBox(height: 40),
                                          ),
                                          SliverToBoxAdapter(
                                            child: CatalogFooter(
                                              bg: footerBgColor, // ✅ Usa cor de fundo do rodapé
                                              textColor:
                                                  footerTextColor, // ✅ Usa cor de texto do rodapé
                                              textSecondaryColor:
                                                  footerTextSecondary, // ✅ Texto secundário
                                              iconColor:
                                                  footerIconColor, // ✅ Cor dos ícones
                                              linkColor:
                                                  footerLinkColor, // ✅ Cor dos links
                                              dividerColor:
                                                  footerDividerColor, // ✅ Cor das divisórias
                                              lojaNome: lojaNome,
                                              instagramUrl: instagramUrl,
                                              facebookUrl: facebookUrl,
                                              tiktokUrl: tiktokUrl,
                                              telegramUrl: telegramUrl,
                                              kwaiUrl: kwaiUrl,
                                              linkedinUrl: linkedinUrl,
                                              emailUrl: emailUrl,
                                              whatsappUrl: whatsappUrl,
                                              atendimentoWhatsapp:
                                                  atendimentoWhatsapp,
                                              links: footerLinks,
                                              paymentCodes: paymentCodes,
                                              paymentAsset: paymentAssets,
                                              badgeSSL: badgeSSL,
                                              badgeGoogle: badgeGoogle,
                                              empresaRazao: empresaRazao,
                                              empresaCnpj: empresaCnpj,
                                              onOpenUrl: _openUrl,
                                              onOpenWhatsapp: () =>
                                                  _openWhatsappSimple(
                                                atendimentoWhatsapp,
                                                'Olá, vim pelo catálogo!',
                                              ),
                                              faqItems: faqItems,
                                              politicaPrivacidadeUrl:
                                                  politicaPrivacidadeUrl,
                                              termosUsoUrl: termosUsoUrl,
                                            ),
                                          ),
                                        ],
                                      );
                                      if (isDesktopBody) {
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Sidebar categorias (esquerda) – layout desktop
                                            Container(
                                              width: 260,
                                              constraints: const BoxConstraints(
                                                minWidth: 260,
                                                maxWidth: 260,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    cardColor.withValues(alpha: 0.4),
                                                border: Border(
                                                  right: BorderSide(
                                                    color: textColor
                                                        .withValues(alpha: 0.12),
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.max,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(
                                                        20, 20, 20, 12),
                                                    child: Text(
                                                      'Categorias',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: 0.8,
                                                        color: textColor
                                                            .withValues(alpha: 0.7),
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child:
                                                        CatalogCategorySubcategoryFilters(
                                                      categoriasMenu:
                                                          categoriasMenu,
                                                      selectedCategory:
                                                          _selectedCategory,
                                                      selectedSubcategory:
                                                          _selectedSubcategory,
                                                      produtos: produtos,
                                                      textColor: textColor,
                                                      cardColor: cardColor,
                                                      primaryColor:
                                                          primaryColor,
                                                      verticalLayout: true,
                                                      onCategorySelectedNull:
                                                          () {
                                                        setState(() {
                                                          _selectedCategory =
                                                              null;
                                                          _selectedSubcategory =
                                                              null;
                                                          _currentPageNotifier
                                                              .value = 0;
                                                        });
                                                      },
                                                      onCategorySelected:
                                                          (cat) {
                                                        setState(() {
                                                          _selectedCategory =
                                                              cat;
                                                          _selectedSubcategory =
                                                              null;
                                                          _currentPageNotifier
                                                              .value = 0;
                                                        });
                                                      },
                                                      onSubcategorySelectedNull:
                                                          () {
                                                        setState(() {
                                                          _selectedSubcategory =
                                                              null;
                                                          _currentPageNotifier
                                                              .value = 0;
                                                        });
                                                      },
                                                      onSubcategorySelected:
                                                          (subcat) {
                                                        setState(() {
                                                          _selectedSubcategory =
                                                              subcat;
                                                          _currentPageNotifier
                                                              .value = 0;
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(child: scrollBody),
                                          ],
                                        );
                                      }
                                      return scrollBody;
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: _scrollOffsetNotifier,
                        builder: (context, offset, _) {
                          if (offset < 300) return const SizedBox.shrink();
                          final primaryColor =
                              Theme.of(context).colorScheme.primary;
                          return Positioned(
                            left: 16,
                            bottom: _cart.isEmpty ? 24 : 88,
                            child: Material(
                              elevation: 4,
                              color: primaryColor.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(28),
                              child: InkWell(
                                onTap: () => _catalogScrollController.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOut,
                                ),
                                borderRadius: BorderRadius.circular(28),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(Icons.vertical_align_top,
                                      color: Colors.white, size: 24),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

void mpLogStoreDiag({
  required String tag,
  required String lojaId,
  String? slug,
  bool? preview,
  String? cfgPath,
  String? produtosPath,
}) {
  logD('━━━━━━━━━━━━ STORE-DIAG ━━━━━━━━━━━━');
  logD('[$tag] (store resolvido)');
  logD('[$tag] slug=${slug ?? "(null)"}');
  logD('[$tag] preview=${preview ?? "(null)"}');
  if (cfgPath != null) logD('[$tag] cfgPath=$cfgPath');
  if (produtosPath != null) logD('[$tag] produtosPath=$produtosPath');
  logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}
