// lib/app_routes.dart
// Rotas geradas dinamicamente (deep links, /loja/{id}, retorno MP, /pedido/).
// Reduz tamanho de main.dart; mapa de rotas nomeadas permanece em main.dart.

import 'package:flutter/material.dart';

import 'core/logger.dart';
import 'screens/public_catalog_screen.dart';
import 'screens/public_catalog/catalog_url_query_codec.dart';
import 'screens/pagamento_resultado_screen.dart';
import 'screens/pedido_publico_screen.dart';
import 'screens/order_review_screen.dart';

/// Rotas dinâmicas: /loja/{id}, /sucesso, /falha, /pagamento/*, /pedido/{orderId}.
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final uri = Uri.parse(settings.name ?? '');

  // ROTA /loja/{id} com suporte a ?ref=vendedorId
  if (settings.name?.startsWith('/loja/') ?? false) {
    final pathParts = uri.pathSegments;
    if (pathParts.length >= 2) {
      // ✅ NUNCA usar 'masterpalm' como fallback: passaria loja errada.
      // Se raw for vazio ou placeholder, passar como está; o catálogo mostrará "Loja não encontrada".
      final raw = pathParts[1].trim();
      final lojaId = raw.isEmpty ? 'minha-loja' : raw;
      final vendedorRef = uri.queryParameters['ref'] ??
          uri.queryParameters['vendedor'] ??
          uri.queryParameters['seller'];
      final tam = uri.queryParameters['tam']?.trim();
      final cor = uri.queryParameters['cor']?.trim();
      final cat = uri.queryParameters['cat']?.trim();
      final sub = uri.queryParameters['sub']?.trim();
      final ord = uri.queryParameters['ord']?.trim();
      final pmin = uri.queryParameters['pmin']?.trim();
      final pmax = uri.queryParameters['pmax']?.trim();
      final searchQ = uri.queryParameters['q']?.trim();
      final pageSplit =
          catalogInterpretPageQueryParam(uri.queryParameters['page']?.trim());
      final produtoDeep = uri.queryParameters['produto']?.trim();
      final prodDeep =
          catalogSanitizeProdQuery(uri.queryParameters['prod']);

      logD('🛒 [ROUTE /loja/{id}] rota resolvida');

      return MaterialPageRoute(
        settings: settings,
        builder: (_) => PublicCatalogScreen(
          lojaId: lojaId,
          vendedorRef: vendedorRef,
          initialTam: (tam != null && tam.isNotEmpty) ? tam : null,
          initialCor: (cor != null && cor.isNotEmpty) ? cor : null,
          initialCat: (cat != null && cat.isNotEmpty) ? cat : null,
          initialSub: (sub != null && sub.isNotEmpty) ? sub : null,
          initialOrd: (ord != null && ord.isNotEmpty) ? ord : null,
          initialPmin: (pmin != null && pmin.isNotEmpty) ? pmin : null,
          initialPmax: (pmax != null && pmax.isNotEmpty) ? pmax : null,
          initialQ: (searchQ != null && searchQ.isNotEmpty) ? searchQ : null,
          initialPage: pageSplit.namedInitialPage,
          initialCatalogPage: pageSplit.catalogPage1Based,
          initialProdutoId:
              (produtoDeep != null && produtoDeep.isNotEmpty) ? produtoDeep : null,
          initialProd: prodDeep,
        ),
      );
    }
  }

  // Rotas de retorno do Mercado Pago (/sucesso, /pagamento/sucesso, etc)
  if (settings.name == '/sucesso' ||
      (settings.name?.startsWith('/pagamento/sucesso') ?? false) ||
      (settings.name?.startsWith('/checkout/success') ?? false)) {
    final loja = uri.queryParameters['loja'] ?? '';
    final plano = uri.queryParameters['plano'] ?? '';
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => PagamentoResultadoScreen(
        status: 'sucesso',
        orderId: uri.queryParameters['id'],
        lojaId: loja.isNotEmpty ? loja : null,
        planoId: plano.isNotEmpty ? plano : null,
        collectionStatus: uri.queryParameters['collection_status'],
        paymentStatusQuery: uri.queryParameters['status'],
        externalReference: uri.queryParameters['external_reference'] ??
            uri.queryParameters['preference_id'],
      ),
    );
  }
  if (settings.name == '/falha' ||
      settings.name?.startsWith('/pagamento/falha') == true ||
      (settings.name?.startsWith('/checkout/failure') ?? false)) {
    final loja = uri.queryParameters['loja'] ?? '';
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => PagamentoResultadoScreen(
        status: 'falha',
        orderId: uri.queryParameters['id'],
        lojaId: loja.isNotEmpty ? loja : null,
        planoId: uri.queryParameters['plano'],
        collectionStatus: uri.queryParameters['collection_status'],
        paymentStatusQuery: uri.queryParameters['status'],
        externalReference: uri.queryParameters['external_reference'] ??
            uri.queryParameters['preference_id'],
      ),
    );
  }
  if (settings.name?.startsWith('/pagamento/pendente') == true ||
      (settings.name?.startsWith('/checkout/pending') ?? false)) {
    final loja = uri.queryParameters['loja'] ?? '';
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => PagamentoResultadoScreen(
        status: 'pendente',
        orderId: uri.queryParameters['id'],
        lojaId: loja.isNotEmpty ? loja : null,
        planoId: uri.queryParameters['plano'],
        collectionStatus: uri.queryParameters['collection_status'],
        paymentStatusQuery: uri.queryParameters['status'],
        externalReference: uri.queryParameters['external_reference'] ??
            uri.queryParameters['preference_id'],
      ),
    );
  }

  // /pedido/{orderId} — pré-pedido (com lojaId) ou temp order (OrderReview)
  if (settings.name?.startsWith('/pedido/') ?? false) {
    final orderId =
        settings.name!.split('/pedido/').last.split('?').first;

    String lojaId = uri.queryParameters['loja'] ?? '';

    if (lojaId.isEmpty) {
      final args = (settings.arguments is Map)
          ? settings.arguments as Map
          : const {};
      lojaId = (args['lojaId'] ?? args['loja'] ?? '').toString();
    }

    if (lojaId.isNotEmpty) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => PedidoPublicoScreen(
          lojaId: lojaId,
          prePedidoId: orderId,
        ),
      );
    }
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => OrderReviewScreen(
        orderId: orderId,
        lojaId: null,
      ),
    );
  }

  return null;
}
