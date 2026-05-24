// lib/screens/public_catalog_screen.dart
// Catálogo público (WEB/Mobile) – carrinho funcional, banners rolando,
// checkout (login opcional) e botão WhatsApp / Mercado Pago.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:connectivity_plus/connectivity_plus.dart';

import '../utils/http_client_helper.dart';
import '../utils/mp_checkout_error_messages.dart';
import '../widgets/smart_image.dart';
import '../services/store_resolver_facade.dart';
import '../widgets/campanha_banner_widget.dart';
import '../services/catalogo_venda_service.dart';
import '../services/pre_pedido_service.dart';
import 'auth/login_screen_cliente.dart';
import 'package:master_palm/screens/auth/cadastro_screen_cliente.dart';
import 'auth/perfil_cliente_screen_novo.dart';
import '../services/cliente_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/catalog_cache_service.dart';
import '../services/catalog_config_published_v3_bridge.dart';
import '../services/catalog_recent_service.dart';
import '../services/catalog_public_url_service.dart';
import '../services/catalog_share_service.dart';
import '../services/catalog_visitas_service.dart';
import '../services/pagamentos_service.dart';

import '../utils/instagram_launcher.dart';
import '../utils/pix_brcode.dart';
import '../widgets/pix_qr_dialog.dart' show showPixQrDialog;
import '../core/combo_config_canonical.dart';
import '../catalog/catalog_layout_config.dart';
import '../debug/catalog_normal_trace.dart';
import '../debug/catalog_startup_trace.dart';
import 'public_catalog/catalog_helpers.dart';
import 'public_catalog/catalog_public_header_debug.dart';
import 'public_catalog/catalog_best_sellers_helper.dart';
import 'public_catalog/catalog_product_card_size.dart';
import 'public_catalog/catalog_estoque_helper.dart';
import 'public_catalog/catalog_config_service.dart'
    show
        mergeCatalogFretesManualFromFirestoreSubdoc,
        parseCupons,
        parseFretes,
        parseMedia;
import '../utils/platform_adaptive.dart';
import '../utils/safe_parse.dart';
import '../web/platform_stub.dart'
    if (dart.library.html) '../web/platform_web.dart' as plat;
import 'public_catalog/catalog_theme_extension.dart';
import 'public_catalog/catalog_theme.dart';
import 'public_catalog/catalog_checkout_summary_tokens.dart';
import 'public_catalog/catalog_cart_checkout_visual_config.dart';
import 'public_catalog/widgets/catalog_banner_carousel.dart';
import 'public_catalog/widgets/catalog_config_error_state.dart';
import 'public_catalog/widgets/catalog_config_loading_state.dart';
import 'public_catalog/widgets/catalog_early_shell_view.dart';
import 'public_catalog/widgets/catalog_empty_products_state.dart';
import 'public_catalog/widgets/catalog_error_loja_state.dart';
import 'public_catalog/widgets/catalog_footer.dart';
import 'public_catalog/widgets/catalog_creator_credit_bar.dart';
import 'public_catalog/widgets/catalog_loading_state.dart';
import 'public_catalog/widgets/catalog_search_filters_bar.dart';
import 'public_catalog/catalog_variation_filter.dart';
import 'public_catalog/catalog_url_query_codec.dart';
import 'public_catalog/catalog_deep_link_resolve.dart';
import 'public_catalog/catalog_url_variation_sync.dart';
import 'public_catalog/widgets/catalog_products_grid_sliver.dart';
import 'public_catalog/widgets/catalog_recent_section_sliver.dart';
import 'public_catalog/widgets/catalog_avaliacoes_section.dart';
import 'public_catalog/widgets/catalog_skeleton_grid.dart';
import 'public_catalog/widgets/catalog_minimalist_widgets.dart';
import 'public_catalog/widgets/catalog_minimal_best_sellers.dart';
import 'public_catalog/widgets/catalog_product_detail_screen.dart';
import 'public_catalog/widgets/carrinho_sheet_web.dart';
import 'public_catalog/catalog_dicas_screen.dart';
import 'public_catalog/catalog_sobre_loja_screen.dart';
import '../core/logger.dart';
import '../core/plan_matrix.dart';
import '../models/catalog_avaliacoes_ordem.dart';
import '../models/catalog_sobre_loja_config.dart';

// ===================================================================
// CACHE CATÁLOGO – Reduz leituras Firestore (TTL 3–5 min)
// Web público: [_cfgStream] emite o config do doc assim que o snapshot chega (pós-bridge V3)
// e, em seguida, reaplica merge de payments/fretes/legado/loja/cupons em paralelo.
// ===================================================================
const bool _useCatalogCache =
    true; // Mobile/desktop público: cache; Preview e Web público: stream direto
const String _catalogMaintenanceDefaultMessage =
    'Estamos preparando algo incrível para você ter a melhor experiência.';
const String _catalogMaintenanceWhatsappPrefill =
    'Olá! Vim pelo catálogo e gostaria de comprar pelo WhatsApp.';

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

  /// ✅ ID ou slug do produto para abrir direto (ex.: `?prod=` ou legado `?produto=`)
  final String? initialProdutoId;

  /// ✅ Mesmo propósito que [initialProdutoId], via query `prod` (rotas nomeadas / deep link).
  final String? initialProd;

  /// ✅ Filtro de variação na URL (?tam=) — na Web costuma vir de [Uri.base]; no app, da rota.
  final String? initialTam;

  /// ✅ Filtro de variação na URL (?cor=)
  final String? initialCor;

  /// ✅ Filtro de variação extra na URL (`xv` = [extraValor])
  final String? initialXv;

  /// ✅ Categoria / subcategoria / ordenação / preço na URL (?cat= & ?sub= & ?ord= & ?pmin= & ?pmax=)
  final String? initialCat;
  final String? initialSub;
  final String? initialOrd;
  final String? initialPmin;
  final String? initialPmax;

  /// ✅ Busca textual na URL (?q=)
  final String? initialQ;

  /// ✅ Página do grid (1-based), quando `page` na URL é numérico — não confundir com [initialPage] (`page=dicas`).
  final int? initialCatalogPage;

  /// No modo [preview], tier do admin para subgates (WhatsApp-only no free/básico).
  final PlanAccessTier? adminPreviewTier;

  const PublicCatalogScreen({
    super.key,
    required this.lojaId,
    this.preview = false,
    this.vendedorRef,
    this.indicacaoClienteRef,
    this.initialPage,
    this.initialCartId,
    this.initialProdutoId,
    this.initialProd,
    this.initialTam,
    this.initialCor,
    this.initialXv,
    this.initialCat,
    this.initialSub,
    this.initialOrd,
    this.initialPmin,
    this.initialPmax,
    this.initialQ,
    this.initialCatalogPage,
    this.adminPreviewTier,
  });

  @override
  State<PublicCatalogScreen> createState() => _PublicCatalogScreenState();
}

/// Produtos por página no catálogo
const int _produtosPorPagina = 20;

/// cacheExtent do grid: Web alto demais materializa cards extras (jank em Android fraco).
double _catalogProductsScrollCacheExtent() {
  if (kIsWeb) return 1000;
  return 800;
}

/// Processa docs Firestore em lista de produtos (evita bloquear UI no build).
List<Map<String, dynamic>> _processDocsToProducts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final produtos = <Map<String, dynamic>>[];
  for (final d in docs) {
    try {
      final m = asMapDeep(d.data());
      if (m.isEmpty) continue;
      if (!CatalogEstoqueHelper.catalogoWebDocPublicado(m)) continue;

      final bool exibirCatalogo = !(m['exibir_no_catalogo'] == false ||
          m['ocultar_catalogo'] == true ||
          m['catalog_ativo'] == false);
      if (!exibirCatalogo) continue;

      final tipoEarly = (m['tipoProduto'] ?? m['tipo'] ?? 'simples').toString();
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

      final categoriaRaw =
          (m['categoria'] ?? m['categoria_nome'] ?? m['categoriaNome'] ?? '')
              .toString()
              .trim();
      final subcategoriaRaw = (m['subcategoria'] ??
              m['subcategoriaId'] ??
              m['subcategoria_nome'] ??
              '')
          .toString()
          .trim();
      final categoria = (isComboEarly && categoriaRaw.toLowerCase() == 'combo')
          ? ''
          : categoriaRaw;
      final subcategoria =
          (isComboEarly && subcategoriaRaw.toLowerCase() == 'combo')
              ? ''
              : subcategoriaRaw;
      List<String> parseStringList(dynamic raw) {
        if (raw is! List) return const [];
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      List<String> dedupeKeepOrder(Iterable<String> values) {
        final out = <String>[];
        final seen = <String>{};
        for (final v in values) {
          final n = v.toLowerCase();
          if (seen.add(n)) out.add(v);
        }
        return out;
      }

      bool omitarRotuloCombo(String s) {
        final t = s.trim();
        if (t.isEmpty) return false;
        return isComboEarly && t.toLowerCase() == 'combo';
      }

      final categoriasAssociadas = dedupeKeepOrder([
        if (categoria.isNotEmpty) categoria,
        ...parseStringList(m['categoriasAssociadas'])
            .where((s) => !omitarRotuloCombo(s)),
        ...parseStringList(m['categoriasExtras'])
            .where((s) => !omitarRotuloCombo(s)),
      ]);
      final subcategoriasAssociadas = dedupeKeepOrder([
        if (subcategoria.isNotEmpty) subcategoria,
        ...parseStringList(m['subcategoriasAssociadas'])
            .where((s) => !omitarRotuloCombo(s)),
        ...parseStringList(m['subcategoriasExtras'])
            .where((s) => !omitarRotuloCombo(s)),
      ]);

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
          final idItem = (e['id'] ?? e['produtoId'] ?? e['productId'] ?? '')
              .toString()
              .trim();
          final row = <String, dynamic>{
            'nome': nomeItem,
            'slug': slugItem,
            'quantidade': (e['quantidade'] is num)
                ? (e['quantidade'] as num).toInt()
                : int.tryParse('${e['quantidade']}') ?? 1,
            if (idItem.isNotEmpty) 'id': idItem,
            if (idItem.isNotEmpty) 'productId': idItem,
            if ((e['tamanho'] ?? '').toString().trim().isNotEmpty)
              'tamanho': (e['tamanho'] ?? '').toString().trim(),
            if ((e['cor'] ?? '').toString().trim().isNotEmpty)
              'cor': (e['cor'] ?? '').toString().trim(),
          };
          for (final k in [
            'variacoes',
            'estoquePorTamanho',
            'estoquePorCor',
            'precoPorTamanho',
            'preco',
            'precoFinal',
            'tamanhos',
            'cores',
            'variacoesExtraTipo',
          ]) {
            final v = e[k];
            if (v != null) row[k] = v;
          }
          itensCombo.add(row);
        }
        if (itensCombo.isEmpty) itensCombo = null;
      }
      final tipoProduto =
          (m['tipoProduto'] ?? m['tipo'] ?? 'simples').toString();
      final comboConfigCatalogo =
          ComboConfigCanonical.parseFromFirestore(m['comboConfig']);

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
        'categoriasAssociadas': categoriasAssociadas,
        'subcategoriasAssociadas': subcategoriasAssociadas,
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
        if (m['variacoesExtraTipo'] != null &&
            m['variacoesExtraTipo'] is Map &&
            (m['variacoesExtraTipo'] as Map).isNotEmpty)
          'variacoesExtraTipo': asMapDeep(m['variacoesExtraTipo']),
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
        if (comboConfigCatalogo != null) 'comboConfig': comboConfigCatalogo,
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
///
/// Por defeito **não** substitui o preço já vindo do estoque/publicação (`precoFinal` / `preco`).
/// Só recalcula pela soma quando não há preço cadastrado válido ou quando o documento pede
/// explicitamente com `precoComboCalcularPelaSoma` / `precoComboUsarSomaItens` == true.
void _aplicarPrecoComboFromSoma(List<Map<String, dynamic>> produtos) {
  for (final p in produtos) {
    final itens = p['itensCombo'];
    if (itens is! List || itens.isEmpty) continue;

    final forcarSoma = p['precoComboCalcularPelaSoma'] == true ||
        p['precoComboUsarSomaItens'] == true;
    if (!forcarSoma) {
      final pf = p['precoFinal'];
      final pr = p['preco'];
      final baseEstoque = (pf is num && pf.toDouble() > 0.009)
          ? pf.toDouble()
          : ((pr is num) ? pr.toDouble() : 0.0);
      if (baseEstoque > 0.009) {
        continue;
      }
    }

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

/// [childAspectRatio] do grid clássico (cross / main): maior = célula menos alta.
/// Só mobile estreito; em [width] ≥ 640 mantém [baseStandardAspectRatio] (ex.: small/medium/large).
double _classicCatalogGridAspectRatio({
  required double width,
  required double baseStandardAspectRatio,
}) {
  if (width >= 640) return baseStandardAspectRatio;
  if (width < 360) return baseStandardAspectRatio + 0.065;
  return baseStandardAspectRatio + 0.04;
}

/// Grid minimalista: em desktop a célula alta deixa faixa vazia no rodapé do card.
/// Só altera quando [isDesktopBody]; mobile mantém [baseFromSizeOrConfig] intacto.
double _minimalCatalogGridAspectRatio({
  required bool isDesktopBody,
  required double baseFromSizeOrConfig,
}) {
  if (!isDesktopBody) return baseFromSizeOrConfig;
  return (baseFromSizeOrConfig + 0.045).clamp(0.30, 0.52);
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
  String? _filtroVariacaoTamanho;
  String? _filtroVariacaoCor;

  /// Filtro opcional por valor de personalização (ex.: estampa, letra).
  String? _filtroVariacaoExtra;

  /// Valores vindos da URL aguardando produtos/opções para validação.
  String? _pendingUrlCat;
  String? _pendingUrlSub;
  String? _pendingUrlOrd;
  String? _pendingUrlPmin;
  String? _pendingUrlPmax;
  String? _pendingUrlTam;
  String? _pendingUrlCor;
  String? _pendingUrlXv;

  /// Página 1-based vinda da URL, aplicada após conhecer [totalPaginas].
  int? _pendingUrlCatalogPage;
  int _catalogTotalPaginasForUrl = 1;

  /// Web: valor de `prod=` na URL (slug preferencial, senão id).
  String? _catalogUrlProd;
  String _lastCatalogSanitizeSig = '';
  int _catalogSanitizeGen = 0;

  /// Merge draft/published para [CatalogPublicUrlService] (domínio próprio nos links).
  Map<String, dynamic> _catalogUrlConfigMerge = const {};

  /// Descarta respostas antigas de [mergeDraftConfigDomainForCatalogUrls].
  int _catalogUrlDraftEnrichSeq = 0;

  // ✅ FONTE ÚNICA: lojaId resolvido de forma assíncrona
  String? _resolvedLojaId;
  bool _loadingLojaId = true;
  /// Exposto em [CatalogErrorLojaState] quando a loja não abre (ex.: flags / resolver).
  String? _catalogOpenFailureDetail;
  bool _traceFirstUsefulPaintLogged = false;
  bool _traceInteractiveLogged = false;
  bool _traceConfigFirstDataLogged = false;
  bool _traceProdutosFirstDataLogged = false;
  bool _traceBuildEnteredLogged = false;
  bool _traceConfigWaitingLogged = false;
  bool _traceConfigReadyLogged = false;
  bool _traceHeaderReadyLogged = false;
  bool _traceProductsWaitingLogged = false;
  bool _traceProductsDataReadyLogged = false;
  bool _traceProductsVisibleLogged = false;
  bool _traceProductsGridFirstViewportLogged = false;
  bool _traceEssentialActionsEnabledLogged = false;
  bool _htmlLoaderHandoffDone = false;
  bool _traceShellFirstFrameLogged = false;
  late final bool _diagCatStartOverlayEnabled =
      kIsWeb && Uri.base.queryParameters['diag'] == '1';

  /// `?diag=1` ou `?traceCatalog=1` — painel técnico no fallback (localStorage + UI).
  late final bool _catalogTechnicalDiagEnabled = kIsWeb &&
      (Uri.base.queryParameters['diag'] == '1' ||
          Uri.base.queryParameters['traceCatalog'] == '1');

  bool _normalTraceRenderCatalogStartLogged = false;
  bool _normalTraceRenderSuccessLogged = false;

  final List<Map<String, dynamic>> _cart = [];
  bool _publicando = false;

  /// Último pré-pedido criado nesta sessão do carrinho (evita vários pedidos ao trocar forma de pagamento)
  String? _ultimoPrePedidoId;
  Map<String, dynamic>? _ultimoPrePedidoData;

  /// Evita reutilizar documento após mudança material (cupom, frete, total, canal, dados do cliente).
  String? _prePedidoReuseFingerprint;

  /// `whatsapp` | `mercadopago` — alinhado a [origemCheckout] do pré-pedido.
  String? _prePedidoReuseCanal;

  /// Estado da roleta (persiste ao fechar/reabrir o carrinho; reseta em nova compra)
  bool _roletaJaGirada = false;
  String? _cupomRoletaCodigo;
  double? _cupomRoletaDesconto;
  String? _premioRoletaDescricao;
  bool _freteGratisRoleta = false;

  int _refreshCounter = 0;

  /// Recria o [FutureBuilder] do menu (sessão cliente) após falha de rede/leitura.
  int _menuClienteAuthRetryKey = 0;
  bool _isOffline = false;
  List<String> _recentIds = [];
  List<String> _favoritosIds = [];
  String _lastProdutosDocsSig = '';
  List<Map<String, dynamic>> _lastProdutosProcessados = const [];
  String _catalogListaOrdenadaCacheSig = '';
  List<Map<String, dynamic>> _catalogListaOrdenadaCache = const [];
  String _lastCartCleanupSig = '';
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

  bool get _adminPreviewRestrictsPayments {
    if (!widget.preview || widget.adminPreviewTier == null) return false;
    final t = widget.adminPreviewTier!;
    return t == PlanAccessTier.freeLimited || t == PlanAccessTier.basic;
  }

  bool get _previewHideAvaliacoesForAdmin {
    if (!widget.preview || widget.adminPreviewTier == null) return false;
    return widget.adminPreviewTier == PlanAccessTier.freeLimited;
  }

  String _buildProdutosDocsSig(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return 'empty';
    final b = StringBuffer()..write(docs.length);
    for (final d in docs) {
      final m = d.data();
      final updatedAt = m['updatedAt'];
      final qty = m['quantidade'];
      b
        ..write('|')
        ..write(d.id)
        ..write(':')
        ..write(updatedAt is Timestamp ? updatedAt.millisecondsSinceEpoch : 0)
        ..write(':')
        ..write(qty ?? '');
    }
    return b.toString();
  }

  List<Map<String, dynamic>> _processDocsToProductsCached(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sig = _buildProdutosDocsSig(docs);
    if (sig == _lastProdutosDocsSig) return _lastProdutosProcessados;
    final processed =
        docs.isEmpty ? <Map<String, dynamic>>[] : _processDocsToProducts(docs);
    _lastProdutosDocsSig = sig;
    _lastProdutosProcessados = processed;
    return processed;
  }

  List<Map<String, dynamic>> _cuponsParaPreviaCart(
    List<Map<String, dynamic>> cupons,
  ) {
    if (!_adminPreviewRestrictsPayments) return cupons;
    return <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _fretesParaPreviaCart(
    List<Map<String, dynamic>> fretes,
  ) {
    if (!_adminPreviewRestrictsPayments) return fretes;
    return <Map<String, dynamic>>[];
  }

  String _gatewayParaPreviaCart(String gateway) {
    if (!_adminPreviewRestrictsPayments) return gateway;
    return 'whatsapp';
  }

  List<String> _paymentCodesParaPreviaRodape(List<String> codes) {
    if (!_adminPreviewRestrictsPayments) return codes;
    return <String>[];
  }

  static const Color _successColor = Color(0xFF22C55E);

  /// Cache de streams (evita recriação a cada rebuild = piscar)
  Stream<Map<String, dynamic>>? _cachedConfigStream;
  String? _cachedConfigStreamKey;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedProdutosStream;
  String? _cachedProdutosStreamKey;

  /// Formulário do checkout (prefs) em memória — evita await antes de abrir o carrinho.
  Map<String, dynamic>? _cachedCatalogCartForm;

  /// [SAFE_SETSTATE] Atualiza estado do catálogo após o frame (evita "widget tree was locked" com sheet/dialog).
  void _safeSetStateAfterFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fn();
    });
  }

  /// Como [_safeSetStateAfterFrame], mas permite `await` antes da próxima etapa (ex.: abrir link de pagamento).
  Future<void> _runStateAfterFrame(VoidCallback fn) {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      fn();
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Stream<Map<String, dynamic>> _getConfigStream(String lojaId) {
    final key = '${lojaId}_${widget.preview}';
    if (_cachedConfigStreamKey == key && _cachedConfigStream != null) {
      return _cachedConfigStream!;
    }
    _cachedConfigStreamKey = key;
    _cachedConfigStream = _useCatalogCache && !widget.preview && !kIsWeb
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
    // Estoque/disponibilidade: snapshots em tempo real (sem TTL do cache de produtos).
    // Config: na Web pública usa [_cfgStream]; em app nativo pode usar CatalogCacheService.
    _cachedProdutosStream = _produtosStream(lojaId);
    return _cachedProdutosStream!;
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      plat.Web.localStorageSet('mp_catalog_phase', 'publicCatalogScreen.init');
      CatalogNormalTrace.beginSession(widget.lojaId, preview: widget.preview);
    }
    CatalogStartupTrace.mark(
      'CAT_START.public_screen.init_state',
      data: <String, Object?>{
        'loja_id_raw': widget.lojaId,
        'preview': widget.preview,
        'is_web': kIsWeb,
      },
    );
    _initPendingCatalogFiltersFromUrl();
    _currentPageNotifier.addListener(_onCatalogPageNotifierChanged);
    _catalogScrollController.addListener(_onCatalogScroll);
    _resolveLojaId().catchError((e, st) {
      logD(
          '❌ [CATÁLOGO] Erro não tratado em _resolveLojaId (type=${e.runtimeType})');
      CatalogNormalTrace.setField('fallback.reason', 'resolve_catchError');
      if (mounted) {
        setState(() {
          _loadingLojaId = false;
          _resolvedLojaId = null;
          _catalogOpenFailureDetail =
              e is TimeoutException ? (e.message ?? 'Tempo esgotado') : e.toString();
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

  /// Visitas, recentes e cliente/favoritos não devem atrasar a 1ª pintura útil.
  void _deferSecondaryPublicCatalogLoads() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRecentIds();
      _loadClienteAndFavoritos();
      final lid = _resolvedLojaId;
      if (!widget.preview && lid != null && lid.isNotEmpty) {
        CatalogVisitasService.incrementarVisita(lid);
      }
    });
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
      _syncCatalogQueryToBrowserUri();
    });
  }

  void _initPendingCatalogFiltersFromUrl() {
    String? cat;
    String? sub;
    String? ord;
    String? pmin;
    String? pmax;
    String? t;
    String? c;
    String? xv;
    String? qFromUri;
    int? pageFromUri;
    String? prodFromUri;
    if (kIsWeb) {
      final qp = Uri.base.queryParameters;
      cat = qp['cat']?.trim();
      sub = qp['sub']?.trim();
      ord = qp['ord']?.trim();
      pmin = qp['pmin']?.trim();
      pmax = qp['pmax']?.trim();
      final qt = qp['tam']?.trim();
      final qc = qp['cor']?.trim();
      if (qt != null && qt.isNotEmpty) t = qt;
      if (qc != null && qc.isNotEmpty) c = qc;
      final qxv = catalogSanitizeXvQuery(qp['xv']);
      if (qxv != null && qxv.isNotEmpty) xv = qxv;
      qFromUri = catalogSanitizeSearchQuery(qp['q']);
      final pageParam = qp['page']?.trim();
      if (pageParam != null && pageParam.isNotEmpty) {
        pageFromUri = catalogParsePaginationPageQuery(pageParam);
      }
      prodFromUri = catalogSanitizeProdQuery(qp['prod']) ??
          catalogSanitizeProdQuery(qp['produto']);
    }
    final ic = widget.initialCat?.trim();
    final iSub = widget.initialSub?.trim();
    final io = widget.initialOrd?.trim();
    final ipmin = widget.initialPmin?.trim();
    final ipmax = widget.initialPmax?.trim();
    if (cat == null || cat.isEmpty) {
      if (ic != null && ic.isNotEmpty) cat = ic;
    }
    if (sub == null || sub.isEmpty) {
      if (iSub != null && iSub.isNotEmpty) sub = iSub;
    }
    if (ord == null || ord.isEmpty) {
      if (io != null && io.isNotEmpty) ord = io;
    }
    if (pmin == null || pmin.isEmpty) {
      if (ipmin != null && ipmin.isNotEmpty) pmin = ipmin;
    }
    if (pmax == null || pmax.isEmpty) {
      if (ipmax != null && ipmax.isNotEmpty) pmax = ipmax;
    }
    final wt = widget.initialTam?.trim();
    final wc = widget.initialCor?.trim();
    final wxv = catalogSanitizeXvQuery(widget.initialXv);
    if (t == null || t.isEmpty) {
      if (wt != null && wt.isNotEmpty) t = wt;
    }
    if (c == null || c.isEmpty) {
      if (wc != null && wc.isNotEmpty) c = wc;
    }
    if (xv == null || xv.isEmpty) {
      if (wxv != null && wxv.isNotEmpty) xv = wxv;
    }
    void nz(String? s, void Function(String) set) {
      if (s != null && s.isNotEmpty) set(s);
    }

    _pendingUrlCat = null;
    _pendingUrlSub = null;
    _pendingUrlOrd = null;
    _pendingUrlPmin = null;
    _pendingUrlPmax = null;
    nz(cat, (v) => _pendingUrlCat = v);
    nz(sub, (v) => _pendingUrlSub = v);
    nz(ord, (v) => _pendingUrlOrd = v);
    nz(pmin, (v) => _pendingUrlPmin = v);
    nz(pmax, (v) => _pendingUrlPmax = v);
    _pendingUrlTam = (t != null && t.isNotEmpty) ? t : null;
    _pendingUrlCor = (c != null && c.isNotEmpty) ? c : null;
    _pendingUrlXv = (xv != null && xv.isNotEmpty) ? xv : null;
    _pendingUrlCatalogPage = pageFromUri;
    if (_pendingUrlCatalogPage == null &&
        widget.initialCatalogPage != null &&
        widget.initialCatalogPage! >= 1) {
      _pendingUrlCatalogPage = widget.initialCatalogPage;
    }

    var qInit = qFromUri;
    if (qInit == null || qInit.isEmpty) {
      qInit = catalogSanitizeSearchQuery(widget.initialQ);
    }
    if (qInit != null && qInit.isNotEmpty) {
      _searchController.text = qInit;
      _searchNotifier.value = qInit.toLowerCase();
    }

    final ip = widget.initialProdutoId?.trim();
    final iprod = widget.initialProd?.trim();
    _pendingInitialProdutoId = prodFromUri ??
        (ip != null && ip.isNotEmpty ? ip : null) ??
        (iprod != null && iprod.isNotEmpty ? iprod : null);
  }

  String _categoryAliasesSignature(Map<String, Set<String>> m) {
    if (m.isEmpty) return '';
    final keys = m.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final vals = (m[k] ?? {}).toList()..sort();
      parts.add('$k:${vals.join(',')}');
    }
    return parts.join('|');
  }

  String? _canonicalCategoriaMenuDeUrl(
    String raw,
    List<String> categoriasMenu,
    Map<String, Set<String>> aliasesByName,
  ) {
    final r = raw.trim();
    if (r.isEmpty) return null;
    for (final c in categoriasMenu) {
      if (c == r) return c;
    }
    for (final c in categoriasMenu) {
      if (c.toLowerCase() == r.toLowerCase()) return c;
    }
    final lr = r.toLowerCase();
    for (final c in categoriasMenu) {
      final al = aliasesByName[c];
      if (al == null) continue;
      for (final a in al) {
        if (a.toLowerCase() == lr) return c;
      }
    }
    return null;
  }

  List<String> _subcategoriasDisponiveisParaCategoria(
    String? cat,
    List<Map<String, dynamic>> produtos,
  ) {
    if (cat == null || cat.isEmpty) return const [];
    final set = <String>{};
    for (final p in produtos) {
      if (!_produtoTemCategoria(p, cat)) continue;
      for (final s in _produtoSubcategoriasAssociadas(p)) {
        if (s.isNotEmpty) set.add(s);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> _stringListFromAny(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _dedupeLowerKeepOrder(Iterable<String> values) {
    final out = <String>[];
    final seen = <String>{};
    for (final v in values) {
      final t = v.trim();
      if (t.isEmpty) continue;
      final n = t.toLowerCase();
      if (seen.add(n)) out.add(t);
    }
    return out;
  }

  List<String> _produtoCategoriasAssociadas(Map<String, dynamic> p) {
    final cat = (p['categoria'] ?? p['categoriaId'] ?? '').toString().trim();
    final fromAssoc = _stringListFromAny(p['categoriasAssociadas']);
    final fromExtras = _stringListFromAny(p['categoriasExtras']);
    final tipo = (p['tipoProduto'] ?? p['tipo'] ?? 'simples')
        .toString()
        .trim()
        .toLowerCase();
    final ehComboTipo = tipo == 'combo';
    bool skipRotuloComboImplicito(String s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      // Produto combo: "Combo" não é categoria do tipo — só entra no menu se o lojista escolher outro nome.
      return ehComboTipo && t.toLowerCase() == 'combo';
    }

    return _dedupeLowerKeepOrder([
      if (!skipRotuloComboImplicito(cat)) cat,
      ...fromAssoc.where((s) => !skipRotuloComboImplicito(s)),
      ...fromExtras.where((s) => !skipRotuloComboImplicito(s)),
    ]);
  }

  List<String> _produtoSubcategoriasAssociadas(Map<String, dynamic> p) {
    final sub =
        (p['subcategoria'] ?? p['subcategoriaId'] ?? '').toString().trim();
    final fromAssoc = _stringListFromAny(p['subcategoriasAssociadas']);
    final fromExtras = _stringListFromAny(p['subcategoriasExtras']);
    final tipo = (p['tipoProduto'] ?? p['tipo'] ?? 'simples')
        .toString()
        .trim()
        .toLowerCase();
    final ehComboTipo = tipo == 'combo';
    bool skipRotuloComboImplicito(String s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      return ehComboTipo && t.toLowerCase() == 'combo';
    }

    return _dedupeLowerKeepOrder([
      if (!skipRotuloComboImplicito(sub)) sub,
      ...fromAssoc.where((s) => !skipRotuloComboImplicito(s)),
      ...fromExtras.where((s) => !skipRotuloComboImplicito(s)),
    ]);
  }

  bool _produtoTemCategoria(Map<String, dynamic> p, String? categoria) {
    if (categoria == null || categoria.isEmpty) return true;
    return _produtoCategoriasAssociadas(p).contains(categoria);
  }

  bool _produtoTemSubcategoria(Map<String, dynamic> p, String? subcategoria) {
    if (subcategoria == null || subcategoria.isEmpty) return true;
    return _produtoSubcategoriasAssociadas(p).contains(subcategoria);
  }

  /// Categoria "Todos" / vazia / sinônimos: mesma experiência da home (banners, mais vendidos, etc.).
  String? _effectiveCatalogCategoryFilter() {
    final c = _selectedCategory?.trim();
    if (c == null || c.isEmpty) return null;
    final lower = c.toLowerCase();
    if (lower == 'todos' || lower == 'todas' || lower == 'all') {
      return null;
    }
    return c;
  }

  String? _effectiveCatalogSubcategoryFilter() {
    if (_effectiveCatalogCategoryFilter() == null) return null;
    final s = _selectedSubcategory?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  bool _catalogExibindoTodosCategorias() =>
      _effectiveCatalogCategoryFilter() == null;

  void _scheduleCatalogScrollToTopAfterFilter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_catalogScrollController.hasClients) {
        _catalogScrollController.jumpTo(0);
      }
    });
  }

  void _onCatalogCategoryOrSubChanged() {
    _syncCatalogQueryToBrowserUri();
    _scheduleCatalogScrollToTopAfterFilter();
  }

  String? _catalogListagemTituloLinha() {
    final c = _effectiveCatalogCategoryFilter();
    if (c == null) return null;
    final s = _effectiveCatalogSubcategoryFilter();
    if (s == null) return c;
    return '$c / $s';
  }

  bool _catalogSemFiltrosAlemDeCategoria(String search) {
    final t = _filtroVariacaoTamanho?.trim();
    final co = _filtroVariacaoCor?.trim();
    final xv = _filtroVariacaoExtra?.trim();
    return search.trim().isEmpty &&
        !_apenasEmEstoque &&
        (t == null || t.isEmpty) &&
        (co == null || co.isEmpty) &&
        (xv == null || xv.isEmpty) &&
        _precoMin == null &&
        _precoMax == null;
  }

  String? _canonicalSubcategoriaNaLista(String raw, List<String> subs) {
    final r = raw.trim();
    if (r.isEmpty) return null;
    for (final s in subs) {
      if (s == r) return s;
    }
    for (final s in subs) {
      if (s.toLowerCase() == r.toLowerCase()) return s;
    }
    return null;
  }

  void _syncCatalogQueryToBrowserUri() {
    if (!kIsWeb) return;
    final ord = catalogOrdInternalIsValid(_ordenacaoProdutos)
        ? _ordenacaoProdutos
        : 'nome';
    catalogSyncPublicCatalogQueryUri(
      cat: _selectedCategory,
      sub: _selectedSubcategory,
      ord: ord,
      pmin: catalogFormatPrecoQuery(_precoMin),
      pmax: catalogFormatPrecoQuery(_precoMax),
      tam: _filtroVariacaoTamanho,
      cor: _filtroVariacaoCor,
      xv: catalogSanitizeXvQuery(_filtroVariacaoExtra),
      q: catalogSanitizeSearchQuery(_searchController.text),
      page: catalogFormatPaginationPageQuery(
        zeroBasedPage: _currentPageNotifier.value,
        totalPaginas: _catalogTotalPaginasForUrl,
      ),
      prod: catalogSanitizeProdQuery(_catalogUrlProd),
    );
  }

  /// Retorna o rótulo canônico da lista de opções se [raw] casar (normalização).
  String? _canonicalVariationInOptions(String raw, List<String> options) {
    final r = raw.trim();
    if (r.isEmpty) return null;
    for (final o in options) {
      if (CatalogVariationFilter.keysMatch(o, r)) {
        return o;
      }
    }
    return null;
  }

  void _sanitizeCatalogUrlDerivedFilters({
    required List<String> categoriasMenu,
    required Map<String, Set<String>> categoryAliasesByName,
    required List<Map<String, dynamic>> produtos,
    required List<String> tamanhos,
    required List<String> cores,
    required List<String> extras,
    required int totalPaginas,
  }) {
    if (!mounted) {
      return;
    }

    var cat = _selectedCategory;
    var sub = _selectedSubcategory;
    var ord = _ordenacaoProdutos;
    var pmin = _precoMin;
    var pmax = _precoMax;
    var tam = _filtroVariacaoTamanho;
    var cor = _filtroVariacaoCor;
    var xv = _filtroVariacaoExtra;

    var changed = false;
    var mustSyncUri = false;

    final pCat = _pendingUrlCat;
    _pendingUrlCat = null;
    if (pCat != null) {
      final c = _canonicalCategoriaMenuDeUrl(
          pCat, categoriasMenu, categoryAliasesByName);
      if (c != null) {
        if (cat != c) {
          cat = c;
          changed = true;
        }
      } else {
        mustSyncUri = true;
        if (cat != null) {
          cat = null;
          changed = true;
        }
      }
    }

    final pSub = _pendingUrlSub;
    _pendingUrlSub = null;
    if (pSub != null) {
      if (cat == null || cat.isEmpty) {
        mustSyncUri = true;
        if (sub != null) {
          sub = null;
          changed = true;
        }
      } else {
        final subs = _subcategoriasDisponiveisParaCategoria(cat, produtos);
        final sc = _canonicalSubcategoriaNaLista(pSub, subs);
        if (sc != null) {
          if (sub != sc) {
            sub = sc;
            changed = true;
          }
        } else {
          mustSyncUri = true;
          if (sub != null) {
            sub = null;
            changed = true;
          }
        }
      }
    }

    if (cat != null) {
      final c = _canonicalCategoriaMenuDeUrl(
          cat, categoriasMenu, categoryAliasesByName);
      if (c == null) {
        cat = null;
        sub = null;
        changed = true;
        mustSyncUri = true;
      } else if (c != cat) {
        cat = c;
        changed = true;
        mustSyncUri = true;
      }
    }

    if (sub != null) {
      if (cat == null || cat.isEmpty) {
        sub = null;
        changed = true;
        mustSyncUri = true;
      } else {
        final subs = _subcategoriasDisponiveisParaCategoria(cat, produtos);
        final sc = _canonicalSubcategoriaNaLista(sub, subs);
        if (sc == null) {
          sub = null;
          changed = true;
          mustSyncUri = true;
        } else if (sc != sub) {
          sub = sc;
          changed = true;
          mustSyncUri = true;
        }
      }
    }

    final pOrd = _pendingUrlOrd;
    _pendingUrlOrd = null;
    if (pOrd != null) {
      final o = catalogOrdQueryToInternal(pOrd);
      if (o != null) {
        if (ord != o) {
          ord = o;
          changed = true;
        }
      } else {
        mustSyncUri = true;
      }
    }

    if (!catalogOrdInternalIsValid(ord)) {
      ord = 'nome';
      changed = true;
      mustSyncUri = true;
    }

    final pm0 = _pendingUrlPmin;
    final pm1 = _pendingUrlPmax;
    _pendingUrlPmin = null;
    _pendingUrlPmax = null;
    if (pm0 != null && pm0.trim().isNotEmpty) {
      final v = catalogParsePrecoQuery(pm0);
      if (v != null) {
        if (pmin != v) {
          pmin = v;
          changed = true;
        }
      } else {
        if (pmin != null) {
          pmin = null;
          changed = true;
        }
        mustSyncUri = true;
      }
    }
    if (pm1 != null && pm1.trim().isNotEmpty) {
      final v = catalogParsePrecoQuery(pm1);
      if (v != null) {
        if (pmax != v) {
          pmax = v;
          changed = true;
        }
      } else {
        if (pmax != null) {
          pmax = null;
          changed = true;
        }
        mustSyncUri = true;
      }
    }
    if (pmin != null && pmax != null && pmin > pmax) {
      pmin = null;
      pmax = null;
      changed = true;
      mustSyncUri = true;
    }

    final pTam = _pendingUrlTam;
    final pCor = _pendingUrlCor;
    _pendingUrlTam = null;
    _pendingUrlCor = null;

    if (pTam != null) {
      final c = _canonicalVariationInOptions(pTam, tamanhos);
      if (c != null) {
        if (tam != c) {
          tam = c;
          changed = true;
        }
      } else {
        mustSyncUri = true;
        if (tam != null) {
          tam = null;
          changed = true;
        }
      }
    }

    if (pCor != null) {
      final c = _canonicalVariationInOptions(pCor, cores);
      if (c != null) {
        if (cor != c) {
          cor = c;
          changed = true;
        }
      } else {
        mustSyncUri = true;
        if (cor != null) {
          cor = null;
          changed = true;
        }
      }
    }

    if (tam != null) {
      final c = _canonicalVariationInOptions(tam, tamanhos);
      if (c == null) {
        tam = null;
        changed = true;
        mustSyncUri = true;
      } else if (c != tam) {
        tam = c;
        changed = true;
        mustSyncUri = true;
      }
    }

    if (cor != null) {
      final c = _canonicalVariationInOptions(cor, cores);
      if (c == null) {
        cor = null;
        changed = true;
        mustSyncUri = true;
      } else if (c != cor) {
        cor = c;
        changed = true;
        mustSyncUri = true;
      }
    }

    final pXv = _pendingUrlXv;
    _pendingUrlXv = null;
    if (pXv != null) {
      final cx = _canonicalVariationInOptions(pXv, extras);
      if (cx != null) {
        if (xv != cx) {
          xv = cx;
          changed = true;
        }
      } else {
        mustSyncUri = true;
        if (xv != null) {
          xv = null;
          changed = true;
        }
      }
    }

    if (xv != null) {
      final cx = _canonicalVariationInOptions(xv, extras);
      if (cx == null) {
        xv = null;
        changed = true;
        mustSyncUri = true;
      } else if (cx != xv) {
        xv = cx;
        changed = true;
        mustSyncUri = true;
      }
    }

    if (xv != null && kIsWeb && _catalogUrlProd != null) {
      Map<String, dynamic>? focused;
      final pu = (_catalogUrlProd ?? '').trim();
      if (pu.isNotEmpty) {
        for (final p in produtos) {
          if (catalogProdutoMatchesDeepLinkTarget(p, pu)) {
            focused = p;
            break;
          }
        }
      }
      if (focused != null &&
          !CatalogVariationFilter.produtoMatches(
            focused,
            variacaoExtra: xv,
          )) {
        xv = null;
        changed = true;
        mustSyncUri = true;
      }
    }

    final tp = totalPaginas < 1 ? 1 : totalPaginas;
    final maxIdx = tp - 1;
    var pageIdx = _currentPageNotifier.value;
    var pageAdjusted = false;

    final pPage = _pendingUrlCatalogPage;
    _pendingUrlCatalogPage = null;
    if (pPage != null) {
      final idx0 = pPage - 1;
      if (idx0 >= 0 && idx0 <= maxIdx) {
        if (pageIdx != idx0) {
          pageIdx = idx0;
          pageAdjusted = true;
        }
      } else {
        final c = idx0.clamp(0, maxIdx);
        if (pageIdx != c) {
          pageIdx = c;
          pageAdjusted = true;
        }
        mustSyncUri = true;
      }
    }

    final safeIdx = pageIdx.clamp(0, maxIdx);
    if (safeIdx != pageIdx) {
      pageIdx = safeIdx;
      pageAdjusted = true;
      mustSyncUri = true;
    }

    if (_currentPageNotifier.value != pageIdx) {
      _currentPageNotifier.value = pageIdx;
      pageAdjusted = true;
    }

    if (changed) {
      setState(() {
        _selectedCategory = cat;
        _selectedSubcategory = sub;
        _ordenacaoProdutos = ord;
        _precoMin = pmin;
        _precoMax = pmax;
        _filtroVariacaoTamanho = tam;
        _filtroVariacaoCor = cor;
        _filtroVariacaoExtra = xv;
      });
      _scheduleCatalogScrollToTopAfterFilter();
    }
    if (changed || mustSyncUri || pageAdjusted) {
      _syncCatalogQueryToBrowserUri();
    }
  }

  void _clearFiltrosVariacao() {
    _filtroVariacaoTamanho = null;
    _filtroVariacaoCor = null;
    _filtroVariacaoExtra = null;
    _pendingUrlTam = null;
    _pendingUrlCor = null;
    _pendingUrlXv = null;
  }

  void _onCatalogVariacaoExtraFromProductUi(String? v) {
    if (!mounted) return;
    setState(() {
      _filtroVariacaoExtra = v;
      _currentPageNotifier.value = 0;
    });
    _syncCatalogQueryToBrowserUri();
  }

  /// Faixa de preço vs [priceMin]/[priceMax] do produto (variações) ou preço único.
  bool _produtoIntersectsPrecoRange(Map<String, dynamic> p) {
    if (_precoMin == null && _precoMax == null) return true;
    double lo;
    double hi;
    final rawMin = p['priceMin'];
    final rawMax = p['priceMax'];
    final nMin = asNum(rawMin);
    final nMax = asNum(rawMax);
    if (nMin != null || nMax != null) {
      final a = (nMin ?? nMax)!.toDouble();
      final b = (nMax ?? nMin)!.toDouble();
      lo = a < b ? a : b;
      hi = a > b ? a : b;
    } else {
      final rawP = p['preco'] ?? p['valor'] ?? 0.0;
      final n = asNum(rawP);
      final preco = n?.toDouble() ?? double.tryParse('$rawP') ?? 0.0;
      lo = hi = preco;
    }
    final fLo = _precoMin ?? double.negativeInfinity;
    final fHi = _precoMax ?? double.infinity;
    return lo <= fHi && hi >= fLo;
  }


  /// Filtro + ordenacao memoizados — evita O(n) sort a cada rebuild do StreamBuilder.
  List<Map<String, dynamic>> _catalogListaOrdenadaMemo({
    required List<Map<String, dynamic>> produtos,
    required String search,
    required String? effCatFilter,
    required String? effSubFilter,
  }) {
    final sig = StringBuffer()
      ..write(_lastProdutosDocsSig)
      ..write('|n=${produtos.length}')
      ..write('|s=${search.trim()}')
      ..write('|cat=${effCatFilter ?? ''}')
      ..write('|sub=${effSubFilter ?? ''}')
      ..write('|ord=$_ordenacaoProdutos')
      ..write('|pmin=$_precoMin')
      ..write('|pmax=$_precoMax')
      ..write('|est=$_apenasEmEstoque')
      ..write('|tam=${_filtroVariacaoTamanho ?? ''}')
      ..write('|cor=${_filtroVariacaoCor ?? ''}')
      ..write('|xv=${_filtroVariacaoExtra ?? ''}');
    final sigStr = sig.toString();
    if (sigStr == _catalogListaOrdenadaCacheSig) {
      return _catalogListaOrdenadaCache;
    }

    bool matchCategoriaSub(Map<String, dynamic> p) {
      return _produtoTemCategoria(p, effCatFilter) &&
          _produtoTemSubcategoria(p, effSubFilter);
    }

    final searchLower = search.trim().toLowerCase();
    final listaFiltrada = produtos.where((p) {
      final n = (p['nome'] ?? '').toString().toLowerCase();
      final d = (p['descricao'] ?? '').toString().toLowerCase();
      final matchText = searchLower.isEmpty
          ? true
          : n.contains(searchLower) || d.contains(searchLower);
      final matchCatSub = matchCategoriaSub(p);
      final matchPreco = _produtoIntersectsPrecoRange(p);
      final matchEstoque = !_apenasEmEstoque ||
          CatalogEstoqueHelper.produtoPassaFiltroApenasEmEstoque(p);
      final matchVariacao = CatalogVariationFilter.produtoMatches(
        p,
        tamanho: _filtroVariacaoTamanho,
        cor: _filtroVariacaoCor,
        variacaoExtra: _filtroVariacaoExtra,
      );
      return matchText &&
          matchCatSub &&
          matchPreco &&
          matchEstoque &&
          matchVariacao;
    }).toList();

    final listaOrdenada = List<Map<String, dynamic>>.from(listaFiltrada);
    if (_ordenacaoProdutos == 'preco_asc') {
      listaOrdenada.sort((a, b) {
        final va = catalogPrecoParaOrdenacao(a);
        final vb = catalogPrecoParaOrdenacao(b);
        return va.compareTo(vb);
      });
    } else if (_ordenacaoProdutos == 'preco_desc') {
      listaOrdenada.sort((a, b) {
        final va = catalogPrecoParaOrdenacao(a);
        final vb = catalogPrecoParaOrdenacao(b);
        return vb.compareTo(va);
      });
    } else if (_ordenacaoProdutos == 'novidade') {
      listaOrdenada.sort((a, b) {
        final dtA = asDateTime(a['dataCriacao']);
        final dtB = asDateTime(b['dataCriacao']);
        if (dtA == null && dtB == null) return 0;
        if (dtA == null) return 1;
        if (dtB == null) return -1;
        return dtB.compareTo(dtA);
      });
    } else {
      listaOrdenada.sort((a, b) {
        final an = (a['nome'] ?? '').toString().toLowerCase();
        final bn = (b['nome'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
    }

    _catalogListaOrdenadaCacheSig = sigStr;
    _catalogListaOrdenadaCache = listaOrdenada;
    return listaOrdenada;
  }

  void _onCatalogScroll() {
    if (!_catalogScrollController.hasClients) return;
    final offset = _catalogScrollController.offset;
    // O botão "voltar ao topo" só depende de estar acima/abaixo do limiar.
    // Atualizar o notifier a cada pixel reconstrói o ValueListenableBuilder o tempo todo
    // e degrada o scroll na Web (jank / "travadas").
    const threshold = 300.0;
    final prev = _scrollOffsetNotifier.value;
    if ((prev >= threshold) == (offset >= threshold)) return;
    _scrollOffsetNotifier.value = offset;
  }

  void _onCatalogPageNotifierChanged() {
    if (kIsWeb) {
      _syncCatalogQueryToBrowserUri();
    }
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
    _currentPageNotifier.removeListener(_onCatalogPageNotifierChanged);
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

  String? _catalogProdUrlFromMap(Map<String, dynamic> p) {
    final slug = safeStr(p['slug']).trim();
    if (slug.isNotEmpty) return slug;
    final id = safeStr(p['id']).trim();
    return id.isEmpty ? null : id;
  }

  void _onProductUrlFocus(String prodUrlValue) {
    if (!kIsWeb) return;
    final s = catalogSanitizeProdQuery(prodUrlValue);
    if (s == null) return;
    _catalogUrlProd = s;
    _syncCatalogQueryToBrowserUri();
  }

  void _onProductUrlBlur() {
    if (!kIsWeb) return;
    if (_catalogUrlProd == null) return;
    _catalogUrlProd = null;
    _syncCatalogQueryToBrowserUri();
  }

  void _tryHandleInitialProdutoDeepLink({
    required List<Map<String, dynamic>> produtos,
  }) {
    if (_initialProdutoHandled) return;
    final target = _pendingInitialProdutoId?.trim();
    if (target == null || target.isEmpty) return;
    if (produtos.isEmpty) return;
    _initialProdutoHandled = true;

    final product = resolveCatalogDeepLinkProduct(
      produtos: produtos,
      targetRaw: target,
    );

    if (product == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _catalogUrlProd = null;
        _syncCatalogQueryToBrowserUri();
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = product;
      final productId = safeStr(p['id']);
      final urlProd = catalogSanitizeProdQuery(_catalogProdUrlFromMap(p));
      if (kIsWeb && urlProd != null) {
        _catalogUrlProd = urlProd;
        _syncCatalogQueryToBrowserUri();
      }
      if (productId.isNotEmpty) _onProductViewed(productId);

      void onDetailClosed() {
        if (!kIsWeb) return;
        _catalogUrlProd = null;
        _syncCatalogQueryToBrowserUri();
      }

      final lid = _resolvedLojaId ?? widget.lojaId;

      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => catalogReplayOpenedTheme(
                context,
                CatalogProductDetailScreen.fromProdutoMap(
                p: p,
                lojaId: lid,
                onAdd: (it) => _addToCart(it, produtos),
                onAbrirCarrinho: null,
                catalogShareUrl: CatalogShareService.buildUrlWithParams(
                  _publicCatalogShareBase(),
                  ref: widget.vendedorRef,
                  indicacao: widget.indicacaoClienteRef,
                  prod: safeStr(p['slug']).isNotEmpty
                      ? safeStr(p['slug'])
                      : productId,
                ),
                nomeLoja: null,
                contatoWhatsapp: null,
                politicaFrete: null,
                prazoEntregaTexto: null,
                todosProdutos: produtos,
                listaCatalogoMemoria: produtos,
                initialCatalogExtraValor: _filtroVariacaoExtra,
                onCatalogVariacaoExtraChanged:
                    _onCatalogVariacaoExtraFromProductUi,
              ),
            ),
            ),
          )
          .then((_) => onDetailClosed());
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
      if (lid != null) await _loadCarrinhoLocal();
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
              content: Text(
                  'Não foi possível carregar o carrinho. Verifique sua conexão e tente novamente.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      },
    );
    if (mounted) {
      _cart.clear();
      _cart.addAll(items);
      _clearPrePedidoReuseSession();
      setState(() {});
    }
  }

  Future<void> _saveCarrinho() async {
    final lid = _resolvedLojaId;
    if (lid == null) return;
    final cid = _clienteId;
    if (cid != null) {
      await ClienteAuthService.saveCarrinho(
          lojaId: lid, clienteId: cid, items: _cart);
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final serializable = _cart.map((e) {
          final m = <String, dynamic>{};
          for (final entry in e.entries) {
            final v = entry.value;
            if (v == null) continue;
            if (v is DateTime) {
              m[entry.key] = v.toIso8601String();
            } else if (v is Map ||
                v is List ||
                v is num ||
                v is bool ||
                v is String) {
              m[entry.key] = v;
            }
          }
          return m;
        }).toList();
        await prefs.setString(
            'catalog_cart_items_$lid', jsonEncode(serializable));
      } catch (_) {}
    }
  }

  Future<void> _loadCarrinhoLocal() async {
    final lid = _resolvedLojaId;
    if (lid == null || _clienteId != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('catalog_cart_items_$lid');
      if (json != null && json.isNotEmpty) {
        final decoded = jsonDecode(json);
        if (decoded is List && mounted) {
          _cart.clear();
          for (final e in decoded) {
            if (e is Map) _cart.add(Map<String, dynamic>.from(e));
          }
          _clearPrePedidoReuseSession();
          setState(() {});
        }
      }
    } catch (_) {}
  }

  /// Remove do carrinho itens cujo produto não existe mais na lista atual do catálogo.
  void _limparCartDeProdutosRemovidos(List<Map<String, dynamic>> produtos) {
    if (_cart.isEmpty || produtos.isEmpty) return;
    final validIds = produtos
        .map((p) => (p['id'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final validSlugs = produtos
        .map((p) => (p['slug'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final before = _cart.length;
    _cart.removeWhere((item) {
      final id = (item['id'] ?? item['produtosId'] ?? '').toString().trim();
      final slug = (item['slug'] ?? '').toString().trim();
      return !validIds.contains(id) && !validSlugs.contains(slug);
    });
    if (_cart.length < before && mounted) {
      _clearPrePedidoReuseSession();
      _saveCarrinho();
      setState(() {});
    }
  }

  /// Reseta o estado da roleta (chamado quando inicia nova compra, ex: após checkout)
  void _resetRoletaState() {
    _roletaJaGirada = false;
    _cupomRoletaCodigo = null;
    _cupomRoletaDesconto = null;
    _premioRoletaDescricao = null;
    _freteGratisRoleta = false;
  }

  void _clearPrePedidoReuseSession() {
    _ultimoPrePedidoId = null;
    _ultimoPrePedidoData = null;
    _prePedidoReuseFingerprint = null;
    _prePedidoReuseCanal = null;
  }

  static String _normFingerprintText(String? s) =>
      (s ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Endereço para fingerprint (sem complemento: evita novo pré-pedido só por complemento).
  static String _enderecoFingerprintKey(Map<String, dynamic> end) {
    if (end.isEmpty) return '';
    final cepDigits =
        (end['cep'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    return [
      cepDigits,
      _normFingerprintText(end['rua']?.toString()),
      _normFingerprintText(end['numero']?.toString()),
      _normFingerprintText(end['bairro']?.toString()),
      _normFingerprintText(end['cidade']?.toString()),
      _normFingerprintText(end['estado']?.toString()),
    ].join('|');
  }

  /// Chave estável do checkout atual; se diferir do último reuso, cria novo pré-pedido.
  String _prePedidoReuseFingerprintFromCheckout({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> entrega,
    required String pagamento,
    required String observacao,
    required String? cupomCodigo,
    String? cupomFreteCodigo,
    required double descontoCupom,
    required double valorTotalCheckout,
    required String canal,
    String? cupomRoletaCodigo,
    double? cupomRoletaDesconto,
    String? premioRoletaDescricao,
  }) {
    final end = asMap(customer['endereco']);
    final nomeCliente = _normFingerprintText(customer['nome']?.toString());
    final addrKey = _enderecoFingerprintKey(end);
    final em = (customer['email'] ?? '').toString().trim().toLowerCase();
    final tel = (customer['telefone'] ?? '').toString().trim();
    final cartPart = _cart.map((e) {
      final id = '${e['id'] ?? e['produtosId'] ?? ''}';
      final q = CatalogEstoqueHelper.parseCartItemQuantidade(e['quantidade']);
      final tam = (e['tamanho'] ?? '').toString();
      final cor = (e['cor'] ?? '').toString();
      return '$id|$q|$tam|$cor';
    }).join(';');
    final fv = safeDouble(entrega['valor']);
    final fg = entrega['freteGratis'] == true;
    final tipo = (entrega['tipo'] ?? '').toString();
    final nom = (entrega['nome'] ?? '').toString();
    final cc = cupomCodigo ?? '';
    final cff = cupomFreteCodigo ?? '';
    final obs = observacao.trim();
    final cr = cupomRoletaCodigo ?? '';
    final crd = cupomRoletaDesconto ?? 0.0;
    final pr = premioRoletaDescricao ?? '';
    return '${valorTotalCheckout.toStringAsFixed(2)}|${descontoCupom.toStringAsFixed(4)}|$cc|$cff|$pagamento|$fv|$fg|$tipo|$nom|$obs|$canal|$cartPart|$em|$tel|$nomeCliente|$addrKey|$cr|$crd|$pr';
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
              content: Text(
                  'Não foi possível carregar favoritos. Verifique sua conexão e tente novamente.'),
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
                        ).then((_) async {
                          await _loadClienteAndFavoritos();
                          if (!mounted) return;
                          setState(() => _menuClienteAuthRetryKey++);
                        });
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
                        ).then((_) async {
                          await _loadClienteAndFavoritos();
                          if (!mounted) return;
                          setState(() => _menuClienteAuthRetryKey++);
                        });
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

  /// Diagnóstico web: origem provável do slug/id (path, query, fragment ou host).
  String _catalogResolveSourceHint() {
    if (!kIsWeb) return 'native_app_route';
    final u = Uri.base;
    if (u.path.contains('/loja/') ||
        (u.pathSegments.isNotEmpty && u.pathSegments.first == 'loja')) {
      return 'web_path_/loja/';
    }
    final q = (u.queryParameters['loja'] ??
            u.queryParameters['slug'] ??
            u.queryParameters['store_id'] ??
            '')
        .trim();
    if (q.isNotEmpty) return 'web_query_slug_store_id';
    if (u.fragment.contains('loja')) return 'web_fragment_hash';
    return 'web_host_custom_domain_or_root';
  }

  String? _catalogTraceDiagnosticText() {
    if (!_catalogTechnicalDiagEnabled) return null;
    final buf = StringBuffer()..writeln(CatalogNormalTrace.toDiagnosticString());
    if (kIsWeb) {
      final phase = plat.Web.localStorageGet('mp_catalog_phase') ?? '';
      buf.writeln('— runtime —');
      buf.writeln('mp_catalog_phase: $phase');
      buf.writeln(
          'resolvedLojaId(widget): ${_resolvedLojaId ?? '(null)'}');
      buf.writeln(
          'buildId: ${const String.fromEnvironment('CATALOG_BUILD_ID', defaultValue: 'dev')}');
    }
    return buf.toString();
  }

  Future<void> _resolveLojaId() async {
    final swResolve = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint(
        '[CAT_START_TIMING] resolve_loja_id begin raw=${widget.lojaId}',
      );
    }
    var traceOk = false;
    String? traceResolvedId;
    String? traceErrorType;
    CatalogStartupTrace.spanStart(
      'CAT_START.resolve_loja_id',
      data: <String, Object?>{
        'loja_id_raw': widget.lojaId,
        'preview': widget.preview,
      },
    );
    try {
      final widgetId = widget.lojaId.trim();
      CatalogNormalTrace.mark(
          'resolver.start', <String, Object?>{'raw': widgetId});

      // Link muito curto (ex: /loja/r) geralmente é incompleto ou truncado
      if (widgetId.length < 3) {
        CatalogNormalTrace.setField('fallback.reason', 'link_too_short');
        if (mounted) {
          setState(() {
            _loadingLojaId = false;
            _resolvedLojaId = null;
            _catalogOpenFailureDetail =
                'Link do catálogo inválido ou incompleto. Use o link completo da loja.';
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
          const Duration(seconds: 7),
          onTimeout: () => throw TimeoutException(
            'O catálogo demorou muito para carregar. Verifique sua conexão e tente novamente.',
          ),
        );

        if (!result.success) {
          logD('❌ [CATÁLOGO] ${result.errorMessage}');
          CatalogNormalTrace.setField(
              'fallback.reason', result.failureReason ?? 'resolve_failed');
          CatalogNormalTrace.mark('resolver.failure', <String, Object?>{
            'error': (result.errorMessage ?? '').toString(),
          });
          if (kIsWeb) {
            final uri = Uri.base;
            final payload = <String, dynamic>{
              'buildId': const String.fromEnvironment(
                'CATALOG_BUILD_ID',
                defaultValue: 'dev',
              ),
              'timestamp': DateTime.now().toIso8601String(),
              'host': uri.host,
              'path': uri.path,
              'query': uri.query,
              'userAgent': plat.Web.userAgent(),
              'slug': widgetId,
              'lojaId': '',
              'fase': 'catalog.slug.resolve.fail',
              'phase': 'publicCatalogScreen.resolveLojaId',
              'reason': result.failureReason ?? 'unknown',
              'resolverStage': result.resolverStage ?? 'publicCatalog.resolve',
              'resolverAttempt': result.resolverAttempt ?? 'n/a',
              'firestorePath':
                  (result.diagnostics?['firestorePath'] ?? '').toString(),
              'firestoreErrorCode':
                  (result.diagnostics?['firestoreErrorCode'] ?? '').toString(),
              'firestoreErrorMessage':
                  (result.diagnostics?['firestoreErrorMessage'] ?? '')
                      .toString(),
              'docExists': result.diagnostics?['docExists'],
              'docId': (result.diagnostics?['docId'] ?? '').toString(),
              'slugField': (result.diagnostics?['slugField'] ?? '').toString(),
              'ativo': result.diagnostics?['ativo'],
              'publicado': result.diagnostics?['publicado'],
              'catalogoAtivo': result.diagnostics?['catalogoAtivo'],
              'status': result.diagnostics?['status'],
              'attempts': result.diagnostics?['attempts'],
              'error': result.errorMessage ?? 'Loja não encontrada',
              'stack': '',
              'appVersion': 'web',
            };
            plat.Web.localStorageSet(
                'mp_last_runtime_error', jsonEncode(payload));
            plat.Web.localStorageSet(
              'mp_catalog_resolver_result',
              jsonEncode(payload),
            );
          }
          setState(() {
            _loadingLojaId = false;
            _resolvedLojaId = null;
            _catalogOpenFailureDetail = result.errorMessage;
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
          _catalogOpenFailureDetail = null;
        });
        traceOk = true;
        traceResolvedId = _resolvedLojaId;
        CatalogNormalTrace.mark('resolver.success', <String, Object?>{
          'lojaId': (result.canonicalStoreId ?? '').toString(),
        });
        CatalogNormalTrace.setField(
            'resolver.lojaId', result.canonicalStoreId ?? '');
        CatalogNormalTrace.setField('lojaDoc.exists', true);
        CatalogNormalTrace.setField('fallback.reason', 'none');
        _loadMostrarEstoqueNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _loadMostrarQuantidadeNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _refreshCatalogCartFormCache(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _deferSecondaryPublicCatalogLoads();
        logD('✅ [CATÁLOGO] lojaId FINAL (público): $_resolvedLojaId');
        catalogDebugLogStoreResolution(
          widgetLojaIdRaw: widgetId,
          resolvedCanonicalId: _resolvedLojaId,
          preview: widget.preview,
          resolveSourceHint: _catalogResolveSourceHint(),
        );
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
          _catalogOpenFailureDetail = null;
        });
        traceOk = true;
        traceResolvedId = _resolvedLojaId;
        _loadMostrarEstoqueNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _loadMostrarQuantidadeNoCatalogo(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _refreshCatalogCartFormCache(
            result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
        _deferSecondaryPublicCatalogLoads();
        logD('✅ [CATÁLOGO] lojaId FINAL (admin): $_resolvedLojaId');
        catalogDebugLogStoreResolution(
          widgetLojaIdRaw: widgetId,
          resolvedCanonicalId: _resolvedLojaId,
          preview: widget.preview,
          resolveSourceHint: 'admin_preview_dashboard',
        );
      }

      logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      traceErrorType = e.runtimeType.toString();
      logD('❌ Erro ao resolver lojaId (type=${e.runtimeType})');
      CatalogNormalTrace.setField('fallback.reason', 'resolve_exception');
      CatalogNormalTrace.mark('resolver.exception', <String, Object?>{
        'type': e.runtimeType.toString(),
      });
      if (mounted) {
        if (kIsWeb) {
          final uri = Uri.base;
          final payload = <String, dynamic>{
            'buildId': const String.fromEnvironment(
              'CATALOG_BUILD_ID',
              defaultValue: 'dev',
            ),
            'timestamp': DateTime.now().toIso8601String(),
            'host': uri.host,
            'path': uri.path,
            'query': uri.query,
            'userAgent': plat.Web.userAgent(),
            'slug': widget.lojaId,
            'lojaId': '',
            'fase': 'catalog.slug.resolve.exception',
            'phase': 'publicCatalogScreen.resolveLojaId',
            'reason': 'exception',
            'resolverStage': 'publicCatalog.resolve',
            'resolverAttempt': 'resolveForPublicCatalog.catch',
            'firestorePath': '',
            'firestoreErrorCode': '',
            'firestoreErrorMessage': e.toString(),
            'docExists': false,
            'docId': '',
            'slugField': '',
            'ativo': null,
            'publicado': null,
            'catalogoAtivo': null,
            'status': null,
            'error': e.toString(),
            'stack': '',
            'appVersion': 'web',
          };
          plat.Web.localStorageSet(
              'mp_last_runtime_error', jsonEncode(payload));
          plat.Web.localStorageSet(
            'mp_catalog_resolver_result',
            jsonEncode(payload),
          );
        }
        setState(() {
          _loadingLojaId = false;
          _resolvedLojaId = null;
          _catalogOpenFailureDetail = e is TimeoutException
              ? (e.message ?? 'Tempo esgotado. Tente novamente.')
              : e.toString();
        });
        final msg = e is TimeoutException
            ? (e.message ?? 'Tempo esgotado. Tente novamente.')
            : 'Erro ao carregar: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (kDebugMode) {
        debugPrint(
          '[CAT_START_TIMING] resolve_loja_id total ${swResolve.elapsedMilliseconds}ms',
        );
      }
      CatalogStartupTrace.spanEnd(
        'CAT_START.resolve_loja_id',
        data: <String, Object?>{
          'ok': traceOk,
          'resolved_loja_id': traceResolvedId,
          'error_type': traceErrorType,
        },
      );
    }
  }

  String get lojaId {
    final lid = _resolvedLojaId;
    if (lid == null || lid.isEmpty) {
      throw StateError('lojaId ainda não foi resolvido');
    }
    return lid;
  }

  String _publicCatalogShareBase() {
    return CatalogPublicUrlService.montarUrlCatalogoPublico(
      lojaConfig: _catalogUrlConfigMerge,
      lojaId: lojaId,
    );
  }

  void _refreshCatalogCartFormCache(String storeId) {
    if (storeId.isEmpty) return;
    SharedPreferences.getInstance().then((prefs) {
      Map<String, dynamic>? parsed;
      try {
        final key = 'catalog_cart_form_$storeId';
        final json = prefs.getString(key);
        if (json != null && json.isNotEmpty) {
          final decoded = jsonDecode(json);
          if (decoded is Map) {
            parsed = Map<String, dynamic>.from(decoded);
          }
        }
      } catch (_) {
        parsed = null;
      }
      if (!mounted) return;
      if (_resolvedLojaId != storeId) return;
      setState(() => _cachedCatalogCartForm = parsed);
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _snackAdicionadoAoCarrinho() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Adicionado ao carrinho'),
        duration: Duration(milliseconds: 2200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarIndicarAmigoSheet(BuildContext context,
      {required String lojaId, required String clienteId}) {
    final link = CatalogShareService.buildUrlWithParams(
      CatalogPublicUrlService.montarUrlCatalogoPublico(
        lojaConfig: _catalogUrlConfigMerge,
        lojaId: lojaId,
      ),
      indicacao: clienteId,
    );
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
                  Expanded(
                    child: Text(
                      'Indicar amigo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Quando seu amigo comprar pelo link abaixo, você e ele ganham um cupom de desconto. Seu cupom será ativado quando ele usar o cupom dele na primeira compra.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
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
      _clearPrePedidoReuseSession();
    });
    _saveCarrinho();
  }

  /// Ajusta quantidade de uma linha do carrinho (respeita estoque como [_addToCart]).
  bool _setCartItemQuantity(
    int index,
    int newQty,
    List<Map<String, dynamic>> catalogProducts,
  ) {
    if (index < 0 || index >= _cart.length) return false;
    if (newQty < 1) {
      _removeFromCart(index);
      return true;
    }

    final item = _cart[index];
    final comboRaw = item['itensComboComSelecao'];
    final isComboLine = comboRaw is List && comboRaw.isNotEmpty;
    final id = '${item['id'] ?? item['produtosId'] ?? ''}';
    final tam = (item['tamanho'] ?? '').toString().trim();
    final cor = (item['cor'] ?? '').toString().trim();
    final ex =
        (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim();

    if (!isComboLine) {
      final idTrim = id.trim();
      if (idTrim.isEmpty) {
        _snack(
          'Não foi possível identificar o produto. Atualize o catálogo e tente novamente.',
        );
        return false;
      }
      final p = CatalogEstoqueHelper.findProductInList(catalogProducts, idTrim);
      if (p == null) {
        _snack(
          'Produto indisponível ou dados desatualizados. Atualize a página e tente novamente.',
        );
        return false;
      }
      final avail =
          CatalogEstoqueHelper.estoqueDisponivelVariacao(p, tam, cor, ex);
      final lineKey = CatalogEstoqueHelper.cartLineIdentity(item);
      var other = 0;
      for (var i = 0; i < _cart.length; i++) {
        if (i == index) continue;
        if (CatalogEstoqueHelper.cartLineIdentity(_cart[i]) == lineKey) {
          other += CatalogEstoqueHelper.parseCartItemQuantidade(
              _cart[i]['quantidade']);
        }
      }
      if (other + newQty > avail) {
        _snack(avail <= 0
            ? 'Produto esgotado nesta variação.'
            : 'Estoque insuficiente. Disponível: $avail un.');
        return false;
      }
    }

    setState(() {
      _cart[index]['quantidade'] = newQty;
      _clearPrePedidoReuseSession();
    });
    _saveCarrinho();
    return true;
  }

  bool _addToCart(
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
    final ex =
        (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim();
    final addQty =
        CatalogEstoqueHelper.parseCartItemQuantidade(item['quantidade']);
    final comboRaw = item['itensComboComSelecao'];
    final isComboLine = comboRaw is List && comboRaw.isNotEmpty;

    if (!isComboLine) {
      final idTrim = id.trim();
      if (idTrim.isEmpty) {
        _snack(
          'Não foi possível identificar o produto. Atualize o catálogo e tente novamente.',
        );
        return false;
      }
      final p = CatalogEstoqueHelper.findProductInList(catalogProducts, idTrim);
      if (p == null) {
        _snack(
          'Produto indisponível ou dados desatualizados. Atualize a página e tente novamente.',
        );
        return false;
      }
      final avail =
          CatalogEstoqueHelper.estoqueDisponivelVariacao(p, tam, cor, ex);
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
        return false;
      }
    }

    setState(() {
      final key = CatalogEstoqueHelper.cartLineIdentity(item);
      final idx = _cart
          .indexWhere((e) => CatalogEstoqueHelper.cartLineIdentity(e) == key);
      if (idx >= 0) {
        final cur = CatalogEstoqueHelper.parseCartItemQuantidade(
            _cart[idx]['quantidade']);
        _cart[idx]['quantidade'] = cur + addQty;
      } else {
        final copy = Map<String, dynamic>.from(item);
        copy['quantidade'] = addQty;
        _cart.add(copy);
      }
      _clearPrePedidoReuseSession();
    });
    _saveCarrinho();
    return true;
  }

  // Flag para evitar spam de log de permission-denied
  static bool _cfgPermissionDeniedLogged = false;
  static bool _produtosPermissionDeniedLogged = false;
  bool _isIosWebKitCatalog() => kIsWeb && plat.Web.isIosWebKit();

  Stream<Map<String, dynamic>> _cfgStream(String lojaId) {
    final db = FirebaseFirestore.instance;
    final baseRef = db.collection('lojas').doc(lojaId);

    final String cfgCol = widget.preview ? 'draft_config' : 'config';
    final configRef = baseRef.collection(cfgCol).doc('config');
    final paymentsDocId = cfgCol == 'config' ? 'payments_public' : 'payments';
    final paymentsRef = baseRef.collection(cfgCol).doc(paymentsDocId);

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
      CatalogStartupTrace.mark(
        'CAT_START.cfg_stream.subscribe',
        data: <String, Object?>{
          'loja_id': lojaId,
          'preview': widget.preview,
        },
      );
      subscription = configRef.snapshots().listen(
        (cfgSnap) async {
          _cfgPermissionDeniedLogged = false;
          final cfg = asMapDeep(cfgSnap.data() ?? {});
          if (kDebugMode) {
            catalogDebugLogConfigPipeline(
              phase: 'direct_stream_pre_bridge',
              lojaId: lojaId,
              cfgCol: cfgCol,
              cfg: Map<String, dynamic>.from(cfg),
            );
          }
          bridgeStoreConfigV3PublishedIntoPublicCatalogFlat(
            cfg,
            preferDraft: widget.preview,
          );
          if (kDebugMode) {
            catalogDebugLogConfigPipeline(
              phase: 'direct_stream_post_bridge_v3',
              lojaId: lojaId,
              cfgCol: cfgCol,
              cfg: Map<String, dynamic>.from(cfg),
            );
          }

          bool isMissing(dynamic v) {
            if (v == null) return true;
            if (v is String) return v.trim().isEmpty;
            if (v is Map) return v.isEmpty;
            if (v is List) return v.isEmpty;
            return false;
          }

          void putIfMissing(Map<String, dynamic> target,
              Map<String, dynamic> source, String key) {
            if (isMissing(target[key]) && !isMissing(source[key])) {
              target[key] = source[key];
            }
          }

          // Emite já com o doc publicado + bridge V3 — o StreamBuilder sai de `waiting`
          // sem esperar payments, fretes subdoc, legado, doc raiz e cupons (antes em série).
          if (!controller.isClosed) {
            if (!_traceConfigFirstDataLogged) {
              _traceConfigFirstDataLogged = true;
              CatalogStartupTrace.mark(
                'CAT_START.cfg_stream.first_data',
                data: <String, Object?>{
                  'loja_id': lojaId,
                  'cfg_keys': cfg.length,
                },
              );
            }
            controller.add(Map<String, dynamic>.from(cfg));
          }

          // iPhone (Safari/Chrome via WebKit): evita merges secundários pesados
          // que podem induzir TypeError/minified com documentos legados heterogêneos.
          // Mantemos o config principal para preservar o fluxo do catálogo.
          if (_isIosWebKitCatalog()) {
            return;
          }

          Future<void> mergePayments() async {
            try {
              final paySnap =
                  await paymentsRef.get().timeout(const Duration(seconds: 8));
              if (paySnap.exists) {
                cfg['payments'] = asMapDeep(paySnap.data());
              }
            } catch (_) {}
          }

          Future<void> mergeLegacyLive() async {
            try {
              final legacyLiveSnap = await baseRef
                  .collection('config_catalogo_live')
                  .doc('main')
                  .get()
                  .timeout(const Duration(seconds: 6));
              if (!legacyLiveSnap.exists) return;
              final legacy = asMapDeep(legacyLiveSnap.data());
              for (final k in const [
                'nomeLoja',
                'nome_loja',
                'nome',
                'name',
                'media',
                'logoUrl',
                'logoDesktopUrl',
                'logoMobileUrl',
                'banners',
                'bannersDesktop',
                'bannersMobile',
                'theme',
                'uiColors',
                'layout',
                'layoutType',
                'layoutPreset',
                'links',
                'rodape',
                'empresa',
                'catalogoEmManutencao',
                'mensagemManutencaoCatalogo',
              ]) {
                putIfMissing(cfg, legacy, k);
              }
            } catch (_) {}
          }

          Future<void> mergeLojaRoot() async {
            try {
              final lojaSnap =
                  await baseRef.get().timeout(const Duration(seconds: 6));
              final lojaMap = asMapDeep(lojaSnap.data());
              for (final k in const [
                'nome',
                'nomeLoja',
                'nome_loja',
                'name',
                'logoUrl',
                'logoDesktopUrl',
                'logoMobileUrl',
                'banners',
                'bannersDesktop',
                'bannersMobile',
                'theme',
                'uiColors',
                'layout',
                'catalogoEmManutencao',
                'mensagemManutencaoCatalogo',
              ]) {
                putIfMissing(cfg, lojaMap, k);
              }
              final lojaName = lojaMap['name'];
              if (isMissing(cfg['nome']) && !isMissing(lojaName)) {
                cfg['nome'] = lojaName;
              }
              if (isMissing(cfg['nomeLoja']) && !isMissing(lojaName)) {
                cfg['nomeLoja'] = lojaName;
              }
            } catch (_) {}
          }

          Future<void> mergeCuponsFromCollectionIfNeeded() async {
            final cuponsCfg = cfg['cupons'];
            final cuponsListCfg = cuponsCfg is List ? cuponsCfg : null;
            if (cuponsListCfg != null && cuponsListCfg.isNotEmpty) return;
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
                final produtoIdsRaw = d['produtoIds'] ?? d['produtoId'];
                final List<String> produtoIds = produtoIdsRaw is List
                    ? produtoIdsRaw
                        .map((e) => e.toString().trim())
                        .where((e) => e.isNotEmpty)
                        .toList()
                    : (produtoIdsRaw != null &&
                            produtoIdsRaw.toString().trim().isNotEmpty
                        ? [produtoIdsRaw.toString().trim()]
                        : <String>[]);
                cuponsList.add({
                  'codigo': cod,
                  'tipo': tipoNorm,
                  'ativo': true,
                  'valor': safeDouble(d['valor']),
                  'aplicarEm': (d['aplicarEm'] ?? 'produtos').toString(),
                  'freteGratis': d['freteGratis'] == true,
                  if (produtoIds.isNotEmpty) 'produtoIds': produtoIds,
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

          Future<void> mergeFretesManual() async {
            try {
              await mergeCatalogFretesManualFromFirestoreSubdoc(
                lojaId: lojaId,
                cfgCol: cfgCol,
                cfg: cfg,
              ).timeout(const Duration(seconds: 8));
            } catch (_) {}
          }

          await Future.wait<void>([
            mergePayments(),
            mergeFretesManual(),
            mergeLegacyLive(),
            mergeLojaRoot(),
            mergeCuponsFromCollectionIfNeeded(),
          ]);

          if (kDebugMode) {
            catalogDebugLogConfigPipeline(
              phase: 'direct_stream_post_legacy_live',
              lojaId: lojaId,
              cfgCol: cfgCol,
              cfg: Map<String, dynamic>.from(cfg),
            );
            catalogDebugLogConfigPipeline(
              phase: 'direct_stream_post_loja_doc_root',
              lojaId: lojaId,
              cfgCol: cfgCol,
              cfg: Map<String, dynamic>.from(cfg),
            );
            catalogDebugLogConfigPipeline(
              phase: 'direct_stream_final_emit',
              lojaId: lojaId,
              cfgCol: cfgCol,
              cfg: Map<String, dynamic>.from(cfg),
            );
          }
          if (!controller.isClosed) {
            CatalogStartupTrace.mark(
              'CAT_START.cfg_stream.enriched_data',
              data: <String, Object?>{
                'loja_id': lojaId,
                'cfg_keys': cfg.length,
              },
            );
            controller.add(Map<String, dynamic>.from(cfg));
          }
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            if (!_cfgPermissionDeniedLogged) {
              _cfgPermissionDeniedLogged = true;
              logD('⚠️ [CATÁLOGO] Sem permissão para config - usando padrões');
            }
            if (kDebugMode) {
              catalogDebugLogConfigStreamEmit(
                source: 'permission_denied_empty_cfg',
                lojaId: lojaId,
                preview: widget.preview,
                cfg: const {},
              );
            }
            // Retorna config vazio para UI usar padrões
            controller.add(<String, dynamic>{});
            subscription?.cancel();
          } else {
            logD(
                '❌ [CATÁLOGO] Erro no stream de config (type=${error.runtimeType})');
            if (kDebugMode) {
              catalogDebugLogConfigStreamEmit(
                source: 'stream_error_empty_cfg',
                lojaId: lojaId,
                preview: widget.preview,
                cfg: const {},
              );
            }
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
      CatalogStartupTrace.mark(
        'CAT_START.produtos_stream.subscribe',
        data: <String, Object?>{
          'loja_id': lojaId,
          'preview': widget.preview,
        },
      );
      CatalogNormalTrace.mark('produtos.stream.start', <String, Object?>{
        'loja_id': lojaId,
        'collection': 'lojas/$lojaId/$col',
        'query': 'ativo==true',
      });
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
          if (!_traceProdutosFirstDataLogged) {
            _traceProdutosFirstDataLogged = true;
            CatalogStartupTrace.mark(
              'CAT_START.produtos_stream.first_data',
              data: <String, Object?>{
                'loja_id': lojaId,
                'doc_count': snapshot.docs.length,
              },
            );
            CatalogNormalTrace.mark(
                'produtos.firstSnapshot.received', <String, Object?>{
              'count': snapshot.docs.length,
            });
            CatalogNormalTrace.setField(
                'produtos.firstSnapshot.count', snapshot.docs.length);
          }
          controller.add(snapshot);
        },
        onError: (error) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            if (!_produtosPermissionDeniedLogged) {
              _produtosPermissionDeniedLogged = true;
              logD(
                  '⚠️ [CATÁLOGO] Sem permissão para produtos - catálogo vazio');
              CatalogNormalTrace.setField(
                  'fallback.reason', 'produtos_permission_denied');
              CatalogNormalTrace.mark('produtos.stream.error', <String, Object?>{
                'code': 'permission-denied',
              });
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
      builder: (context) {
        final maxW = math.min(
          kMaxContentWidth,
          MediaQuery.sizeOf(context).width - 40,
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: AlertDialog(
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
                  _syncCatalogQueryToBrowserUri();
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
                    var a = min;
                    var b = max;
                    if (a != null && b != null && a > b) {
                      a = null;
                      b = null;
                    }
                    _precoMin = a;
                    _precoMax = b;
                    _currentPageNotifier.value = 0;
                  });
                  _syncCatalogQueryToBrowserUri();
                },
                child: const Text('Aplicar'),
              ),
            ],
          ),
        );
      },
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
        await PagamentosService.syncPaymentsPublic(lojaId);
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
    required String freteMelhorEnvioModoExibicao,
    required bool mercadoPagoAtivo,
    required CatalogCheckoutSummaryTokens checkoutSummaryTokens,
    required CatalogCartUiTokens catalogCartUiTokens,
    CatalogFirstPurchaseCouponOffer? catalogFirstPurchaseCouponOffer,
    required List<Map<String, dynamic>> catalogProducts,
  }) async {
    if (_cart.isEmpty) {
      _snack('Seu carrinho está vazio.');
      return;
    }

    final cuponsEff = _cuponsParaPreviaCart(cupons);
    final fretesEff = _fretesParaPreviaCart(fretes);
    final gatewayEff = _gatewayParaPreviaCart(checkoutGateway);

    final Map<String, dynamic>? initialFormData = _cachedCatalogCartForm;

    if (!mounted) return;
    final wideChrome = usePointerFirstChrome(context);

    if (kDebugMode) {
      debugPrint(
        '[CART_WIDGET_REAL] OPEN_CARRINHO public_catalog → '
        'CarrinhoSheetWeb (wideChrome=$wideChrome, preview=${widget.preview})',
      );
    }

    Widget carrinhoContent(BuildContext sheetContext) {
      return ScaffoldMessenger(
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.transparent,
          body: Builder(
            builder: (BuildContext cartCtx) {
              void showCartSnack(String message) {
                ScaffoldMessenger.of(cartCtx).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  ),
                );
              }

              return CarrinhoSheetWeb(
                lojaId: lojaId,
                items: _cart,
                catalogProducts: catalogProducts,
                fretes: fretesEff,
                cupons: cuponsEff,
                initialFormData: initialFormData,
                onFormDataToSave: (data) {
                  final copy = Map<String, dynamic>.from(data);
                  _safeSetStateAfterFrame(() {
                    setState(() => _cachedCatalogCartForm = copy);
                  });
                  SharedPreferences.getInstance().then((prefs) {
                    prefs.setString(
                        'catalog_cart_form_$lojaId', jsonEncode(data));
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
                checkoutSummaryStyle: checkoutSummaryTokens,
                cartUiTokens: catalogCartUiTokens,
                firstPurchaseCoupon: _adminPreviewRestrictsPayments
                    ? null
                    : catalogFirstPurchaseCouponOffer,
                checkoutGateway: gatewayEff,
                checkoutButtonLabel: checkoutButtonLabel,
                pixKey: pixKey,
                freightToken: freightToken,
                freteMelhorEnvioModoExibicao: freteMelhorEnvioModoExibicao,
                pixPreferMercadoPago: mercadoPagoAtivo,
                onRemove: _removeFromCart,
                onSetItemQuantity: (i, q) =>
                    _setCartItemQuantity(i, q, catalogProducts),
                showSnack: showCartSnack,
                onCheckoutPix: (gatewayEff == 'pix' ||
                            gatewayEff == 'whatsapp') &&
                        pixKey.trim().isNotEmpty &&
                        !mercadoPagoAtivo
                    ? ({
                        required Map<String, dynamic> customer,
                        required Map<String, dynamic> entrega,
                        required double valorTotal,
                        String observacao = '',
                        String? cupomCodigo,
                        String? cupomFreteCodigo,
                        double desconto = 0.0,
                        String? cupomRoletaCodigo,
                        double? cupomRoletaDesconto,
                        String? premioRoletaDescricao,
                        void Function(String message)? showErrorInCart,
                        Future<void> Function(String? pedidoId)? onPedidoCriado,
                      }) async {
                        void showErr(String msg) {
                          if (showErrorInCart != null) {
                            showErrorInCart(msg);
                          } else {
                            showCartSnack(msg);
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
                            cupomCodigo: cupomCodigo,
                            cupomFreteCodigo: cupomFreteCodigo,
                            desconto: desconto,
                            cupomRoletaCodigo: cupomRoletaCodigo,
                            cupomRoletaDesconto: cupomRoletaDesconto,
                            premioRoletaDescricao: premioRoletaDescricao,
                          );
                        } catch (e) {
                          logD(
                              '❌ Erro ao registrar venda PIX (type=${e.runtimeType})');
                          if (!sheetContext.mounted) return;
                          showErr('Erro ao criar pedido. Tente novamente.');
                          return;
                        }
                        try {
                          await onPedidoCriado?.call(vendaId);
                        } catch (e, st) {
                          logD(
                              '❌ [PIX] onPedidoCriado falhou (cupom não marcado): ${e.runtimeType}');
                          if (kDebugMode) debugPrintStack(stackTrace: st);
                        }
                        final payload = gerarPixCopiaECola(
                          chavePix: pixKey,
                          valor: valorTotal,
                          nomeRecebedor: 'LOJA',
                          cidadeRecebedor: 'BRASIL',
                          txid: vendaId ?? '***',
                        );
                        if (sheetContext.mounted) {
                          await _runStateAfterFrame(() {
                            setState(() {
                              _cart.clear();
                              _resetRoletaState();
                            });
                            _saveCarrinho();
                            if (!sheetContext.mounted) return;
                            showPixQrDialog(
                              context: sheetContext,
                              pixPayload: payload,
                              valor: valorTotal,
                              pedidoId: vendaId,
                            );
                            if (showErrorInCart == null) {
                              if (!sheetContext.mounted) return;
                              showCartSnack(
                                'Escaneie o QR Code ou copie o código para pagar.',
                              );
                            }
                          });
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
                  String? cupomCodigo,
                  String? cupomFreteCodigo,
                  required double descontoCupom,
                  required double valorTotalCheckout,
                  Future<void> Function(String? pedidoId)? onSuccess,
                  void Function(String message)? showErrorInCart,
                }) async {
                  void showErr(String msg) {
                    if (showErrorInCart != null) {
                      showErrorInCart(msg);
                    } else {
                      showCartSnack(msg);
                    }
                  }

                  try {
                    final fpWhatsapp = _prePedidoReuseFingerprintFromCheckout(
                      customer: customer,
                      entrega: entrega,
                      pagamento: pagamento,
                      observacao: observacao,
                      cupomCodigo: cupomCodigo,
                      cupomFreteCodigo: cupomFreteCodigo,
                      descontoCupom: descontoCupom,
                      valorTotalCheckout: valorTotalCheckout,
                      canal: 'whatsapp',
                      cupomRoletaCodigo: cupomRoletaCodigo,
                      cupomRoletaDesconto: cupomRoletaDesconto,
                      premioRoletaDescricao: premioRoletaDescricao,
                    );
                    // ✨ Reutilizar pré-pedido se já foi criado (ex.: após erro em outra forma de pagamento)
                    Map<String, dynamic>? prePedido;
                    if (_ultimoPrePedidoId != null &&
                        _ultimoPrePedidoData != null &&
                        _prePedidoReuseFingerprint == fpWhatsapp &&
                        _prePedidoReuseCanal == 'whatsapp') {
                      prePedido = _ultimoPrePedidoData;
                      logD(
                          '📦 [PRE-PEDIDO] Reutilizando pedido existente: $_ultimoPrePedidoId');
                    } else {
                      try {
                        if (_ultimoPrePedidoId != null) {
                          logD(
                              '📋 [PRE-PEDIDO] Novo documento WhatsApp (substitui sessão anterior: $_ultimoPrePedidoId)');
                        }
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
                          cupomCodigo: cupomCodigo,
                          cupomFreteCodigo: cupomFreteCodigo,
                          desconto: descontoCupom,
                          cupomRoletaCodigo: cupomRoletaCodigo,
                          cupomRoletaDesconto: cupomRoletaDesconto,
                          premioRoletaDescricao: premioRoletaDescricao,
                          vendedorRef: widget.vendedorRef,
                          indicacaoClienteId: widget.indicacaoClienteRef,
                          clienteId: clienteLogado?['clienteId']?.toString(),
                          origemCheckout: 'whatsapp',
                          portalTokenFromSession:
                              clienteLogado?['portalToken']?.toString(),
                          substituiPrePedidoId: _ultimoPrePedidoId,
                          checkoutFingerprint: fpWhatsapp,
                        );
                        if (prePedido != null) {
                          final t = safeDouble(prePedido['total']);
                          if ((t - valorTotalCheckout).abs() > 0.02) {
                            logD(
                                '⚠️ [CHECKOUT] total pré-pedido vs carrinho: $t vs $valorTotalCheckout');
                          }
                        }

                        if (prePedido == null) {
                          showErr('Erro ao criar pedido. Tente novamente.');
                          return;
                        }
                        if (mounted) {
                          setState(() {
                            _ultimoPrePedidoId = prePedido!['id']?.toString();
                            _ultimoPrePedidoData = prePedido;
                            _prePedidoReuseFingerprint = fpWhatsapp;
                            _prePedidoReuseCanal = 'whatsapp';
                          });
                        }
                        logD(
                            '✅ [PRE-PEDIDO] Criado com ID: ${prePedido['id']}');
                      } catch (e) {
                        logD(
                            '❌ Erro ao criar pré-pedido (type=${e.runtimeType})');
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
                      lojaSlug:
                          lojaSlug, // ✅ Passa slug para gerar link correto
                    );

                    // ⭐ GERAR CUPOM E NÚMERO DA SORTE
                    final prePedidoId = prePedidoVal['id']?.toString();
                    try {
                      final cliente =
                          await ClienteAuthService.getClienteLogado();
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
                          'clienteNome':
                              cliente['nome'] ?? customer['nome'] ?? '',
                          'clienteTelefone': customer['telefone'] ?? '',
                        };

                        logD(
                            '📤 [CUPOM] Enviando requisição para Cloud Function:');
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
                            final cupomCodigo =
                                cupom['codigo']?.toString() ?? '';
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
                                _clearPrePedidoReuseSession();
                              });
                            }
                            _saveCarrinho();
                            await onSuccess
                                ?.call(prePedidoVal['id']?.toString());
                            return;
                          } catch (e) {
                            logD(
                                'Erro ao processar cupom (type=${e.runtimeType})');
                          }
                        } else {
                          logD('❌ [CUPOM] Erro HTTP ${response.statusCode}');
                          logD('   Response: ${response.body}');
                        }
                      }
                    } catch (e, stackTrace) {
                      logD(
                          '❌ Erro ao gerar cupom/número (type=${e.runtimeType})');
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
                        _clearPrePedidoReuseSession();
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
                  String? cupomCodigo,
                  String? cupomFreteCodigo,
                  required double descontoCupom,
                  required double valorTotalCheckout,
                  void Function(String message)? showErrorInCart,
                }) async {
                  // Erros devem aparecer na tela do carrinho (não no catálogo)
                  void showErr(String msg) {
                    if (showErrorInCart != null) {
                      showErrorInCart(msg);
                    } else {
                      showCartSnack(msg);
                    }
                  }

                  final fpMp = _prePedidoReuseFingerprintFromCheckout(
                    customer: customer,
                    entrega: entrega,
                    pagamento: pagamento,
                    observacao: observacao,
                    cupomCodigo: cupomCodigo,
                    cupomFreteCodigo: cupomFreteCodigo,
                    descontoCupom: descontoCupom,
                    valorTotalCheckout: valorTotalCheckout,
                    canal: 'mercadopago',
                    cupomRoletaCodigo: cupomRoletaCodigo,
                    cupomRoletaDesconto: cupomRoletaDesconto,
                    premioRoletaDescricao: premioRoletaDescricao,
                  );
                  final bool reuseMpOk = _ultimoPrePedidoId != null &&
                      _prePedidoReuseFingerprint == fpMp &&
                      _prePedidoReuseCanal == 'mercadopago';
                  // ✨ Reutilizar pré-pedido se já foi criado (evita vários pedidos ao trocar forma de pagamento)
                  String? pedidoId = reuseMpOk ? _ultimoPrePedidoId : null;
                  if (pedidoId == null) {
                    try {
                      if (_ultimoPrePedidoId != null) {
                        logD(
                            '📋 [PRE-PEDIDO] Novo documento MP (substitui sessão anterior: $_ultimoPrePedidoId)');
                      }
                      logD(
                          '💳 [MERCADO-PAGO] Criando pré-pedido para loja: $lojaId');
                      final cliente =
                          await ClienteAuthService.getClienteLogado();
                      final prePedido = await PrePedidoService.criarPrePedido(
                        lojaId: lojaId,
                        customer: customer,
                        items: _cart,
                        clienteId: cliente?['clienteId']?.toString(),
                        entrega: entrega,
                        pagamento: pagamento,
                        observacao: observacao,
                        cupomCodigo: cupomCodigo,
                        cupomFreteCodigo: cupomFreteCodigo,
                        desconto: descontoCupom,
                        cupomRoletaCodigo: cupomRoletaCodigo,
                        cupomRoletaDesconto: cupomRoletaDesconto,
                        premioRoletaDescricao: premioRoletaDescricao,
                        vendedorRef: widget.vendedorRef,
                        indicacaoClienteId: widget.indicacaoClienteRef,
                        portalTokenFromSession:
                            cliente?['portalToken']?.toString(),
                        origemCheckout: 'mercadopago',
                        substituiPrePedidoId: _ultimoPrePedidoId,
                        checkoutFingerprint: fpMp,
                      );
                      if (prePedido != null) {
                        final t = safeDouble(prePedido['total']);
                        if ((t - valorTotalCheckout).abs() > 0.02) {
                          logD(
                              '⚠️ [CHECKOUT] total pré-pedido MP vs carrinho: $t vs $valorTotalCheckout');
                        }
                      }
                      pedidoId = prePedido?['id']?.toString();
                      if (pedidoId != null && mounted) {
                        setState(() {
                          _ultimoPrePedidoId = pedidoId;
                          _ultimoPrePedidoData = prePedido;
                          _prePedidoReuseFingerprint = fpMp;
                          _prePedidoReuseCanal = 'mercadopago';
                        });
                        logD(
                            '✅ Pré-pedido criado (aguardando pagamento): $pedidoId');
                      } else {
                        logD('⚠️ Falha ao criar pré-pedido');
                        showErr('Erro ao criar pedido. Tente novamente.');
                        return;
                      }
                    } catch (e) {
                      logD(
                          '❌ Erro ao criar pré-pedido (type=${e.runtimeType})');
                      showErr('Erro ao criar pedido. Tente novamente.');
                      return;
                    }
                  } else {
                    logD(
                        '💳 [MERCADO-PAGO] Reutilizando pré-pedido: $pedidoId');
                  }

                  try {
                    final valorTotal = valorTotalCheckout;
                    if (valorTotal < 0.01) {
                      showErr('Valor do pedido inválido. Tente novamente.');
                      return;
                    }
                    final isPix = pagamento.toUpperCase() == 'PIX';
                    if (isPix &&
                        !catalogCheckoutBuyerValidForMpPix(
                          email: customer['email']?.toString(),
                          cpf: customer['cpf']?.toString(),
                        )) {
                      showErr(
                        'E-mail ou CPF inválidos para PIX. Use um e-mail completo (ex.: '
                        'nome@provedor.com) e CPF com dígitos corretos.',
                      );
                      return;
                    }
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

                    // Sempre mpCatalogPayment: valor canônico vem do pré-pedido no servidor (sem token no cliente).
                    try {
                      final paymentOrigin = kIsWeb
                          ? Uri.base.origin
                          : 'https://app.mastepalm.com.br';
                      final body = <String, dynamic>{
                        'lojaId': lojaId,
                        'orderId': pedidoId,
                        'externalReference': pedidoId,
                        'type': isPix ? 'pix' : 'preference',
                        if (isPix) ...{
                          'descricao': 'Pedido #$pedidoId',
                          'email': (customer['email'] ?? '').toString().trim(),
                          'cpf': customer['cpf']?.toString(),
                        } else ...{
                          'titulo': 'Pedido #$pedidoId',
                          'quantidade': 1,
                          'descricao': 'Compra em $lojaId',
                          // payer montado no servidor (mpCatalogPayment) a partir do pré-pedido em Firestore
                          if (maxInstallmentsSemJuros != null)
                            'maxInstallments': maxInstallmentsSemJuros,
                          if (maxInstallmentsSemJuros != null)
                            'paymentMethods': {
                              'installments': maxInstallmentsSemJuros,
                            },
                          'backUrls': {
                            'success':
                                '$paymentOrigin/pagamento/sucesso?loja=$lojaId',
                            'failure':
                                '$paymentOrigin/pagamento/falha?loja=$lojaId',
                            'pending':
                                '$paymentOrigin/pagamento/pendente?loja=$lojaId',
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
                        paymentData = asMap(jsonDecode(response.body));
                      } else {
                        String errMsg =
                            'Erro ao criar pagamento no Mercado Pago. Tente novamente.';
                        if (response.body.isNotEmpty) {
                          try {
                            final errJson = asMap(jsonDecode(response.body));
                            final friendly =
                                userMessageForMpCheckoutErrorJson(errJson);
                            if (friendly != null) {
                              errMsg = friendly;
                            } else if (errJson['error'] != null) {
                              errMsg = errJson['error'].toString();
                              if (errMsg
                                      .toLowerCase()
                                      .contains('bad_request') ||
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
                      logD('❌ mpCatalogPayment (type=${e.runtimeType})');
                      showErr(
                          'Erro ao criar pagamento no Mercado Pago. Tente novamente.');
                      return;
                    }

                    logD('✅ Pagamento criado: $paymentData');

                    // FASE 3: Não chamar gerarCupomNumeroSorte ao criar pagamento MP — evitava escrita
                    // promocional antes da confirmação e duplicava com o webhook (mpWebhookPromo).
                    // Fonte oficial pós-MP: functions/src/mpWebhookHandler.js → registrarPromocaoPosPagamentoMp.

                    // Obter QR Code ou URL de pagamento primeiro (para abrir o quanto antes)
                    final qrCode = paymentData['qr_code']?.toString();
                    final ticketUrl = paymentData['ticket_url']?.toString();
                    final initPoint = paymentData['init_point']?.toString();

                    // Se tiver init_point (checkout), abrir — NÃO limpar carrinho até pagamento aprovado
                    // (retorno em PagamentoResultadoScreen + CatalogCartPersistence).
                    if (initPoint != null && initPoint.isNotEmpty) {
                      final uri = Uri.tryParse(initPoint);
                      if (uri != null) {
                        final ok = await _launchPaymentUrl(uri);
                        if (!mounted) return;
                        if (!ok) {
                          showErr(
                              'Não foi possível abrir o link de pagamento.');
                        } else if (showErrorInCart == null) {
                          showCartSnack(
                              'Pagamento criado! Abrindo checkout...');
                        }
                        return;
                      }
                    }

                    // Se tiver ticket_url (PIX direto), abrir — carrinho permanece até confirmação
                    if (ticketUrl != null && ticketUrl.isNotEmpty) {
                      final uri = Uri.tryParse(ticketUrl);
                      if (uri != null) {
                        final ok = await _launchPaymentUrl(uri);
                        if (!mounted) return;
                        if (!ok) {
                          showErr('Não foi possível abrir o comprovante PIX.');
                        } else if (showErrorInCart == null) {
                          showCartSnack('PIX gerado! Abrindo comprovante...');
                        }
                        return;
                      }
                    }

                    // Se tiver QR Code, mostrar dialog PIX — carrinho só zera após aprovação no retorno MP
                    if (qrCode != null && qrCode.isNotEmpty) {
                      if (mounted) {
                        await _runStateAfterFrame(() {
                          if (!mounted) return;
                          if (showErrorInCart == null) {
                            showCartSnack(
                              'PIX gerado! Escaneie o QR Code para pagar.',
                            );
                          }

                          // 🔔 O webhook processará a confirmação: pagamento concluído e novo pedido recebido
                          if (!sheetContext.mounted) return;
                          final scaffoldContext =
                              Navigator.of(sheetContext).context;
                          if (scaffoldContext.mounted) {
                            showPixQrDialog(
                              context: scaffoldContext,
                              pixPayload: qrCode,
                              valor: valorTotal,
                              pedidoId: pedidoId,
                            );
                          }
                        });
                      }
                      return;
                    }

                    showErr('Pagamento criado, mas sem dados de QR Code.');
                  } catch (e) {
                    logD(
                        '❌ Erro ao processar pagamento (type=${e.runtimeType})');
                    showErr('Erro ao processar pagamento: $e');
                  }
                },
              );
            },
          ),
        ),
      );
    }

    if (!mounted) return;
    if (wideChrome) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (sheetContext) {
          final mq = MediaQuery.of(sheetContext);
          final maxW = math.min(kMaxContentWidth, mq.size.width - 40);
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW,
                maxHeight: mq.size.height * 0.92,
              ),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: carrinhoContent(sheetContext),
              ),
            ),
          );
        },
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return Container(
            margin: const EdgeInsets.only(top: 24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: carrinhoContent(sheetContext),
          );
        },
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
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
    // Só tenta app do Instagram para links reais do Instagram (evita abrir IG para sites como mastepalm.com.br).
    if (!kIsWeb) {
      final igUri = Uri.tryParse(finalUrl);
      final host = igUri?.host.toLowerCase() ?? '';
      if (host.contains('instagram.com') &&
          await openInstagramInApp(finalUrl)) {
        return;
      }
    }
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
    // Web: `externalApplication` costuma falhar no navegador; usar janela explícita.
    if (kIsWeb) {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!ok) {
        _snack('Não foi possível abrir o link.');
      }
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

  /// Legado: chamava `gerarCupomNumeroSorte` ao **criar** pagamento MP (antes da aprovação).
  /// Mantido vazio de propósito: a participação em campanha / número da sorte para pedidos MP
  /// é registrada no servidor em `processMpWebhook` → `registrarPromocaoPosPagamentoMp`
  /// após pagamento aprovado (idempotente). Não remover o método para evitar churn de merge.
  // ignore: unused_element
  Future<void> _gerarCupomNumeroSorteBackground({
    required String lojaId,
    required String pedidoId,
    required double valorTotal,
    required Map<String, dynamic> customer,
  }) async {
    logD(
      '[PROMO-SKIP] MP create-payment: promoção definitiva via webhook (mpWebhookPromo); '
      'pedidoId=$pedidoId',
    );
  }

  String _normalizeWhatsappForWaMe(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.length == 10 || digits.length == 11) {
      return '55$digits';
    }
    return digits;
  }

  String _resolveCatalogWhatsappNumber(Map<String, dynamic> cfg) {
    final links = mpMapDyn(cfg['links']);
    final empresa = mpMapDyn(cfg['empresa']);
    final rodape = mpMapDyn(cfg['rodape']);
    final candidates = <dynamic>[
      cfg['whatsapp'],
      cfg['whatsappLoja'],
      cfg['telefoneWhatsapp'],
      cfg['numeroWhatsapp'],
      cfg['whatsapp_vendedor'],
      rodape['whatsapp'],
      links['whatsapp'],
      empresa['whatsapp'],
      cfg['telefone'],
    ];
    for (final c in candidates) {
      final normalized = _normalizeWhatsappForWaMe(c?.toString());
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  Future<void> _openCatalogMaintenanceWhatsapp(String phone) async {
    final normalized = _normalizeWhatsappForWaMe(phone);
    if (normalized.isEmpty) return;
    final uri = Uri.parse(
      'https://wa.me/$normalized?text=${Uri.encodeComponent(_catalogMaintenanceWhatsappPrefill)}',
    );
    if (kIsWeb) {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildCatalogMaintenanceScaffold({
    required String lojaNome,
    required String logoUrl,
    required String mensagem,
    required String whatsappNumber,
    required Color primaryColor,
    required Color bgColor,
    required Color cardColor,
    required Color textColor,
    required Color btnTextColor,
  }) {
    final hasWhatsapp = whatsappNumber.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (logoUrl.trim().isNotEmpty) ...[
                      SizedBox(
                        height: 72,
                        child: SmartImage(src: logoUrl, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: primaryColor,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Site em manutenção',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      mensagem.trim().isEmpty
                          ? _catalogMaintenanceDefaultMessage
                          : mensagem,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor.withOpacity(0.88),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (hasWhatsapp)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openCatalogMaintenanceWhatsapp(
                            whatsappNumber,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: btnTextColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: const Icon(Icons.chat),
                          label: const Text('Comprar no WhatsApp'),
                        ),
                      )
                    else
                      Text(
                        'WhatsApp da loja ainda não configurado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor.withOpacity(0.75),
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      lojaNome,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
      if (kIsWeb) {
        await launchUrl(
          url,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );
      } else {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      logD('❌ Erro ao abrir WhatsApp (type=${e.runtimeType})');
      _snack('Não foi possível abrir o WhatsApp. Tente novamente.');
    }
  }

  void _scheduleHtmlLoaderHandoff(String reason) {
    if (!kIsWeb || _htmlLoaderHandoffDone) return;
    _htmlLoaderHandoffDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      plat.Web.notifyCatalogHtmlLoaderReady(reason);
    });
  }

  void _onCatalogEarlyShellFirstFrame() {
    if (!kIsWeb) return;
    plat.Web.notifyCatalogShellReady();
    _scheduleHtmlLoaderHandoff('catalog_shell_ready');
    if (!_traceShellFirstFrameLogged) {
      _traceShellFirstFrameLogged = true;
      CatalogStartupTrace.mark(
        'CAT_START.catalog_shell.first_frame',
        data: <String, Object?>{'loja_id': _resolvedLojaId},
      );
    }
  }

  Widget _wrapWithCatStartDiagOverlay(Widget child) {
    if (!_diagCatStartOverlayEnabled) return child;
    const trackedEvents = <String>[
      'CAT_START.main.enter',
      'CAT_START.runApp.catalog_web_root.fast_path',
      'CAT_START.public_screen.init_state',
      'CAT_START.resolve_loja_id.end',
      'CAT_START.cfg_stream.first_data',
      'CAT_START.produtos_stream.first_data',
      'CAT_START.first_useful_paint',
      'CAT_START.products_grid.first_viewport_frame',
      'CAT_START.catalog_interactive',
    ];
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: 8,
          bottom: 8,
          child: IgnorePointer(
            child: ValueListenableBuilder<int>(
              valueListenable: CatalogStartupTrace.revisionListenable,
              builder: (_, __, ___) {
                final events = CatalogStartupTrace.eventsSnapshot();
                final tracked = <Map<String, Object?>>[];
                for (final name in trackedEvents) {
                  int? tMs;
                  for (final e in events.reversed) {
                    if (e['event'] == name) {
                      tMs = e['t_ms'] as int?;
                      break;
                    }
                  }
                  tracked.add(<String, Object?>{
                    'event': name,
                    't_ms': tMs,
                  });
                }
                final tail = events
                    .where((e) =>
                        (e['event']?.toString() ?? '').startsWith('CAT_START.'))
                    .toList()
                    .reversed
                    .take(10)
                    .toList()
                    .reversed
                    .toList();
                return Container(
                  width: 360,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.25,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('CAT_START DIAG (temporário)'),
                        const SizedBox(height: 6),
                        for (final e in tracked)
                          Text(
                            '${e['event']}: ${e['t_ms'] ?? '--'}ms',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 6),
                        const Text('Últimos CAT_START:'),
                        for (final e in tail)
                          Text(
                            '- ${e['event']} @ ${e['t_ms']}ms',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
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
    if (kIsWeb) {
      plat.Web.localStorageSet(
          'mp_catalog_phase', 'publicCatalogScreen.build.start');
    }
    try {
      if (!_traceBuildEnteredLogged) {
        _traceBuildEnteredLogged = true;
        CatalogStartupTrace.mark(
          'CAT_START.public_screen.build_enter',
          data: <String, Object?>{
            'loja_id_raw': widget.lojaId,
            'preview': widget.preview,
          },
        );
      }
      final themeData = _modoEscuro ? ThemeData.dark() : ThemeData.light();
      // Usar tema do contexto (ex.: web) para loading/erro, evitando tela branca
      final themeForStates = Theme.of(context);
      if (_loadingLojaId) {
        return _wrapWithCatStartDiagOverlay(
          CatalogLoadingState(themeData: themeForStates),
        );
      }

      if (_resolvedLojaId == null || _resolvedLojaId!.isEmpty) {
        _scheduleHtmlLoaderHandoff('catalog_error');
        return _wrapWithCatStartDiagOverlay(
          CatalogErrorLojaState(
            themeData: themeForStates,
            detailMessage: _catalogOpenFailureDetail,
            diagnosticText: _catalogTraceDiagnosticText(),
          ),
        );
      }
      if (!_traceFirstUsefulPaintLogged) {
        _traceFirstUsefulPaintLogged = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          CatalogStartupTrace.mark(
            'CAT_START.first_useful_paint',
            data: <String, Object?>{'loja_id': _resolvedLojaId},
          );
        });
      }

      if (kDebugMode) {
        logD('📱 [CATALOG] Renderizando loja: $_resolvedLojaId');
      }

      final rendered = _wrapWithCatStartDiagOverlay(
        Theme(
          data: themeData,
          child: StreamBuilder<Map<String, dynamic>>(
            stream: _getConfigStream(lojaId),
            builder: (context, cfgSnap) {
              // Usar tema do MaterialApp (themeForStates) para evitar tela branca na web
              if (cfgSnap.connectionState == ConnectionState.waiting) {
                if (!_traceConfigWaitingLogged) {
                  _traceConfigWaitingLogged = true;
                  CatalogStartupTrace.mark(
                    'CAT_START.cfg_builder.waiting',
                    data: <String, Object?>{'loja_id': lojaId},
                  );
                }
                if (kIsWeb) {
                  return CatalogEarlyShellView(
                    storeSlug: widget.lojaId,
                    themeData: themeForStates,
                    onFirstFrame: _onCatalogEarlyShellFirstFrame,
                  );
                }
                return CatalogConfigLoadingState(themeData: themeForStates);
              }
              if (!cfgSnap.hasData) {
                CatalogNormalTrace.setField('config.exists', false);
                CatalogNormalTrace.setField(
                    'fallback.reason', 'config_stream_no_data');
                CatalogNormalTrace.mark('config.missing_or_empty',
                    <String, Object?>{'loja_id': lojaId});
                _scheduleHtmlLoaderHandoff('catalog_error');
                return CatalogConfigErrorState(themeData: themeForStates);
              }
              if (!_htmlLoaderHandoffDone) {
                _scheduleHtmlLoaderHandoff('catalog_config_ready');
              }
              if (!_normalTraceRenderCatalogStartLogged) {
                _normalTraceRenderCatalogStartLogged = true;
                CatalogNormalTrace.setField('config.exists', true);
                CatalogNormalTrace.mark(
                    'render.catalog.start', <String, Object?>{'loja_id': lojaId});
              }
              if (!_traceConfigReadyLogged) {
                _traceConfigReadyLogged = true;
                CatalogStartupTrace.mark(
                  'CAT_START.cfg_builder.ready',
                  data: <String, Object?>{
                    'loja_id': lojaId,
                    'cfg_keys':
                        (cfgSnap.data ?? const <String, dynamic>{}).length,
                  },
                );
              }

              final Map<String, dynamic> cfg =
                  (cfgSnap.data ?? {}).map((k, v) => MapEntry(k.toString(), v));
              _catalogUrlConfigMerge =
                  CatalogPublicUrlService.coalesceCatalogUrlConfig(
                cfg,
                _catalogUrlConfigMerge,
              );

              if (!widget.preview &&
                  CatalogPublicUrlService.tryCustomCatalogPublicRoot(
                        _catalogUrlConfigMerge,
                      ) ==
                      null) {
                _catalogUrlDraftEnrichSeq++;
                final seq = _catalogUrlDraftEnrichSeq;
                final loja = lojaId;
                final baseline =
                    Map<String, dynamic>.from(_catalogUrlConfigMerge);
                CatalogPublicUrlService.mergeDraftConfigDomainForCatalogUrls(
                  loja,
                  baseline,
                ).then((enriched) {
                  if (!mounted || seq != _catalogUrlDraftEnrichSeq) return;
                  if (identical(enriched, baseline)) return;
                  if (CatalogPublicUrlService.tryCustomCatalogPublicRoot(
                        enriched,
                      ) ==
                      null) {
                    return;
                  }
                  setState(() => _catalogUrlConfigMerge = enriched);
                });
              }

              if (kDebugMode) {
                logD(
                    '📄 [CATÁLOGO] Config carregado: ${cfg.keys.length} chaves');
              }

              // Número único: rodapé (Loja Config) > campos legados no root — o checkout
              // usava só o root; se o WhatsApp estava só em rodape.whatsapp, o carrinho
              // dizia "não configurado" mesmo com o rodapé exibindo o contato.
              final rodapeForWhatsapp = mpMapDyn(cfg['rodape']);
              final whatsappRodape =
                  (rodapeForWhatsapp['whatsapp'] ?? '').toString().trim();
              final whatsappNoRoot =
                  (cfg['whatsapp_vendedor'] ?? cfg['whatsapp'] ?? '')
                      .toString()
                      .trim();
              final atendimentoWhatsapp =
                  whatsappRodape.isNotEmpty ? whatsappRodape : whatsappNoRoot;
              final whatsappVendedor = atendimentoWhatsapp;
              final mercadoPagoAtivo = catalogConfigMercadoPagoAtivo(cfg);

              // =================== CONFIGURAÇÕES DE LAYOUT ===================
              final cardShowShadow = safeBool(cfg['cardShowShadow'], true);
              final cardBorderRadius =
                  safeDouble(cfg['cardBorderRadius'], 18.0);
              final gridDesktopCols =
                  safeInt(cfg['gridDesktopCols'], 4).clamp(2, 6);
              final gridMobileCols =
                  safeInt(cfg['gridMobileCols'], 2).clamp(1, 4);

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
                      colorFromTheme('texto', Colors.white.withOpacity(0.95)))
                  : colorFromTheme('texto', Colors.white.withOpacity(0.95));
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
              final headerTextColor =
                  colorFromHeaderColors('text', Colors.white);
              final headerIconColor =
                  colorFromHeaderColors('icon', Colors.white);
              final headerSearchBg =
                  colorFromHeaderColors('searchBackground', Colors.white10);
              final headerSearchText =
                  colorFromHeaderColors('searchText', Colors.white);
              final headerSearchHint =
                  colorFromHeaderColors('searchHint', Colors.white70);

              // ===== Cores do rodapé =====
              final footerBgColor =
                  colorFromFooterColors('background', bgColor);
              final footerTextColor =
                  colorFromFooterColors('text', Colors.white);
              final footerTextSecondary =
                  colorFromFooterColors('textSecondary', Colors.white70);
              final footerIconColor =
                  colorFromFooterColors('icon', Colors.white70);
              final footerLinkColor =
                  colorFromFooterColors('link', primaryColor);
              final footerDividerColor =
                  colorFromFooterColors('divider', Colors.white24);

              // ===== Cores da tela Dicas e Informações =====
              CatalogDicasColors? catalogDicasColors;
              if (dicasColorsMap.isNotEmpty) {
                catalogDicasColors = CatalogDicasColors(
                  background: colorFromDicasColors(
                      'background', const Color(0xFFF8F9FA)),
                  footerBackground:
                      colorFromDicasColors('footerBackground', Colors.white),
                  footerText:
                      colorFromDicasColors('footerText', Colors.black87),
                  buttonBackground: colorFromDicasColors(
                      'buttonBackground', const Color(0xFF22C55E)),
                  buttonText: colorFromDicasColors('buttonText', Colors.white),
                  topicPrimary: colorFromDicasColors(
                      'topicPrimary', const Color(0xFF22C55E)),
                );
              }

              if (kDebugMode && themeMap.isEmpty && uiColorsMap.isEmpty) {
                logD(
                    '⚠️ [CATÁLOGO] cfg["theme"] e cfg["uiColors"] vazios, usando padrão');
              }

              // ===== Cores do checkout / carrinho =====
              // Prioriza uiColors > checkoutTheme > fallback
              final checkoutCardColor = uiColorsMap.isNotEmpty
                  ? colorFromUiColors('cardBackground',
                      colorFromCheckoutTheme('card', cardColor))
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
                  ? colorFromUiColors(
                      'fieldBorder', Colors.white.withOpacity(0.25))
                  : Colors.white.withOpacity(0.25);

              final catalogThemeDataResolved = CatalogThemeData.fromConfig(cfg);
              final catalogCheckoutSummaryTokens =
                  CatalogCheckoutSummaryTokens.fromThemeData(
                      catalogThemeDataResolved);
              final catalogCartUiTokens = CatalogCartUiTokens.fromConfig(
                cfg,
                theme: catalogThemeDataResolved,
              );
              final catalogFirstPurchaseCouponOffer =
                  CatalogFirstPurchaseCouponOffer.parse(
                cfg,
                theme: catalogThemeDataResolved,
              );

              // ===== Cores de nome e preço do produto =====
              final productNameColor = cardTextPrimary;
              final productPriceColor = priceHighlightColor;

              // =================== IDENTIDADE / LINKS ===================
              final lojaNome =
                  catalogHeaderStoreNameFromCfg(cfg) ?? 'Minha Loja';
              final catalogoEmManutencao = !widget.preview &&
                  safeBool(cfg['catalogoEmManutencao'], false);
              final mensagemManutencaoCatalogo =
                  (cfg['mensagemManutencaoCatalogo'] ?? '').toString().trim();
              final whatsappCatalogoManutencao =
                  _resolveCatalogWhatsappNumber(cfg);

              final links = mpMapDyn(cfg['links']);
              final rodapeLinks = mpMapDyn(cfg['rodape']);

              final instagramUrl =
                  (rodapeLinks['instagram'] ?? links['instagram'] ?? '')
                      .toString();
              final facebookUrl =
                  (rodapeLinks['facebook'] ?? links['facebook'] ?? '')
                      .toString();
              final tiktokUrl = (rodapeLinks['tiktok'] ?? '').toString();
              final telegramUrl = (rodapeLinks['telegram'] ?? '').toString();
              final kwaiUrl = (rodapeLinks['kwai'] ?? '').toString();
              final linkedinUrl = (rodapeLinks['linkedin'] ?? '').toString();
              final emailUrl = (rodapeLinks['email'] ?? '').toString();
              final whatsappUrl = (rodapeLinks['whatsapp'] ?? '').toString();
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
              final freteMelhorEnvioModoExibicaoRaw =
                  (cfg['freteMelhorEnvioModoExibicao'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
              final freteMelhorEnvioModoExibicao =
                  freteMelhorEnvioModoExibicaoRaw == 'somente_correios'
                      ? 'somente_correios'
                      : 'todas_transportadoras';

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
                  final pixMap =
                      pixRaw.map((k, v) => MapEntry(k.toString(), v));
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
              // Mesmo breakpoint de `CatalogBannerCarousel` (1024): evita carregar
              // banners de desktop no layout mobile (ou o contrário) em resoluções médias.
              final isWide = size.width >= 1024;
              final mediaConfig = parseMedia(cfg, isWide: isWide);
              catalogDebugLogHeaderUi(
                lojaId: lojaId,
                cfg: cfg,
                isWide: isWide,
              );
              final logoUrl = mediaConfig.logoUrl;
              final banners = mediaConfig.banners;
              final bannerH = mediaConfig.bannerH;
              if (!_traceHeaderReadyLogged) {
                _traceHeaderReadyLogged = true;
                CatalogStartupTrace.mark(
                  'CAT_START.header_structure.ready',
                  data: <String, Object?>{
                    'loja_id': lojaId,
                    'logo_present': logoUrl.isNotEmpty,
                    'banners_count': banners.length,
                    'banner_h': bannerH,
                  },
                );
              }
              // O modo manutenção bloqueia apenas a visualização pública do catálogo.
              // Não remove produtos, não altera estoque e não interfere no painel admin.
              if (catalogoEmManutencao) {
                final mensagem = mensagemManutencaoCatalogo.isEmpty
                    ? '$_catalogMaintenanceDefaultMessage ✨'
                    : mensagemManutencaoCatalogo;
                return _buildCatalogMaintenanceScaffold(
                  lojaNome: lojaNome,
                  logoUrl: logoUrl,
                  mensagem: mensagem,
                  whatsappNumber: whatsappCatalogoManutencao,
                  primaryColor: primaryColor,
                  bgColor: bgColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  btnTextColor: btnTextColor,
                );
              }
              return Theme(
                data: Theme.of(context).copyWith(
                  scaffoldBackgroundColor: bgColor,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: primaryColor,
                    brightness:
                        _modoEscuro ? Brightness.dark : Brightness.light,
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
                    if (prodSnap.connectionState == ConnectionState.waiting &&
                        !_traceProductsWaitingLogged) {
                      _traceProductsWaitingLogged = true;
                      CatalogStartupTrace.mark(
                        'CAT_START.products_builder.waiting',
                        data: <String, Object?>{'loja_id': lojaId},
                      );
                    }
                    if (!_traceInteractiveLogged &&
                        cfgSnap.hasData &&
                        prodSnap.hasData) {
                      _traceInteractiveLogged = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        CatalogStartupTrace.mark(
                          'CAT_START.catalog_interactive',
                          data: <String, Object?>{
                            'loja_id': lojaId,
                            'produtos_count': prodSnap.data?.docs.length ?? 0,
                          },
                        );
                      });
                    }
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
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
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
                    if (prodSnap.hasData && !_traceProductsDataReadyLogged) {
                      _traceProductsDataReadyLogged = true;
                      CatalogStartupTrace.mark(
                        'CAT_START.products_builder.ready',
                        data: <String, Object?>{
                          'loja_id': lojaId,
                          'docs_count': docs.length,
                        },
                      );
                    }

                    final produtos = _processDocsToProductsCached(docs);
                    CatalogNormalTrace.setField(
                        'produtos.afterClientFilters.count', produtos.length);
                    if (prodSnap.hasData && !_normalTraceRenderSuccessLogged) {
                      _normalTraceRenderSuccessLogged = true;
                      CatalogNormalTrace.mark(
                          'render.catalog.success', <String, Object?>{
                        'raw_docs': docs.length,
                        'after_filters': produtos.length,
                      });
                    }
                    if (!_traceProductsVisibleLogged) {
                      _traceProductsVisibleLogged = true;
                      CatalogStartupTrace.mark(
                        'CAT_START.products_visible.ready',
                        data: <String, Object?>{
                          'loja_id': lojaId,
                          'produtos_count': produtos.length,
                        },
                      );
                    }

                    if (produtos.isNotEmpty && _cart.isNotEmpty) {
                      final cleanupSig =
                          '$_lastProdutosDocsSig|cart:${_cart.length}';
                      if (_lastCartCleanupSig != cleanupSig) {
                        _lastCartCleanupSig = cleanupSig;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _limparCartDeProdutosRemovidos(produtos);
                        });
                      }
                    }

                    const badgeSSL = 'assets/badges/ssl.png';
                    const badgeGoogle =
                        'assets/badges/google-safe-browsing.png';

                    final sobreLojaConfig = CatalogSobreLojaConfig.fromCfg(cfg);

                    final footerLinks = <Map<String, String>>[
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
                    final politicaPrivacidadeUrl =
                        (cfg['politicaPrivacidadeUrl'] ??
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
                    if (!_traceEssentialActionsEnabledLogged) {
                      _traceEssentialActionsEnabledLogged = true;
                      CatalogStartupTrace.mark(
                        'CAT_START.essential_actions.enabled',
                        data: <String, Object?>{
                          'loja_id': lojaId,
                          'cart_count': cartCount,
                          'has_whatsapp': whatsappVendedor.trim().isNotEmpty,
                        },
                      );
                    }

                    final layoutCatalogo = CatalogLayoutConfig.normalize(
                      cfg['layoutCatalogo'] ?? cfg['layout_catalogo'],
                    );
                    final bool useMinimalLayout =
                        CatalogLayoutConfig.isMinimal(layoutCatalogo);
                    final viewportW = MediaQuery.sizeOf(context).width;
                    final int catalogGridMobileCols = !useMinimalLayout &&
                            viewportW < 640 &&
                            gridMobileCols > 2
                        ? 2
                        : gridMobileCols;
                    _tryHandleInitialProdutoDeepLink(
                      produtos: produtos,
                    );
                    final promoBarCfg = mpMapDyn(cfg['promoBar']);
                    final minimalSearchCfg = mpMapDyn(cfg['minimalSearch']);
                    final categoryVisualsCfg = mpMapDyn(cfg['categoryVisuals']);
                    final heroBannerCfg = mpMapDyn(cfg['heroBanner']);
                    final heroBannerSizeMode =
                        (heroBannerCfg['bannerMinimalistaTamanho'] ?? 'grande')
                            .toString()
                            .trim();
                    final heroBannerCompactImageUrl =
                        (heroBannerCfg['bannerMinimalistaCompactoUrl'] ?? '')
                            .toString();
                    final heroBannerActionLink =
                        catalogHeroBannerActionUrl(heroBannerCfg);
                    final minimalGridCfg = mpMapDyn(cfg['minimalProductGrid']);
                    final productCardSize = CatalogProductCardSize.normalize(
                      cfg['productCardSize'],
                    );
                    final minimalBestSellersCfg =
                        mpMapDyn(cfg['minimalBestSellers']);
                    final bestSellersSectionEnabled =
                        safeBool(minimalBestSellersCfg['enabled'], true);
                    final bestSellersTitle =
                        (minimalBestSellersCfg['title'] ?? 'Mais vendidos')
                            .toString();
                    final bestSellersLimit =
                        safeInt(minimalBestSellersCfg['count'], 10)
                            .clamp(3, 24);

                    // Banner hero minimalista: card / tipografia / botão (Loja Config — draft_config).
                    final heroCardCfg = mpMapDyn(heroBannerCfg['card']);
                    final heroTitleStyle =
                        mpMapDyn(heroBannerCfg['titleStyle']);
                    final heroSubtitleStyle =
                        mpMapDyn(heroBannerCfg['subtitleStyle']);
                    final heroButtonStyle =
                        mpMapDyn(heroBannerCfg['buttonStyle']);
                    final Color heroLegacyText =
                        readColorFromCfg(heroBannerCfg['textColor']) ??
                            Colors.white;
                    final Color heroLegacyCardBg =
                        readColorFromCfg(heroBannerCfg['backgroundColor']) ??
                            cardColor;
                    final Color heroLegacyBtnBg =
                        readColorFromCfg(heroBannerCfg['buttonColor']) ??
                            primaryColor;
                    final Color heroBannerCardBg =
                        readColorFromCfg(heroCardCfg['backgroundColor']) ??
                            heroLegacyCardBg;
                    final double heroBannerCardRadius = safeDouble(
                      heroCardCfg['borderRadius'],
                      safeDouble(heroBannerCfg['borderRadius'], 18),
                    );
                    final Color heroBannerTitleColor =
                        readColorFromCfg(heroTitleStyle['color']) ??
                            heroLegacyText;
                    final double heroBannerTitleSize =
                        safeDouble(heroTitleStyle['fontSize'], 17);
                    final FontWeight heroBannerTitleW = parseFontWeightCfg(
                        heroTitleStyle['fontWeight'], FontWeight.w600);
                    final String heroBannerTitleCase =
                        (heroTitleStyle['letterCase'] ?? 'none').toString();
                    final Color heroBannerSubtitleColor =
                        readColorFromCfg(heroSubtitleStyle['color']) ??
                            heroLegacyText.withOpacity(0.96);
                    final double heroBannerSubtitleSize =
                        safeDouble(heroSubtitleStyle['fontSize'], 13);
                    final FontWeight heroBannerSubtitleW = parseFontWeightCfg(
                        heroSubtitleStyle['fontWeight'], FontWeight.w400);
                    final String heroBannerSubtitleCase =
                        (heroSubtitleStyle['letterCase'] ?? 'none').toString();
                    final Color heroBannerBtnBg =
                        readColorFromCfg(heroButtonStyle['backgroundColor']) ??
                            readColorFromCfg(heroButtonStyle['background']) ??
                            heroLegacyBtnBg;
                    final Color heroBannerBtnText =
                        readColorFromCfg(heroButtonStyle['textColor']) ??
                            Colors.white;
                    final double heroBannerBtnSize =
                        safeDouble(heroButtonStyle['fontSize'], 13);
                    final FontWeight heroBannerBtnW = parseFontWeightCfg(
                        heroButtonStyle['fontWeight'], FontWeight.w600);
                    final double heroBannerBtnRadius =
                        safeDouble(heroButtonStyle['borderRadius'], 8);
                    final String heroBannerBtnCase =
                        (heroButtonStyle['letterCase'] ?? 'none').toString();

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
                    final mostrarQuantidadeNoCatalogo = safeBool(
                        cfg['mostrarQuantidadeNoCatalogo'],
                        _mostrarQuantidadeNoCatalogo);
                    final mostrarEstoqueNoCatalogo = safeBool(
                        cfg['mostrarEstoqueNoCatalogo'],
                        _mostrarEstoqueNoCatalogo);

                    // categorias únicas para o menu lateral
                    // Compatibilidade: lê tanto 'categoria' quanto 'categoriaId'
                    final categoriasSet = <String>{};
                    final categoryAliasesByName = <String, Set<String>>{};
                    for (final p in produtos) {
                      for (final c in _produtoCategoriasAssociadas(p)) {
                        categoriasSet.add(c);
                        final aliases = categoryAliasesByName.putIfAbsent(
                            c, () => <String>{});
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
                    final menuShowQuemSomos =
                        safeBool(menuMap['quemSomos'], true);
                    final menuShowDicas = safeBool(menuMap['dicas'], true);
                    final exibirAvaliacoesCatalogo = safeBool(
                          cfg['exibirAvaliacoesCatalogo'] ??
                              cfg['exibir_depoimentos_catalogo'],
                          false,
                        ) &&
                        !_previewHideAvaliacoesForAdmin;
                    final catalogAvaliacoesOrdem =
                        CatalogAvaliacoesOrdem.fromFirestore(
                      cfg['catalogAvaliacoesOrdem'],
                    );
                    final indicacaoRaw = cfg['indicacao'];
                    final indicacaoAtivo =
                        indicacaoRaw is Map && (indicacaoRaw['ativo'] == true);

                    // DEBUG: Ver se está lendo as configurações do menu
                    if (kDebugMode) {
                      logD(
                          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                      logD('📋 [MENU CONFIG] Configurações do menu:');
                      logD('   menuRaw existe: ${menuRaw != null}');
                      logD('   menuMap: $menuMap');
                      logD('   Categorias: $menuShowCategorias');
                      logD('   Entrar: $menuShowEntrar');
                      logD('   Contato: $menuShowContato');
                      logD('   SAC: $menuShowSac');
                      logD('   Quem Somos: $menuShowQuemSomos');
                      logD(
                          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
                    }

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
                        if (d.ativo && d.titulo.trim().isNotEmpty) {
                          dicasList.add(d);
                        }
                      }
                    }

                    final w = MediaQuery.of(context).size.width;
                    final isDesktop = w >= 1024;

                    // Link direto: ?page=dicas abre a página de dicas ao carregar
                    if (widget.initialPage == 'dicas' && !_openedInitialPage) {
                      _openedInitialPage = true;
                      final contact = DicasContactInfo(
                        whatsappNumber: atendimentoWhatsapp,
                        instagramUrl:
                            instagramUrl.isNotEmpty ? instagramUrl : null,
                        facebookUrl:
                            facebookUrl.isNotEmpty ? facebookUrl : null,
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
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                                            colorClaro:
                                                mediaConfig.logoColorClaro,
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
                                          _clearFiltrosVariacao();
                                          _currentPageNotifier.value = 0;
                                        });
                                        _onCatalogCategoryOrSubChanged();
                                      },
                                    ),

                                    // PRODUTOS (sem filtro, mostra todos)
                                    ListTile(
                                      leading:
                                          const Icon(Icons.grid_view_outlined),
                                      title: const Text('Produtos'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        setState(() {
                                          _selectedCategory = null;
                                          _selectedSubcategory = null;
                                          _clearFiltrosVariacao();
                                          _currentPageNotifier.value = 0;
                                        });
                                        _onCatalogCategoryOrSubChanged();
                                      },
                                    ),

                                    // CATEGORIAS E SUBCATEGORIAS (condicional)
                                    if (menuShowCategorias &&
                                        categoriasMenu.isNotEmpty) ...[
                                      const Padding(
                                        padding:
                                            EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                                          if (_produtoTemCategoria(p, cat)) {
                                            for (final sub
                                                in _produtoSubcategoriasAssociadas(
                                                    p)) {
                                              if (sub.isNotEmpty) {
                                                subcategoriasSet.add(sub);
                                              }
                                            }
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
                                                _clearFiltrosVariacao();
                                                _currentPageNotifier.value = 0;
                                              });
                                              _onCatalogCategoryOrSubChanged();
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
                                                  Icons
                                                      .subdirectory_arrow_right,
                                                  size: 18,
                                                  color: primaryColor
                                                      .withOpacity(0.7)),
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
                                                  _clearFiltrosVariacao();
                                                  _currentPageNotifier.value =
                                                      0;
                                                });
                                                _onCatalogCategoryOrSubChanged();
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
                                key: ValueKey(_menuClienteAuthRetryKey),
                                future: ClienteAuthService.getClienteLogado(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          ListTile(
                                            leading: Icon(
                                              Icons.cloud_off_outlined,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                            title: const Text(
                                              'Não foi possível carregar sua sessão',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              kDebugMode
                                                  ? snapshot.error.toString()
                                                  : 'Verifique a conexão e tente de novo.',
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ),
                                          TextButton.icon(
                                            onPressed: () {
                                              setState(() =>
                                                  _menuClienteAuthRetryKey++);
                                            },
                                            icon: const Icon(Icons.refresh,
                                                size: 20),
                                            label:
                                                const Text('Tentar novamente'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14),
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      ),
                                    );
                                  }

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
                                          subtitle:
                                              const Text('Ver meu perfil'),
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
                                            ).then((_) async {
                                              await _loadClienteAndFavoritos();
                                              if (!mounted) return;
                                              setState(() =>
                                                  _menuClienteAuthRetryKey++);
                                            });
                                          },
                                        ),
                                        if (indicacaoAtivo &&
                                            clienteId.isNotEmpty)
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
                                                _resolvedLojaId ??
                                                    widget.lojaId;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    LoginScreenCliente(
                                                        lojaId: lojaIdAuth),
                                              ),
                                            ).then((_) async {
                                              await _loadClienteAndFavoritos();
                                              if (!mounted) return;
                                              setState(() =>
                                                  _menuClienteAuthRetryKey++);
                                            });
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.person_add),
                                          title: const Text('Cadastrar'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            final lojaIdAuth =
                                                _resolvedLojaId ??
                                                    widget.lojaId;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    CadastroScreenCliente(
                                                        lojaId: lojaIdAuth),
                                              ),
                                            ).then((_) async {
                                              await _loadClienteAndFavoritos();
                                              if (!mounted) return;
                                              setState(() =>
                                                  _menuClienteAuthRetryKey++);
                                            });
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
                                  _modoEscuro
                                      ? Icons.dark_mode
                                      : Icons.light_mode,
                                  color: primaryColor,
                                ),
                              ),

                              // SAC (elogios, sugestões e críticas) - condicional
                              if (menuShowSac)
                                ListTile(
                                  leading:
                                      const Icon(Icons.support_agent_outlined),
                                  title: const Text(
                                      'SAC – elogios, sugestões e críticas',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () {
                                    Navigator.pop(context);

                                    final sacNumber =
                                        sacWhatsapp.trim().isNotEmpty
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
                                      backgroundColor: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      builder: (_) {
                                        final texto = quemSomosTexto
                                                .trim()
                                                .isEmpty
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
                                                  style: (Theme.of(context)
                                                              .textTheme
                                                              .titleLarge ??
                                                          const TextStyle(
                                                            fontSize: 22,
                                                          ))
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
                                          lojaId:
                                              _resolvedLojaId ?? widget.lojaId,
                                          lojaNome: lojaNome,
                                          dicas: dicasList,
                                          primaryColor: primaryColor,
                                          logoUrl: logoUrl.isNotEmpty
                                              ? logoUrl
                                              : null,
                                          logoHeight: isWide ? 90 : 80,
                                          bannerHeightCard:
                                              mediaConfig.bannerH * 0.65,
                                          bannerHeightDetail:
                                              mediaConfig.bannerH * 0.85,
                                          dicasColors: catalogDicasColors,
                                          contactInfo: DicasContactInfo(
                                            whatsappNumber: atendimentoWhatsapp,
                                            instagramUrl:
                                                instagramUrl.isNotEmpty
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
                        // Margem extra vs conteúdo do título (busca + chips) para evitar overflow vertical residual.
                        // Minimal: altura do AppBar equilibrada com ícones + busca (logo não domina a faixa).
                        toolbarHeight: useMinimalLayout
                            ? (isDesktop ? 112 : 100)
                            : (isDesktop
                                ? (categoriasMenu.isEmpty
                                    ? 152
                                    : (!_catalogExibindoTodosCategorias()
                                        ? 248
                                        : 198))
                                : (categoriasMenu.isEmpty
                                    ? 132
                                    : (!_catalogExibindoTodosCategorias()
                                        ? 228
                                        : 178))),
                        titleSpacing: 0,
                        automaticallyImplyLeading: false,
                        title: LayoutBuilder(
                          builder: (context, constraints) {
                            return Align(
                              alignment: Alignment.topCenter,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                // Não limitar maxHeight aqui: o Column estoura antes do FittedBox escalar (overflow ~20px).
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // ======= LINHA SUPERIOR: MENU + LOGO + PUBLICAR + CARRINHO =======
                                      () {
                                        // Minimal: logo no centro *global* do AppBar (Stack);
                                        // a Row só reserva a faixa central; sem logo duplicar offset dos ícones.
                                        final topBarRow = Row(
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
                                                onPressed: () =>
                                                    Scaffold.of(ctx)
                                                        .openDrawer(),
                                              ),
                                            ),

                                            // Clássico: logo no Expanded. Minimal: vazio — layer de logo abaixo.
                                            Expanded(
                                              child: useMinimalLayout
                                                  ? const SizedBox.shrink()
                                                  : Center(
                                                      child: logoUrl.isNotEmpty
                                                          ? SizedBox(
                                                              height: isDesktop
                                                                  ? 68
                                                                  : 56,
                                                              child: Image(
                                                                image:
                                                                    mpImageProvider(
                                                                        logoUrl),
                                                                fit: BoxFit
                                                                    .contain,
                                                                filterQuality:
                                                                    FilterQuality
                                                                        .high,
                                                                isAntiAlias:
                                                                    true,
                                                              ),
                                                            )
                                                          : Text(
                                                              lojaNome,
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 22,
                                                                color:
                                                                    headerTextColor, // ✅ Usa cor do cabeçalho
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                    ),
                                            ),

                                            // 🌐 BOTÃO ABRIR CATÁLOGO WEB (sempre visível)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 4),
                                              child: IconButton(
                                                icon: Icon(
                                                  Icons.language,
                                                  size: 26,
                                                  color:
                                                      headerIconColor, // ✅ Usa cor do cabeçalho
                                                ),
                                                tooltip:
                                                    'Abrir catálogo online',
                                                onPressed: () async {
                                                  final messenger =
                                                      ScaffoldMessenger.of(
                                                          context);
                                                  final url =
                                                      _publicCatalogShareBase();
                                                  logD(
                                                      '🌐 Abrindo catálogo web: $url');

                                                  final uri = Uri.parse(url);
                                                  if (await canLaunchUrl(uri)) {
                                                    await launchUrl(
                                                      uri,
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    );

                                                    if (mounted) {
                                                      messenger.showSnackBar(
                                                        SnackBar(
                                                          content: const Text(
                                                              'Abrindo navegador...'),
                                                          duration:
                                                              const Duration(
                                                                  seconds: 2),
                                                          backgroundColor:
                                                              primaryColor,
                                                        ),
                                                      );
                                                    }
                                                  } else {
                                                    if (mounted) {
                                                      messenger.showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Não foi possível abrir: $url'),
                                                          backgroundColor:
                                                              Colors.red,
                                                          action:
                                                              SnackBarAction(
                                                            label: 'Copiar',
                                                            textColor:
                                                                Colors.white,
                                                            onPressed: () {
                                                              Clipboard.setData(
                                                                  ClipboardData(
                                                                      text:
                                                                          url));
                                                            },
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                },
                                              ),
                                            ),

                                            // ✅ Só no preview interno (admin): fallback Web quando não há
                                            // histórico para voltar. Catálogo público online (preview: false)
                                            // NUNCA mostra isto — evita levar o cliente para /home do app interno.
                                            if (kIsWeb &&
                                                widget.preview &&
                                                !Navigator.of(context).canPop())
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 4),
                                                child: IconButton(
                                                  icon: const Icon(
                                                      Icons.home_outlined),
                                                  color: headerIconColor,
                                                  tooltip: 'Voltar para Home',
                                                  onPressed: () {
                                                    Navigator.of(context)
                                                        .pushNamed('/home');
                                                  },
                                                ),
                                              ),

                                            // BOTÃO PUBLICAR (só no preview, dentro do app)
                                            if (widget.preview)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 4),
                                                child: FilledButton(
                                                  style: FilledButton.styleFrom(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 12,
                                                    ),
                                                    minimumSize:
                                                        const Size(0, 40),
                                                    backgroundColor:
                                                        primaryColor,
                                                    foregroundColor:
                                                        btnTextColor,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                    ),
                                                  ),
                                                  onPressed: _publicando
                                                      ? null
                                                      : publicarCatalogo,
                                                  child: Text(
                                                    _publicando
                                                        ? 'Publicando...'
                                                        : 'Publicar',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),

                                            // ÍCONE DO CARRINHO (SEM TEXTO)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons
                                                        .shopping_bag_outlined),
                                                    color:
                                                        headerIconColor, // ✅ Usa cor do cabeçalho
                                                    onPressed: () =>
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
                                                          _paymentCodesParaPreviaRodape(
                                                              paymentCodes),
                                                      instagramUrl:
                                                          instagramUrl,
                                                      facebookUrl: facebookUrl,
                                                      empresaRazao:
                                                          empresaRazao,
                                                      empresaCnpj: empresaCnpj,
                                                      checkoutGateway:
                                                          checkoutGateway,
                                                      checkoutButtonLabel:
                                                          checkoutButtonLabel,
                                                      pixKey: pixKey,
                                                      freightToken:
                                                          freightToken,
                                                      freteMelhorEnvioModoExibicao:
                                                          freteMelhorEnvioModoExibicao,
                                                      mercadoPagoAtivo:
                                                          mercadoPagoAtivo,
                                                      checkoutSummaryTokens:
                                                          catalogCheckoutSummaryTokens,
                                                      catalogCartUiTokens:
                                                          catalogCartUiTokens,
                                                      catalogFirstPurchaseCouponOffer:
                                                          catalogFirstPurchaseCouponOffer,
                                                      catalogProducts: produtos,
                                                    ),
                                                  ),
                                                  if (cartCount > 0)
                                                    Positioned(
                                                      right: 4,
                                                      top: 6,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(3),
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              Colors.redAccent,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(10),
                                                        ),
                                                        child: Text(
                                                          '$cartCount',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );

                                        if (!useMinimalLayout) {
                                          return topBarRow;
                                        }
                                        final dpr =
                                            MediaQuery.devicePixelRatioOf(
                                                context);
                                        // Proporção ao catálogo: altura próxima à linha de ícones; largura limitada
                                        // (evita logos horizontais ocuparem a faixa inteira como no screenshot).
                                        final logoMaxH =
                                            isDesktop ? 52.0 : 44.0;
                                        final topBarH = isDesktop ? 56.0 : 48.0;
                                        return SizedBox(
                                          height: topBarH,
                                          width: double.infinity,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            alignment: Alignment.center,
                                            children: [
                                              if (logoUrl.isNotEmpty)
                                                Positioned.fill(
                                                  child: LayoutBuilder(
                                                    builder: (context, b) {
                                                      final fullW = b.maxWidth;
                                                      final logoCapW = math.min(
                                                        fullW *
                                                            (isDesktop
                                                                ? 0.42
                                                                : 0.48),
                                                        isDesktop
                                                            ? 300.0
                                                            : 220.0,
                                                      );
                                                      return Center(
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      6),
                                                          child: SizedBox(
                                                            width: logoCapW,
                                                            height: logoMaxH,
                                                            child: Image(
                                                              image:
                                                                  ResizeImage(
                                                                mpImageProvider(
                                                                    logoUrl),
                                                                width: (logoCapW *
                                                                        dpr)
                                                                    .round()
                                                                    .clamp(64,
                                                                        2048),
                                                                height:
                                                                    (logoMaxH *
                                                                            dpr)
                                                                        .round()
                                                                        .clamp(
                                                                            64,
                                                                            1024),
                                                                allowUpscaling:
                                                                    false,
                                                              ),
                                                              width: logoCapW,
                                                              height: logoMaxH,
                                                              fit: BoxFit
                                                                  .contain,
                                                              filterQuality:
                                                                  FilterQuality
                                                                      .high,
                                                              isAntiAlias: true,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                )
                                              else
                                                Positioned.fill(
                                                  child: Center(
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 24),
                                                      child: FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          lojaNome,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 22,
                                                            color:
                                                                headerTextColor,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              topBarRow,
                                            ],
                                          ),
                                        );
                                      }(),

                                      const SizedBox(height: 8),

                                      // ======= BARRA DE PESQUISA + CATEGORIAS (mobile; desktop = sidebar) =======
                                      CatalogSearchBar(
                                        controller: _searchController,
                                        headerSearchText: headerSearchText,
                                        headerSearchHint: headerSearchHint,
                                        headerSearchBg: useMinimalLayout
                                            ? (readColorFromCfg(
                                                    minimalSearchCfg[
                                                        'background']) ??
                                                Colors.white)
                                            : headerSearchBg,
                                        hintText: (minimalSearchCfg[
                                                    'placeholder'] ??
                                                'O que voce esta procurando?')
                                            .toString(),
                                        iconOnRight: useMinimalLayout,
                                        borderColor: useMinimalLayout
                                            ? (readColorFromCfg(
                                                    minimalSearchCfg[
                                                        'borderColor']) ??
                                                Colors.black12)
                                            : null,
                                        borderRadius: useMinimalLayout
                                            ? safeDouble(
                                                minimalSearchCfg['radius'], 10)
                                            : 12,
                                        height: useMinimalLayout
                                            ? safeDouble(
                                                minimalSearchCfg['height'], 44)
                                            : 42,
                                        onChanged: _debouncedSearchUpdate,
                                        onClear: () {
                                          _searchDebounce?.cancel();
                                          _searchController.clear();
                                          _searchNotifier.value = '';
                                          _currentPageNotifier.value = 0;
                                          _syncCatalogQueryToBrowserUri();
                                        },
                                      ),
                                      if (!isDesktop && !useMinimalLayout)
                                        CatalogCategorySubcategoryFilters(
                                          categoriasMenu: categoriasMenu,
                                          selectedCategory: _selectedCategory,
                                          selectedSubcategory:
                                              _selectedSubcategory,
                                          produtos: produtos,
                                          textColor: textColor,
                                          cardColor: cardColor,
                                          primaryColor: primaryColor,
                                          onCategorySelectedNull: () {
                                            setState(() {
                                              _selectedCategory = null;
                                              _selectedSubcategory = null;
                                              _clearFiltrosVariacao();
                                              _currentPageNotifier.value = 0;
                                            });
                                            _onCatalogCategoryOrSubChanged();
                                          },
                                          onCategorySelected: (cat) {
                                            setState(() {
                                              _selectedCategory = cat;
                                              _selectedSubcategory = null;
                                              _clearFiltrosVariacao();
                                              _currentPageNotifier.value = 0;
                                            });
                                            _onCatalogCategoryOrSubChanged();
                                          },
                                          onSubcategorySelectedNull: () {
                                            setState(() {
                                              _selectedSubcategory = null;
                                              _clearFiltrosVariacao();
                                              _currentPageNotifier.value = 0;
                                            });
                                            _onCatalogCategoryOrSubChanged();
                                          },
                                          onSubcategorySelected: (subcat) {
                                            setState(() {
                                              _selectedSubcategory = subcat;
                                              _clearFiltrosVariacao();
                                              _currentPageNotifier.value = 0;
                                            });
                                            _onCatalogCategoryOrSubChanged();
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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
                                paymentCodes:
                                    _paymentCodesParaPreviaRodape(paymentCodes),
                                instagramUrl: instagramUrl,
                                facebookUrl: facebookUrl,
                                empresaRazao: empresaRazao,
                                empresaCnpj: empresaCnpj,
                                checkoutGateway: checkoutGateway,
                                checkoutButtonLabel: checkoutButtonLabel,
                                pixKey: pixKey,
                                freightToken: freightToken,
                                freteMelhorEnvioModoExibicao:
                                    freteMelhorEnvioModoExibicao,
                                mercadoPagoAtivo: mercadoPagoAtivo,
                                checkoutSummaryTokens:
                                    catalogCheckoutSummaryTokens,
                                catalogCartUiTokens: catalogCartUiTokens,
                                catalogFirstPurchaseCouponOffer:
                                    catalogFirstPurchaseCouponOffer,
                                catalogProducts: produtos,
                              ),
                              icon: const Icon(Icons.shopping_bag_outlined),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Carrinho ($cartCount)'),
                              ),
                            ),

// ================= CORPO =================
                      body: Stack(
                        children: [
                          Column(
                            children: [
                              if (useMinimalLayout &&
                                  _catalogExibindoTodosCategorias() &&
                                  safeBool(promoBarCfg['enabled'], false))
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 6, 12, 8),
                                  child: CatalogPromoBar(
                                    enabled: true,
                                    text:
                                        (promoBarCfg['text'] ?? '').toString(),
                                    backgroundColor: readColorFromCfg(
                                            promoBarCfg['backgroundColor']) ??
                                        const Color(0xFFFF4F96),
                                    textColor: readColorFromCfg(
                                            promoBarCfg['textColor']) ??
                                        Colors.white,
                                    icon:
                                        safeBool(promoBarCfg['showIcon'], false)
                                            ? Icons.local_offer_outlined
                                            : null,
                                    height:
                                        safeDouble(promoBarCfg['height'], 34),
                                    textAlign: parseTextAlign(
                                        promoBarCfg['alignment'],
                                        TextAlign.center),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
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
                                          final isDesktopBody =
                                              c.maxWidth >= 1024;
                                          final effCatFilter =
                                              _effectiveCatalogCategoryFilter();
                                          final effSubFilter =
                                              _effectiveCatalogSubcategoryFilter();
                                          // Quando uma categoria/subcategoria específica está selecionada, o catálogo
                                          // vira uma listagem direta de produtos. Banners, mais vendidos e destaques
                                          // devem aparecer apenas em Todos.
                                          final exibindoTodosCatalogo =
                                              effCatFilter == null;
                                          final modoListagemCategoria =
                                              effCatFilter != null;
                                          bool matchCategoriaSub(
                                              Map<String, dynamic> p) {
                                            final matchCat =
                                                _produtoTemCategoria(
                                              p,
                                              effCatFilter,
                                            );
                                            final matchSubcat =
                                                _produtoTemSubcategoria(
                                              p,
                                              effSubFilter,
                                            );
                                            return matchCat && matchSubcat;
                                          }

                                          final produtosParaOpcoesVariacao =
                                              produtos
                                                  .where(matchCategoriaSub)
                                                  .toList();
                                          final variacaoTamanhosOpcoes =
                                              CatalogVariationFilter
                                                  .coletarTamanhos(
                                                      produtosParaOpcoesVariacao);
                                          final variacaoCoresOpcoes =
                                              CatalogVariationFilter.coletarCores(
                                                  produtosParaOpcoesVariacao);
                                          final variacaoExtrasOpcoes =
                                              CatalogVariationFilter
                                                  .coletarExtras(
                                                      produtosParaOpcoesVariacao);

                                          final listaOrdenada =
                                              _catalogListaOrdenadaMemo(
                                            produtos: produtos,
                                            search: search,
                                            effCatFilter: effCatFilter,
                                            effSubFilter: effSubFilter,
                                          );

                                          // Paginação: 20 produtos por página
                                          final totalPaginas =
                                              (listaOrdenada.length /
                                                      _produtosPorPagina)
                                                  .ceil()
                                                  .clamp(1, 999999);
                                          _catalogTotalPaginasForUrl =
                                              totalPaginas;

                                          if (prodSnap.hasData) {
                                            final categoryAliasesSig =
                                                _categoryAliasesSignature(
                                                    categoryAliasesByName);
                                            final sig =
                                                '${produtos.length}|${categoriasMenu.join('\u0001')}|$categoryAliasesSig|$effCatFilter|$effSubFilter|$_ordenacaoProdutos|${_precoMin}_$_precoMax|${variacaoTamanhosOpcoes.join('\u0001')}|${variacaoCoresOpcoes.join('\u0001')}|${variacaoExtrasOpcoes.join('\u0001')}|$search|$_apenasEmEstoque|$_filtroVariacaoTamanho|$_filtroVariacaoCor|$_filtroVariacaoExtra|$totalPaginas';
                                            if (sig !=
                                                _lastCatalogSanitizeSig) {
                                              _lastCatalogSanitizeSig = sig;
                                              final gen = ++_catalogSanitizeGen;
                                              final tList = List<String>.from(
                                                  variacaoTamanhosOpcoes);
                                              final cList = List<String>.from(
                                                  variacaoCoresOpcoes);
                                              final xList = List<String>.from(
                                                  variacaoExtrasOpcoes);
                                              final catList = List<String>.from(
                                                  categoriasMenu);
                                              final aliasCopy =
                                                  Map<String, Set<String>>.from(
                                                categoryAliasesByName.map(
                                                  (k, v) => MapEntry(
                                                    k,
                                                    Set<String>.from(v),
                                                  ),
                                                ),
                                              );
                                              final prodCopy = List<
                                                  Map<String,
                                                      dynamic>>.from(produtos);
                                              final tpSan = totalPaginas;
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                if (!mounted ||
                                                    gen !=
                                                        _catalogSanitizeGen) {
                                                  return;
                                                }
                                                _sanitizeCatalogUrlDerivedFilters(
                                                  categoriasMenu: catList,
                                                  categoryAliasesByName:
                                                      aliasCopy,
                                                  produtos: prodCopy,
                                                  tamanhos: tList,
                                                  cores: cList,
                                                  extras: xList,
                                                  totalPaginas: tpSan,
                                                );
                                              });
                                            }
                                          }

                                          final paginaAtual = currentPage.clamp(
                                              0, totalPaginas - 1);
                                          final start =
                                              paginaAtual * _produtosPorPagina;
                                          final listaPaginated = listaOrdenada
                                              .skip(start)
                                              .take(_produtosPorPagina)
                                              .toList();

                                          final minimalSubcats = useMinimalLayout &&
                                                  effCatFilter != null
                                              ? _subcategoriasDisponiveisParaCategoria(
                                                  effCatFilter,
                                                  produtos,
                                                )
                                              : <String>[];

                                          final scrollBody = CustomScrollView(
                                            controller:
                                                _catalogScrollController,
                                            // Web: área maior fora da viewport reduz descarte/rebuild de cards ao rolar.
                                            cacheExtent: _catalogProductsScrollCacheExtent(),
                                            physics: const ClampingScrollPhysics(
                                                parent:
                                                    AlwaysScrollableScrollPhysics()),
                                            slivers: [
                                              SliverToBoxAdapter(
                                                child: Column(
                                                  children: [
                                                    if (exibindoTodosCatalogo &&
                                                        banners.isNotEmpty)
                                                      CatalogBannerCarousel(
                                                        banners: banners,
                                                        height: bannerH,
                                                        resolvedLojaId:
                                                            _resolvedLojaId ??
                                                                widget.lojaId,
                                                        onBannerPressed:
                                                            (i, url) {
                                                          if (url
                                                              .trim()
                                                              .isEmpty) {
                                                            return;
                                                          }
                                                          _openUrl(url);
                                                        },
                                                      ),
                                                    // Mesmo no modo listagem por categoria, o menu horizontal de categorias deve continuar visível para permitir troca rápida de categoria. Apenas banners, destaques e mais vendidos ficam ocultos.
                                                    if (useMinimalLayout &&
                                                        menuShowCategorias &&
                                                        categoriasMenu
                                                            .isNotEmpty &&
                                                        (exibindoTodosCatalogo ||
                                                            modoListagemCategoria))
                                                      CatalogMinimalCategoryImageStrip(
                                                        categories:
                                                            categoriasMenu,
                                                        selectedCategory:
                                                            _selectedCategory,
                                                        categoryVisuals:
                                                            categoryVisualsCfg,
                                                        categoryAliasesByName:
                                                            categoryAliasesByName,
                                                        onSelect: (cat) {
                                                          setState(() {
                                                            _selectedCategory =
                                                                cat;
                                                            _selectedSubcategory =
                                                                null;
                                                            _clearFiltrosVariacao();
                                                            _currentPageNotifier
                                                                .value = 0;
                                                          });
                                                          _onCatalogCategoryOrSubChanged();
                                                        },
                                                        onClear: () {
                                                          setState(() {
                                                            _selectedCategory =
                                                                null;
                                                            _selectedSubcategory =
                                                                null;
                                                            _clearFiltrosVariacao();
                                                            _currentPageNotifier
                                                                .value = 0;
                                                          });
                                                          _onCatalogCategoryOrSubChanged();
                                                        },
                                                        textColor: textColor,
                                                        fallbackBg: cardColor,
                                                      ),
                                                    if (useMinimalLayout &&
                                                        effCatFilter != null &&
                                                        minimalSubcats
                                                            .isNotEmpty)
                                                      CatalogMinimalSubcategoryStrip(
                                                        subcategories:
                                                            minimalSubcats,
                                                        selectedSubcategory:
                                                            _selectedSubcategory,
                                                        primaryColor:
                                                            primaryColor,
                                                        textColor: textColor,
                                                        surfaceColor: cardColor,
                                                        onSelectAll: () {
                                                          setState(() {
                                                            _selectedSubcategory =
                                                                null;
                                                            _currentPageNotifier
                                                                .value = 0;
                                                          });
                                                          _onCatalogCategoryOrSubChanged();
                                                        },
                                                        onSelectSub: (sub) {
                                                          setState(() {
                                                            _selectedSubcategory =
                                                                sub;
                                                            _currentPageNotifier
                                                                .value = 0;
                                                          });
                                                          _onCatalogCategoryOrSubChanged();
                                                        },
                                                      ),
                                                    if (modoListagemCategoria)
                                                      Padding(
                                                        padding:
                                                            EdgeInsets.fromLTRB(
                                                          16,
                                                          useMinimalLayout
                                                              ? 8
                                                              : 12,
                                                          16,
                                                          useMinimalLayout
                                                              ? 4
                                                              : 8,
                                                        ),
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Text(
                                                            _catalogListagemTituloLinha() ??
                                                                '',
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              color: textColor,
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    if (useMinimalLayout &&
                                                        exibindoTodosCatalogo)
                                                      CatalogMinimalHeroBanner(
                                                        enabled: safeBool(
                                                            heroBannerCfg[
                                                                'enabled'],
                                                            false),
                                                        title: (heroBannerCfg[
                                                                    'title'] ??
                                                                '')
                                                            .toString(),
                                                        subtitle: (heroBannerCfg[
                                                                    'subtitle'] ??
                                                                '')
                                                            .toString(),
                                                        buttonText: (heroBannerCfg[
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
                                                        compactImageUrl:
                                                            heroBannerCompactImageUrl,
                                                        bannerSizeMode:
                                                            heroBannerSizeMode,
                                                        resolvedLojaId:
                                                            _resolvedLojaId ??
                                                                widget.lojaId,
                                                        backgroundColor:
                                                            heroBannerCardBg,
                                                        borderRadius:
                                                            heroBannerCardRadius,
                                                        height: safeDouble(
                                                            heroBannerCfg[
                                                                'height'],
                                                            isDesktop
                                                                ? 240
                                                                : 180),
                                                        overlayOpacity: safeDouble(
                                                            heroBannerCfg[
                                                                'overlayOpacity'],
                                                            0.16),
                                                        titleColor:
                                                            heroBannerTitleColor,
                                                        titleFontSize:
                                                            heroBannerTitleSize,
                                                        titleFontWeight:
                                                            heroBannerTitleW,
                                                        titleLetterCase:
                                                            heroBannerTitleCase,
                                                        subtitleColor:
                                                            heroBannerSubtitleColor,
                                                        subtitleFontSize:
                                                            heroBannerSubtitleSize,
                                                        subtitleFontWeight:
                                                            heroBannerSubtitleW,
                                                        subtitleLetterCase:
                                                            heroBannerSubtitleCase,
                                                        buttonBackgroundColor:
                                                            heroBannerBtnBg,
                                                        buttonTextColor:
                                                            heroBannerBtnText,
                                                        buttonFontSize:
                                                            heroBannerBtnSize,
                                                        buttonFontWeight:
                                                            heroBannerBtnW,
                                                        buttonBorderRadius:
                                                            heroBannerBtnRadius,
                                                        buttonLetterCase:
                                                            heroBannerBtnCase,
                                                        onTap: heroBannerActionLink !=
                                                                    null &&
                                                                heroBannerActionLink
                                                                    .isNotEmpty
                                                            ? () => _openUrl(
                                                                  heroBannerActionLink,
                                                                )
                                                            : null,
                                                      ),
                                                    if (useMinimalLayout &&
                                                        exibindoTodosCatalogo &&
                                                        bestSellersSectionEnabled &&
                                                        produtos.isNotEmpty)
                                                      CatalogMinimalBestSellersSection(
                                                        title: bestSellersTitle,
                                                        productCardSize:
                                                            productCardSize,
                                                        products:
                                                            pickBestSellersForMinimalCatalog(
                                                          produtos,
                                                          limit:
                                                              bestSellersLimit,
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
                                                          buttonText:
                                                              btnTextColor,
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
                                                          facebookUrl:
                                                              facebookUrl,
                                                          empresaRazao:
                                                              empresaRazao,
                                                          empresaCnpj:
                                                              empresaCnpj,
                                                          checkoutGateway:
                                                              checkoutGateway,
                                                          checkoutButtonLabel:
                                                              checkoutButtonLabel,
                                                          pixKey: pixKey,
                                                          freightToken:
                                                              freightToken,
                                                          freteMelhorEnvioModoExibicao:
                                                              freteMelhorEnvioModoExibicao,
                                                          mercadoPagoAtivo:
                                                              mercadoPagoAtivo,
                                                          checkoutSummaryTokens:
                                                              catalogCheckoutSummaryTokens,
                                                          catalogCartUiTokens:
                                                              catalogCartUiTokens,
                                                          catalogFirstPurchaseCouponOffer:
                                                              catalogFirstPurchaseCouponOffer,
                                                          catalogProducts:
                                                              produtos,
                                                        ),
                                                        catalogShareUrl:
                                                            CatalogShareService
                                                                .buildUrlWithParams(
                                                          _publicCatalogShareBase(),
                                                          ref: widget
                                                              .vendedorRef,
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
                                                        onProductUrlFocus:
                                                            _onProductUrlFocus,
                                                        onProductUrlBlur:
                                                            _onProductUrlBlur,
                                                      ),
                                                    if (exibindoTodosCatalogo)
                                                      const SizedBox(
                                                          height: 16),

                                                    // ✨ BANNER DE CAMPANHAS
                                                    if (exibindoTodosCatalogo)
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
                                                  mobileCols:
                                                      catalogGridMobileCols,
                                                  childAspectRatio: useMinimalLayout
                                                      ? _minimalCatalogGridAspectRatio(
                                                          isDesktopBody:
                                                              isDesktopBody,
                                                          baseFromSizeOrConfig:
                                                              CatalogProductCardSize
                                                                  .minimalAspectRatio(
                                                            productCardSize,
                                                          ),
                                                        )
                                                      : _classicCatalogGridAspectRatio(
                                                          width: viewportW,
                                                          baseStandardAspectRatio:
                                                              CatalogProductCardSize
                                                                  .standardAspectRatio(
                                                            productCardSize,
                                                          ),
                                                        ),
                                                )
                                              else if (listaOrdenada.isEmpty)
                                                modoListagemCategoria &&
                                                        _catalogSemFiltrosAlemDeCategoria(
                                                            search)
                                                    ? SliverFillRemaining(
                                                        hasScrollBody: false,
                                                        child: Center(
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(24),
                                                            child: Text(
                                                              'Nenhum produto encontrado nesta categoria.',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: TextStyle(
                                                                color:
                                                                    textColor,
                                                                fontSize: 16,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    : const CatalogEmptyProductsState()
                                              else ...[
                                                // Ordenação (filtros) - linha separada da paginação para evitar sobreposição
                                                SliverToBoxAdapter(
                                                  child:
                                                      CatalogSortFiltersSection(
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
                                                        _ordenacaoProdutos =
                                                            value;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                      _syncCatalogQueryToBrowserUri();
                                                    },
                                                    onFilterEmEstoqueToggled:
                                                        () {
                                                      setState(() {
                                                        _apenasEmEstoque =
                                                            !_apenasEmEstoque;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                    },
                                                    onFilterPrecoTap: () =>
                                                        _mostrarDialogoFiltroPreco(
                                                            textColor),
                                                    paginaAtual: paginaAtual,
                                                    totalPaginas: totalPaginas,
                                                    onPageChanged: (p) {
                                                      _currentPageNotifier
                                                          .value = p;
                                                    },
                                                    variacaoTamanhos:
                                                        variacaoTamanhosOpcoes,
                                                    variacaoCores:
                                                        variacaoCoresOpcoes,
                                                    variacaoExtras:
                                                        variacaoExtrasOpcoes,
                                                    filtroVariacaoTamanho:
                                                        _filtroVariacaoTamanho,
                                                    filtroVariacaoCor:
                                                        _filtroVariacaoCor,
                                                    filtroVariacaoExtra:
                                                        _filtroVariacaoExtra,
                                                    onVariacaoTamanhoChanged:
                                                        (v) {
                                                      setState(() {
                                                        _filtroVariacaoTamanho =
                                                            v;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                      _syncCatalogQueryToBrowserUri();
                                                    },
                                                    onVariacaoCorChanged: (v) {
                                                      setState(() {
                                                        _filtroVariacaoCor = v;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                      _syncCatalogQueryToBrowserUri();
                                                    },
                                                    onVariacaoExtraChanged:
                                                        (v) {
                                                      setState(() {
                                                        _filtroVariacaoExtra =
                                                            v;
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                      _syncCatalogQueryToBrowserUri();
                                                    },
                                                    onVariacaoClear: () {
                                                      setState(() {
                                                        _clearFiltrosVariacao();
                                                        _currentPageNotifier
                                                            .value = 0;
                                                      });
                                                      _syncCatalogQueryToBrowserUri();
                                                    },
                                                  ),
                                                ),
                                                if (exibindoTodosCatalogo &&
                                                    _recentIds.isNotEmpty)
                                                  buildCatalogRecentSectionSliver(
                                                    recentProducts: () {
                                                      final pm = {
                                                        for (final p
                                                            in produtos)
                                                          safeStr(p['id']): p
                                                      };
                                                      return _recentIds
                                                          .where((id) => pm
                                                              .containsKey(id))
                                                          .take(8)
                                                          .map((id) => pm[id])
                                                          .whereType<
                                                              Map<String,
                                                                  dynamic>>()
                                                          .toList();
                                                    }(),
                                                    todosProdutos: produtos,
                                                    lojaId: lojaId,
                                                    onAdd: (it) => _addToCart(
                                                        it, produtos),
                                                    onProductViewed:
                                                        _onProductViewed,
                                                    onProductUrlFocus:
                                                        _onProductUrlFocus,
                                                    onProductUrlBlur:
                                                        _onProductUrlBlur,
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
                                                      paymentAsset:
                                                          paymentAssets,
                                                      paymentCodes:
                                                          _paymentCodesParaPreviaRodape(
                                                              paymentCodes),
                                                      instagramUrl:
                                                          instagramUrl,
                                                      facebookUrl: facebookUrl,
                                                      empresaRazao:
                                                          empresaRazao,
                                                      empresaCnpj: empresaCnpj,
                                                      checkoutGateway:
                                                          checkoutGateway,
                                                      checkoutButtonLabel:
                                                          checkoutButtonLabel,
                                                      pixKey: pixKey,
                                                      freightToken:
                                                          freightToken,
                                                      freteMelhorEnvioModoExibicao:
                                                          freteMelhorEnvioModoExibicao,
                                                      mercadoPagoAtivo:
                                                          mercadoPagoAtivo,
                                                      checkoutSummaryTokens:
                                                          catalogCheckoutSummaryTokens,
                                                      catalogCartUiTokens:
                                                          catalogCartUiTokens,
                                                      catalogFirstPurchaseCouponOffer:
                                                          catalogFirstPurchaseCouponOffer,
                                                      catalogProducts: produtos,
                                                    ),
                                                    clienteId: _clienteId,
                                                    favoritosIds: _favoritosIds,
                                                    mostrarEstoqueNoCatalogo:
                                                        mostrarEstoqueNoCatalogo,
                                                    mostrarQuantidadeNoCatalogo:
                                                        mostrarQuantidadeNoCatalogo,
                                                    cardBorderRadius:
                                                        cardBorderRadius,
                                                    cardShowShadow:
                                                        cardShowShadow,
                                                    prazoEntregaTexto:
                                                        prazoEntregaTexto,
                                                    jurosParcelamento:
                                                        jurosParcelamento,
                                                    maxParcelas:
                                                        maxParcelasClamped,
                                                    textColor: textColor,
                                                    useMinimalLayout:
                                                        useMinimalLayout,
                                                    productCardSize:
                                                        productCardSize,
                                                    cardColor: cardColor,
                                                    priceColor:
                                                        productPriceColor,
                                                    catalogShareUrl:
                                                        CatalogShareService
                                                            .buildUrlWithParams(
                                                      _publicCatalogShareBase(),
                                                      ref: widget.vendedorRef,
                                                      indicacao: widget
                                                          .indicacaoClienteRef,
                                                    ),
                                                    nomeLoja: lojaNome,
                                                    contatoWhatsapp:
                                                        whatsappVendedor,
                                                    politicaFrete: null,
                                                    catalogInitialExtraValor:
                                                        _filtroVariacaoExtra,
                                                    onCatalogVariacaoExtraChanged:
                                                        _onCatalogVariacaoExtraFromProductUi,
                                                  ),
                                                buildCatalogProductsGridSliver(
                                                  products: listaPaginated,
                                                  todosProdutosParaCombo:
                                                      produtos,
                                                  lojaId: lojaId,
                                                  catalogInitialExtraValor:
                                                      _filtroVariacaoExtra,
                                                  onCatalogVariacaoExtraChanged:
                                                      _onCatalogVariacaoExtraFromProductUi,
                                                  isDesktop: isDesktopBody,
                                                  desktopCols: gridDesktopCols,
                                                  mobileCols:
                                                      catalogGridMobileCols,
                                                  classicGridWideBody:
                                                      !useMinimalLayout &&
                                                          isDesktopBody,
                                                  onAdd: (it) =>
                                                      _addToCart(it, produtos),
                                                  onProductViewed:
                                                      _onProductViewed,
                                                  onProductUrlFocus:
                                                      _onProductUrlFocus,
                                                  onProductUrlBlur:
                                                      _onProductUrlBlur,
                                                  onProductsGridFirstViewportFrame:
                                                      _traceProductsGridFirstViewportLogged
                                                          ? null
                                                          : () {
                                                              if (_traceProductsGridFirstViewportLogged) {
                                                                return;
                                                              }
                                                              _traceProductsGridFirstViewportLogged =
                                                                  true;
                                                              CatalogStartupTrace
                                                                  .mark(
                                                                'CAT_START.products_grid.first_viewport_frame',
                                                                data: <String,
                                                                    Object?>{
                                                                  'loja_id':
                                                                      lojaId,
                                                                  'grid_item_count':
                                                                      listaPaginated
                                                                          .length,
                                                                },
                                                              );
                                                            },
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
                                                    paymentCodes:
                                                        _paymentCodesParaPreviaRodape(
                                                            paymentCodes),
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
                                                    freteMelhorEnvioModoExibicao:
                                                        freteMelhorEnvioModoExibicao,
                                                    mercadoPagoAtivo:
                                                        mercadoPagoAtivo,
                                                    checkoutSummaryTokens:
                                                        catalogCheckoutSummaryTokens,
                                                    catalogCartUiTokens:
                                                        catalogCartUiTokens,
                                                    catalogFirstPurchaseCouponOffer:
                                                        catalogFirstPurchaseCouponOffer,
                                                    catalogProducts: produtos,
                                                  ),
                                                  clienteId: _clienteId,
                                                  favoritosIds: _favoritosIds,
                                                  mostrarEstoqueNoCatalogo:
                                                      mostrarEstoqueNoCatalogo,
                                                  mostrarQuantidadeNoCatalogo:
                                                      mostrarQuantidadeNoCatalogo,
                                                  cardBorderRadius: useMinimalLayout
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
                                                  maxParcelas:
                                                      maxParcelasClamped,
                                                  imageCacheWidth:
                                                      useMinimalLayout
                                                          ? safeInt(
                                                              minimalGridCfg[
                                                                  'imageCacheWidth'],
                                                              CatalogProductCardSize
                                                                  .gridImageCache(
                                                                size:
                                                                    productCardSize,
                                                                minimalLayout:
                                                                    true,
                                                                isWeb: kIsWeb,
                                                              ).width,
                                                            )
                                                          : CatalogProductCardSize
                                                              .gridImageCache(
                                                              size:
                                                                  productCardSize,
                                                              minimalLayout:
                                                                  false,
                                                              isWeb: kIsWeb,
                                                            ).width,
                                                  imageCacheHeight:
                                                      useMinimalLayout
                                                          ? safeInt(
                                                              minimalGridCfg[
                                                                  'imageCacheHeight'],
                                                              CatalogProductCardSize
                                                                  .gridImageCache(
                                                                size:
                                                                    productCardSize,
                                                                minimalLayout:
                                                                    true,
                                                                isWeb: kIsWeb,
                                                              ).height,
                                                            )
                                                          : CatalogProductCardSize
                                                              .gridImageCache(
                                                              size:
                                                                  productCardSize,
                                                              minimalLayout:
                                                                  false,
                                                              isWeb: kIsWeb,
                                                            ).height,
                                                  childAspectRatio: useMinimalLayout
                                                      ? _minimalCatalogGridAspectRatio(
                                                          isDesktopBody:
                                                              isDesktopBody,
                                                          baseFromSizeOrConfig:
                                                              safeDouble(
                                                            minimalGridCfg[
                                                                'aspectRatio'],
                                                            CatalogProductCardSize
                                                                .minimalAspectRatio(
                                                              productCardSize,
                                                            ),
                                                          ),
                                                        )
                                                      : _classicCatalogGridAspectRatio(
                                                          width: viewportW,
                                                          baseStandardAspectRatio:
                                                              CatalogProductCardSize
                                                                  .standardAspectRatio(
                                                            productCardSize,
                                                          ),
                                                        ),
                                                  mainAxisSpacing: useMinimalLayout
                                                      ? safeDouble(
                                                          minimalGridCfg[
                                                              'mainAxisSpacing'],
                                                          18)
                                                      : 16,
                                                  crossAxisSpacing: useMinimalLayout
                                                      ? safeDouble(
                                                          minimalGridCfg[
                                                              'crossAxisSpacing'],
                                                          12)
                                                      : 16,
                                                  padding: useMinimalLayout
                                                      ? const EdgeInsets
                                                          .fromLTRB(
                                                          12, 0, 12, 24)
                                                      : const EdgeInsets
                                                          .fromLTRB(
                                                          12, 0, 12, 24),
                                                  catalogShareUrl:
                                                      CatalogShareService
                                                          .buildUrlWithParams(
                                                    _publicCatalogShareBase(),
                                                    ref: widget.vendedorRef,
                                                    indicacao: widget
                                                        .indicacaoClienteRef,
                                                  ),
                                                  useMinimalLayout:
                                                      useMinimalLayout,
                                                  onMinimalSilentAddFeedback:
                                                      useMinimalLayout
                                                          ? _snackAdicionadoAoCarrinho
                                                          : null,
                                                  productCardSize:
                                                      productCardSize,
                                                ),
                                                // Paginação: Anterior | Página X de Y | Próxima (sempre visível)
                                                if (totalPaginas > 1)
                                                  SliverToBoxAdapter(
                                                    child: CatalogPaginacaoRow(
                                                      paginaAtual: paginaAtual,
                                                      totalPaginas:
                                                          totalPaginas,
                                                      primaryColor:
                                                          primaryColor,
                                                      cardColor: cardColor,
                                                      textColor: textColor,
                                                      onPagePrev: paginaAtual >
                                                              0
                                                          ? () =>
                                                              _currentPageNotifier
                                                                      .value =
                                                                  paginaAtual -
                                                                      1
                                                          : null,
                                                      onPageNext: paginaAtual <
                                                              totalPaginas - 1
                                                          ? () =>
                                                              _currentPageNotifier
                                                                      .value =
                                                                  paginaAtual +
                                                                      1
                                                          : null,
                                                    ),
                                                  ),
                                                if (exibindoTodosCatalogo &&
                                                    exibirAvaliacoesCatalogo)
                                                  SliverToBoxAdapter(
                                                    child:
                                                        CatalogAvaliacoesSection(
                                                      lojaId: lojaId,
                                                      cardColor: cardColor,
                                                      textColor: textColor,
                                                      accentColor: primaryColor,
                                                      ordem:
                                                          catalogAvaliacoesOrdem,
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
                                                  paymentCodes:
                                                      _paymentCodesParaPreviaRodape(
                                                          paymentCodes),
                                                  paymentAsset: paymentAssets,
                                                  badgeSSL: badgeSSL,
                                                  badgeGoogle: badgeGoogle,
                                                  empresaRazao: empresaRazao,
                                                  empresaCnpj: empresaCnpj,
                                                  onOpenUrl: _openUrl,
                                                  onSobreLojaTap: () {
                                                    final w = MediaQuery.sizeOf(
                                                            context)
                                                        .width;
                                                    final wide = w >= 900;
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute<void>(
                                                        builder: (ctx) =>
                                                            CatalogSobreLojaScreen(
                                                          lojaNome: lojaNome,
                                                          config:
                                                              sobreLojaConfig,
                                                          primaryColor:
                                                              primaryColor,
                                                          dicasColors:
                                                              catalogDicasColors,
                                                          logoUrl:
                                                              logoUrl.isNotEmpty
                                                                  ? logoUrl
                                                                  : null,
                                                          logoHeight:
                                                              wide ? 90 : 80,
                                                          bannerHeightHero:
                                                              mediaConfig
                                                                      .bannerH *
                                                                  0.52,
                                                          contactInfo:
                                                              DicasContactInfo(
                                                            whatsappNumber:
                                                                atendimentoWhatsapp,
                                                            instagramUrl:
                                                                instagramUrl
                                                                        .isNotEmpty
                                                                    ? instagramUrl
                                                                    : null,
                                                            facebookUrl: facebookUrl
                                                                    .isNotEmpty
                                                                ? facebookUrl
                                                                : null,
                                                          ),
                                                          empresaRazao:
                                                              empresaRazao,
                                                          empresaCnpj:
                                                              empresaCnpj,
                                                          onOpenUrl: _openUrl,
                                                        ),
                                                      ),
                                                    );
                                                  },
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
                                              SliverToBoxAdapter(
                                                child: CatalogCreatorCreditBar(
                                                  backgroundColor:
                                                      footerBgColor,
                                                  textColor: textColor,
                                                  accentColor: primaryColor,
                                                  onOpenUrl: _openUrl,
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
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 260,
                                                    maxWidth: 260,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: cardColor
                                                        .withOpacity(0.4),
                                                    border: Border(
                                                      right: BorderSide(
                                                        color: textColor
                                                            .withOpacity(0.12),
                                                        width: 1,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
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
                                                                .withOpacity(
                                                                    0.7),
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
                                                              _clearFiltrosVariacao();
                                                              _currentPageNotifier
                                                                  .value = 0;
                                                            });
                                                            _onCatalogCategoryOrSubChanged();
                                                          },
                                                          onCategorySelected:
                                                              (cat) {
                                                            setState(() {
                                                              _selectedCategory =
                                                                  cat;
                                                              _selectedSubcategory =
                                                                  null;
                                                              _clearFiltrosVariacao();
                                                              _currentPageNotifier
                                                                  .value = 0;
                                                            });
                                                            _onCatalogCategoryOrSubChanged();
                                                          },
                                                          onSubcategorySelectedNull:
                                                              () {
                                                            setState(() {
                                                              _selectedSubcategory =
                                                                  null;
                                                              _clearFiltrosVariacao();
                                                              _currentPageNotifier
                                                                  .value = 0;
                                                            });
                                                            _onCatalogCategoryOrSubChanged();
                                                          },
                                                          onSubcategorySelected:
                                                              (subcat) {
                                                            setState(() {
                                                              _selectedSubcategory =
                                                                  subcat;
                                                              _clearFiltrosVariacao();
                                                              _currentPageNotifier
                                                                  .value = 0;
                                                            });
                                                            _onCatalogCategoryOrSubChanged();
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
                                  color: primaryColor.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(28),
                                  child: InkWell(
                                    onTap: () =>
                                        _catalogScrollController.animateTo(
                                      0,
                                      duration:
                                          const Duration(milliseconds: 400),
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
        ),
      );
      if (kIsWeb) {
        plat.Web.localStorageSet(
            'mp_catalog_phase', 'publicCatalogScreen.render');
      }
      return rendered;
    } catch (e, st) {
      if (kIsWeb) {
        final uri = Uri.base;
        CatalogNormalTrace.setField(
            'fallback.reason', 'build_catch_${e.runtimeType}');
        CatalogNormalTrace.mark(
            'render.catalog.exception', <String, Object?>{'error': e.toString()});
        final payload = <String, dynamic>{
          'buildId': const String.fromEnvironment(
            'CATALOG_BUILD_ID',
            defaultValue: 'dev',
          ),
          'timestamp': DateTime.now().toIso8601String(),
          'host': uri.host,
          'path': uri.path,
          'query': uri.query,
          'userAgent': plat.Web.userAgent(),
          'slug': widget.lojaId,
          'lojaId': _resolvedLojaId ?? '',
          'fase': 'publicCatalogScreen.build.catch',
          'phase': plat.Web.localStorageGet('mp_catalog_phase') ??
              'publicCatalogScreen.build.start',
          'error': e.toString(),
          'stack': st.toString(),
          'appVersion': 'web',
          'resolvedLojaId': _resolvedLojaId,
          'fallbackReason': 'publicCatalogScreen.build.catch',
        };
        plat.Web.localStorageSet('mp_last_runtime_error', jsonEncode(payload));
        CatalogNormalTrace.setField('last_build_stack', st.toString());
        CatalogNormalTrace.setField('last_build_error', e.toString());
        CatalogNormalTrace.setField(
            'last_build_error_type', e.runtimeType.toString());
        CatalogNormalTrace.setField('mp_catalog_phase_at_catch',
            plat.Web.localStorageGet('mp_catalog_phase') ?? '');
        CatalogNormalTrace.persist();
      }
      final resolved = _resolvedLojaId;
      final hasResolved = resolved != null && resolved.isNotEmpty;
      if (hasResolved) {
        final parts = <String>[];
        final d = _catalogOpenFailureDetail?.trim();
        if (d != null && d.isNotEmpty) parts.add(d);
        parts.add('Falha ao montar a vitrine: $e');
        parts.add('error.runtimeType: ${e.runtimeType}');
        if (_catalogTechnicalDiagEnabled) parts.add(st.toString());
        _scheduleHtmlLoaderHandoff('catalog_error');
        return _wrapWithCatStartDiagOverlay(
          CatalogErrorLojaState(
            themeData: Theme.of(context),
            titleOverride: 'Não foi possível exibir o catálogo.',
            detailMessage: parts.join('\n\n'),
            showUrlHint: false,
            diagnosticText: _catalogTraceDiagnosticText(),
          ),
        );
      }
      if (!_catalogTechnicalDiagEnabled) {
        _scheduleHtmlLoaderHandoff('catalog_error');
        return _wrapWithCatStartDiagOverlay(
          CatalogErrorLojaState(
            themeData: Theme.of(context),
            detailMessage: _catalogOpenFailureDetail,
            diagnosticText: _catalogTraceDiagnosticText(),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnóstico Catálogo')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'error=${e.toString()}\n\nstack=${st.toString()}',
          ),
        ),
      );
    }
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
