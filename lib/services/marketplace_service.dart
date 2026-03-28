// lib/services/marketplace_service.dart

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serviço unificado para integração com marketplaces
/// Suporta: TikTok Shop, Mercado Livre, Shopee, Amazon, Magalu, etc.
class MarketplaceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Limite do Firestore para `whereIn` em `documentId`.
  static const int _whereInMax = 30;

  // URLs base das APIs
  static const String _tiktokShopBaseUrl = 'https://open-api.tiktokglobalshop.com';
  static const String _mercadoLivreBaseUrl = 'https://api.mercadolibre.com';
  static const String _shopeeBaseUrl = 'https://partner.shopeemobile.com';

  /// Timeout padrão para requisições (segundos)
  static const int _timeoutSegundos = 60;

  /// Links para documentação oficial
  static const Map<String, String> linksDocumentacao = {
    'tiktok': 'https://partner.tiktokshop.com/doc/page/262749',
    'mercadolivre': 'https://developers.mercadolivre.com.br/pt_br',
    'shopee': 'https://open.shopee.com/documents',
  };

  /// Lista de marketplaces suportados
  static const List<Map<String, dynamic>> marketplacesDisponiveis = [
    {'id': 'tiktok_shop', 'nome': 'TikTok Shop', 'icone': '🎵', 'cor': '#000000', 'ativo': true, 'automatico': true},
    {'id': 'mercado_livre', 'nome': 'Mercado Livre', 'icone': '🟡', 'cor': '#FFE600', 'ativo': true, 'automatico': true},
    {'id': 'shopee', 'nome': 'Shopee', 'icone': '🛍️', 'cor': '#EE4D2D', 'ativo': true, 'automatico': true},
    {'id': 'amazon', 'nome': 'Amazon', 'icone': '📦', 'cor': '#FF9900', 'ativo': false, 'automatico': false},
    {'id': 'magalu', 'nome': 'Magalu/Magazine Luiza', 'icone': '🔵', 'cor': '#0086FF', 'ativo': false, 'automatico': false},
    {'id': 'americanas', 'nome': 'Americanas', 'icone': '🔴', 'cor': '#E31F29', 'ativo': false, 'automatico': false},
  ];

  // ================================================================
  // 🔧 CONFIGURAÇÃO
  // ================================================================

  static Future<Map<String, dynamic>> buscarConfig(String lojaId) async {
    try {
      final doc = await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('marketplaces')
          .get();

      if (!doc.exists) return {};
      return doc.data() ?? {};
    } catch (e) {
      debugPrint('❌ [MARKETPLACE] Erro ao buscar config (type=${e.runtimeType})');
      return {};
    }
  }

  static Future<bool> salvarConfig(String lojaId, Map<String, dynamic> config) async {
    try {
      await _firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('marketplaces')
          .set(config, SetOptions(merge: true));
      debugPrint('✅ [MARKETPLACE] Config salva com sucesso');
      return true;
    } catch (e) {
      debugPrint('❌ [MARKETPLACE] Erro ao salvar config (type=${e.runtimeType})');
      return false;
    }
  }

  /// Traduz erros comuns para mensagens amigáveis
  static String _mensagemErroAmigavel(dynamic e, [int? statusCode]) {
    final msg = e.toString().toLowerCase();
    if (statusCode == 401) return 'Token expirado ou inválido. Gere um novo token no painel do marketplace.';
    if (statusCode == 403) return 'Acesso negado. Verifique se as permissões do app estão corretas.';
    if (statusCode == 404) return 'Recurso não encontrado. Verifique a URL ou o ID.';
    if (statusCode != null && statusCode >= 500) return 'Servidor do marketplace temporariamente indisponível. Tente novamente em alguns minutos.';
    if (msg.contains('timeout') || msg.contains('timed out')) return 'Tempo esgotado. Verifique sua conexão e tente novamente.';
    if (msg.contains('connection') || msg.contains('socket')) return 'Erro de conexão. Verifique sua internet.';
    if (msg.contains('invalid') && msg.contains('token')) return 'Token inválido. Gere um novo no painel do marketplace.';
    return e.toString();
  }

  /// Executa requisição com retry (1 tentativa extra em caso de 5xx ou timeout)
  static Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        final response = await request().timeout(const Duration(seconds: _timeoutSegundos));
        if (i < maxRetries - 1 && response.statusCode >= 500) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return response;
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw Exception('Falha após $maxRetries tentativas');
  }

  // ================================================================
  // 🧪 TESTAR CONEXÃO
  // ================================================================

  /// Testa conexão com TikTok Shop
  static Future<Map<String, dynamic>> testarConexaoTikTok({
    required String appKey,
    required String appSecret,
    required String accessToken,
    required String shopId,
  }) async {
    try {
      const path = '/api/shop/get_authorized_shop';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sign = _gerarAssinaturaTikTok(appSecret, path, timestamp, {});

      final uri = Uri.parse('$_tiktokShopBaseUrl$path').replace(
        queryParameters: {
          'app_key': appKey,
          'timestamp': timestamp.toString(),
          'sign': sign,
          'access_token': accessToken,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) return {'success': true, 'message': 'Conexão OK'};
        return {'success': false, 'error': data['message'] ?? 'Erro na API'};
      }
      return {'success': false, 'error': _mensagemErroAmigavel(response.body, response.statusCode)};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  /// Testa conexão com Mercado Livre
  static Future<Map<String, dynamic>> testarConexaoMercadoLivre({
    required String accessToken,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_mercadoLivreBaseUrl/users/me'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'message': 'Conectado como ${data['nickname'] ?? 'vendedor'}'};
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'Token expirado. Use o Refresh Token para renovar ou gere um novo.'};
      }
      return {'success': false, 'error': _mensagemErroAmigavel(response.body, response.statusCode)};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  /// Testa conexão com Shopee
  static Future<Map<String, dynamic>> testarConexaoShopee({
    required String partnerId,
    required String partnerKey,
    required String shopId,
    required String accessToken,
  }) async {
    try {
      const path = '/api/v2/shop/get_shop_info';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign = _gerarAssinaturaShopee(partnerId, path, timestamp, accessToken, shopId, partnerKey);

      final uri = Uri.parse('$_shopeeBaseUrl$path').replace(
        queryParameters: {
          'partner_id': partnerId,
          'timestamp': timestamp.toString(),
          'sign': sign,
          'shop_id': shopId,
          'access_token': accessToken,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error'] == null || data['error'] == '') {
          return {'success': true, 'message': 'Conexão OK'};
        }
        return {'success': false, 'error': data['message'] ?? data['error'] ?? 'Erro na API'};
      }
      return {'success': false, 'error': _mensagemErroAmigavel(response.body, response.statusCode)};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  // ================================================================
  // 🔄 RENOVAÇÃO TOKEN MERCADO LIVRE
  // ================================================================

  /// Renova Access Token do Mercado Livre usando Refresh Token
  static Future<Map<String, dynamic>> renovarTokenMercadoLivre({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_mercadoLivreBaseUrl/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'client_secret': clientSecret,
          'refresh_token': refreshToken,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'access_token': data['access_token'],
          'refresh_token': data['refresh_token'] ?? refreshToken,
          'expires_in': data['expires_in'],
        };
      }
      final err = jsonDecode(response.body);
      return {
        'success': false,
        'error': err['message'] ?? 'Falha ao renovar token. Verifique Client ID, Secret e Refresh Token.',
      };
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  /// Obtém Access Token válido (renova se necessário)
  static Future<String?> _obterAccessTokenML(String lojaId) async {
    final config = await buscarConfig(lojaId);
    final ml = config['mercado_livre'] as Map<String, dynamic>? ?? {};

    var accessToken = (ml['access_token'] ?? '').toString();
    final refreshToken = (ml['refresh_token'] ?? '').toString();
    final clientId = (ml['client_id'] ?? '').toString();
    final clientSecret = (ml['client_secret'] ?? '').toString();

    if (accessToken.isEmpty) return null;

    // Testar token atual
    final teste = await testarConexaoMercadoLivre(accessToken: accessToken);
    if (teste['success'] == true) return accessToken;

    // Tentar renovar
    if (refreshToken.isEmpty || clientId.isEmpty || clientSecret.isEmpty) return accessToken;

    final renovado = await renovarTokenMercadoLivre(
      clientId: clientId,
      clientSecret: clientSecret,
      refreshToken: refreshToken,
    );

    if (renovado['success'] == true && renovado['access_token'] != null) {
      accessToken = renovado['access_token'] as String;
      final novaConfig = Map<String, dynamic>.from(config);
      final mlAtualizado = Map<String, dynamic>.from(ml);
      mlAtualizado['access_token'] = accessToken;
      if (renovado['refresh_token'] != null) {
        mlAtualizado['refresh_token'] = renovado['refresh_token'];
      }
      novaConfig['mercado_livre'] = mlAtualizado;
      await salvarConfig(lojaId, novaConfig);
      return accessToken;
    }

    return accessToken;
  }

  // ================================================================
  // 🎵 TIKTOK SHOP - Assinatura HMAC-SHA256
  // ================================================================

  /// Gera assinatura HMAC-SHA256 para TikTok Shop API
  static String _gerarAssinaturaTikTok(String appSecret, String path, int timestamp, Map<String, dynamic> body) {
    final bodyStr = body.isEmpty ? '' : jsonEncode(body);
    final signStr = '$appSecret$path$timestamp$bodyStr';
    final key = utf8.encode(appSecret);
    final bytes = utf8.encode(signStr);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    final base64 = base64Encode(digest.bytes);
    return base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  static Future<Map<String, dynamic>> sincronizarProdutosTikTok({
    required String lojaId,
    List<String>? produtoIds,
  }) async {
    try {
      debugPrint('🎵 [TIKTOK] Iniciando sincronização...');

      final config = await buscarConfig(lojaId);
      final tiktokConfig = config['tiktok_shop'] as Map<String, dynamic>? ?? {};

      final appKey = (tiktokConfig['app_key'] ?? '').toString();
      final appSecret = (tiktokConfig['app_secret'] ?? '').toString();
      final accessToken = (tiktokConfig['access_token'] ?? '').toString();
      final shopId = (tiktokConfig['shop_id'] ?? '').toString();

      if (appKey.isEmpty || appSecret.isEmpty || accessToken.isEmpty) {
        return {'success': false, 'error': 'Credenciais TikTok Shop não configuradas'};
      }

      if (produtoIds != null && produtoIds.isEmpty) {
        return {
          'success': true,
          'sincronizados': 0,
          'erros': 0,
          'total': 0,
          'resultados': <Map<String, dynamic>>[],
        };
      }

      int sincronizados = 0;
      int erros = 0;
      List<Map<String, dynamic>> resultados = [];
      var total = 0;

      Future<void> processarChunk(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
        for (var doc in docs) {
          try {
            final produto = doc.data();
            final produtoId = doc.id;
            final tiktokId = produto['tiktok_product_id'] as String?;

            Map<String, dynamic> resultado;
            if (tiktokId != null && tiktokId.isNotEmpty) {
              resultado = await _atualizarProdutoTikTok(
                appKey: appKey,
                appSecret: appSecret,
                accessToken: accessToken,
                shopId: shopId,
                tiktokProductId: tiktokId,
                produto: produto,
              );
            } else {
              resultado = await _criarProdutoTikTok(
                appKey: appKey,
                appSecret: appSecret,
                accessToken: accessToken,
                shopId: shopId,
                produto: produto,
              );
              if (resultado['success'] == true && resultado['product_id'] != null) {
                await doc.reference.update({
                  'tiktok_product_id': resultado['product_id'],
                  'tiktok_synced_at': FieldValue.serverTimestamp(),
                });
              }
            }

            if (resultado['success'] == true) {
              sincronizados++;
            } else {
              erros++;
            }
            resultados.add({'produto_id': produtoId, 'nome': produto['nome'] ?? 'Sem nome', ...resultado});
          } catch (e) {
            debugPrint('❌ [TIKTOK] Erro produto ${doc.id} (type=${e.runtimeType})');
            erros++;
            resultados.add({'produto_id': doc.id, 'success': false, 'error': e.toString()});
          }
        }
      }

      if (produtoIds != null && produtoIds.isNotEmpty) {
        for (var i = 0; i < produtoIds.length; i += _whereInMax) {
          final end = (i + _whereInMax < produtoIds.length) ? i + _whereInMax : produtoIds.length;
          final chunk = produtoIds.sublist(i, end);
          final snap = await _firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('produtos')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          total += snap.docs.length;
          await processarChunk(snap.docs);
        }
      } else {
        final snap = await _firestore.collection('lojas').doc(lojaId).collection('produtos').get();
        total = snap.docs.length;
        await processarChunk(snap.docs);
      }

      return {
        'success': true,
        'sincronizados': sincronizados,
        'erros': erros,
        'total': total,
        'resultados': resultados,
      };
    } catch (e) {
      debugPrint('❌ [TIKTOK] Erro geral (type=${e.runtimeType})');
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _criarProdutoTikTok({
    required String appKey,
    required String appSecret,
    required String accessToken,
    required String shopId,
    required Map<String, dynamic> produto,
  }) async {
    try {
      const path = '/api/products/create';
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final productData = {
        'title': produto['nome'] ?? 'Produto',
        'description': produto['descricao'] ?? '',
        'category_id': produto['tiktok_category_id'] ?? '1',
        'brand_id': produto['tiktok_brand_id'] ?? '',
        'main_images': [{'url': produto['imagem'] ?? ''}],
        'skus': [
          {
            'price': {'amount': ((produto['preco'] as num?)?.toDouble() ?? 0) * 100, 'currency': 'BRL'},
            'stock_infos': [
              {'available_stock': (produto['estoque'] as int?) ?? 0, 'warehouse_id': shopId}
            ],
            'seller_sku': produto['sku'] ?? produto['id'] ?? '',
          }
        ],
        'package_dimensions': {
          'length': (produto['comprimento'] as num?)?.toInt() ?? 10,
          'width': (produto['largura'] as num?)?.toInt() ?? 10,
          'height': (produto['altura'] as num?)?.toInt() ?? 10,
          'unit': 'CENTIMETER',
        },
        'package_weight': {'value': ((produto['peso'] as num?)?.toDouble() ?? 100) / 1000, 'unit': 'KILOGRAM'},
      };

      final bodyStr = jsonEncode(productData);
      final sign = _gerarAssinaturaTikTok(appSecret, path, timestamp, productData);

      final response = await _requestWithRetry(() => http.post(
            Uri.parse('$_tiktokShopBaseUrl$path').replace(
              queryParameters: {
                'app_key': appKey,
                'timestamp': timestamp.toString(),
                'sign': sign,
                'access_token': accessToken,
              },
            ),
            headers: {'Content-Type': 'application/json'},
            body: bodyStr,
          ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          return {'success': true, 'product_id': data['data']['product_id'], 'message': 'Produto criado no TikTok Shop'};
        }
        return {'success': false, 'error': data['message'] ?? 'Erro desconhecido'};
      }
      return {'success': false, 'error': _mensagemErroAmigavel(response.body, response.statusCode)};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _atualizarProdutoTikTok({
    required String appKey,
    required String appSecret,
    required String accessToken,
    required String shopId,
    required String tiktokProductId,
    required Map<String, dynamic> produto,
  }) async {
    try {
      const path = '/api/products/update';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final productData = {
        'product_id': tiktokProductId,
        'title': produto['nome'] ?? 'Produto',
        'description': produto['descricao'] ?? '',
      };
      final bodyStr = jsonEncode(productData);
      final sign = _gerarAssinaturaTikTok(appSecret, path, timestamp, productData);

      final response = await _requestWithRetry(() => http.post(
            Uri.parse('$_tiktokShopBaseUrl$path').replace(
              queryParameters: {
                'app_key': appKey,
                'timestamp': timestamp.toString(),
                'sign': sign,
                'access_token': accessToken,
              },
            ),
            headers: {'Content-Type': 'application/json'},
            body: bodyStr,
          ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) return {'success': true, 'message': 'Produto atualizado no TikTok Shop'};
        return {'success': false, 'error': data['message'] ?? 'Erro desconhecido'};
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  // ================================================================
  // 🟡 MERCADO LIVRE
  // ================================================================

  static Future<Map<String, dynamic>> sincronizarProdutosMercadoLivre({
    required String lojaId,
    List<String>? produtoIds,
  }) async {
    try {
      debugPrint('🟡 [ML] Iniciando sincronização...');

      final accessToken = await _obterAccessTokenML(lojaId);
      if (accessToken == null || accessToken.isEmpty) {
        return {'success': false, 'error': 'Access Token não configurado ou expirado. Configure Client ID, Secret e Refresh Token para renovação automática.'};
      }

      if (produtoIds != null && produtoIds.isEmpty) {
        return {'success': true, 'sincronizados': 0, 'erros': 0, 'total': 0};
      }

      int sincronizados = 0;
      int erros = 0;
      var total = 0;

      Future<void> processarChunk(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
        for (var doc in docs) {
          try {
            final produto = doc.data();
            final mlId = produto['mercadolivre_id'] as String?;

            Map<String, dynamic> resultado;
            if (mlId != null && mlId.isNotEmpty) {
              resultado = await _atualizarProdutoMercadoLivre(accessToken: accessToken, mlId: mlId, produto: produto);
            } else {
              resultado = await _criarProdutoMercadoLivre(accessToken: accessToken, produto: produto);
              if (resultado['success'] == true && resultado['id'] != null) {
                await doc.reference.update({
                  'mercadolivre_id': resultado['id'],
                  'mercadolivre_permalink': resultado['permalink'],
                  'mercadolivre_synced_at': FieldValue.serverTimestamp(),
                });
              }
            }
            if (resultado['success'] == true) {
              sincronizados++;
            } else {
              erros++;
            }
          } catch (e) {
            debugPrint('❌ [ML] Erro produto ${doc.id} (type=${e.runtimeType})');
            erros++;
          }
        }
      }

      if (produtoIds != null && produtoIds.isNotEmpty) {
        for (var i = 0; i < produtoIds.length; i += _whereInMax) {
          final end = (i + _whereInMax < produtoIds.length) ? i + _whereInMax : produtoIds.length;
          final chunk = produtoIds.sublist(i, end);
          final snap = await _firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('produtos')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          total += snap.docs.length;
          await processarChunk(snap.docs);
        }
      } else {
        final snap = await _firestore.collection('lojas').doc(lojaId).collection('produtos').get();
        total = snap.docs.length;
        await processarChunk(snap.docs);
      }

      return {'success': true, 'sincronizados': sincronizados, 'erros': erros, 'total': total};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _criarProdutoMercadoLivre({
    required String accessToken,
    required Map<String, dynamic> produto,
  }) async {
    try {
      final productData = {
        'title': produto['nome'] ?? 'Produto',
        'category_id': produto['ml_category_id'] ?? 'MLB1051',
        'price': (produto['preco'] as num?)?.toDouble() ?? 0,
        'currency_id': 'BRL',
        'available_quantity': (produto['estoque'] as int?) ?? 0,
        'buying_mode': 'buy_it_now',
        'listing_type_id': 'gold_special',
        'condition': 'new',
        'description': {'plain_text': produto['descricao'] ?? ''},
        'pictures': [{'source': produto['imagem'] ?? ''}],
      };

      final response = await _requestWithRetry(() => http.post(
            Uri.parse('$_mercadoLivreBaseUrl/items'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
            body: jsonEncode(productData),
          ));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'id': data['id'], 'permalink': data['permalink'], 'message': 'Produto criado no Mercado Livre'};
      }
      final error = jsonDecode(response.body);
      return {'success': false, 'error': error['message'] ?? _mensagemErroAmigavel(response.body, response.statusCode)};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _atualizarProdutoMercadoLivre({
    required String accessToken,
    required String mlId,
    required Map<String, dynamic> produto,
  }) async {
    try {
      final updateData = {
        'price': (produto['preco'] as num?)?.toDouble() ?? 0,
        'available_quantity': (produto['estoque'] as int?) ?? 0,
        'title': produto['nome'] ?? 'Produto',
      };

      final response = await _requestWithRetry(() => http.put(
            Uri.parse('$_mercadoLivreBaseUrl/items/$mlId'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
            body: jsonEncode(updateData),
          ));

      if (response.statusCode == 200) return {'success': true, 'message': 'Produto atualizado no Mercado Livre'};
      return {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  // ================================================================
  // 🛍️ SHOPEE - HMAC-SHA256 + Sincronização real
  // ================================================================

  /// Gera assinatura HMAC-SHA256 para Shopee API
  static String _gerarAssinaturaShopee(String partnerId, String path, int timestamp, String accessToken, String shopId, String partnerKey) {
    final baseStr = '$partnerId$path$timestamp$accessToken$shopId';
    final key = utf8.encode(partnerKey);
    final bytes = utf8.encode(baseStr);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  static Future<Map<String, dynamic>> sincronizarProdutosShopee({
    required String lojaId,
    List<String>? produtoIds,
  }) async {
    try {
      debugPrint('🛍️ [SHOPEE] Iniciando sincronização...');

      final config = await buscarConfig(lojaId);
      final shopeeConfig = config['shopee'] as Map<String, dynamic>? ?? {};

      final partnerId = (shopeeConfig['partner_id'] ?? '').toString();
      final partnerKey = (shopeeConfig['partner_key'] ?? '').toString();
      final shopId = (shopeeConfig['shop_id'] ?? '').toString();
      final accessToken = (shopeeConfig['access_token'] ?? '').toString();

      if (partnerId.isEmpty || partnerKey.isEmpty || accessToken.isEmpty || shopId.isEmpty) {
        return {'success': false, 'error': 'Credenciais Shopee incompletas. Preencha Partner ID, Partner Key, Shop ID e Access Token.'};
      }

      if (produtoIds != null && produtoIds.isEmpty) {
        return {'success': true, 'sincronizados': 0, 'erros': 0, 'total': 0};
      }

      int sincronizados = 0;
      int erros = 0;
      var total = 0;

      Future<void> processarChunk(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
        for (var doc in docs) {
          try {
            final produto = doc.data();
            final shopeeItemId = produto['shopee_item_id'] as String?;

            Map<String, dynamic> resultado;
            if (shopeeItemId != null && shopeeItemId.isNotEmpty) {
              resultado = await _atualizarProdutoShopee(
                partnerId: partnerId,
                partnerKey: partnerKey,
                shopId: shopId,
                accessToken: accessToken,
                itemId: shopeeItemId,
                produto: produto,
              );
            } else {
              resultado = await _criarProdutoShopee(
                partnerId: partnerId,
                partnerKey: partnerKey,
                shopId: shopId,
                accessToken: accessToken,
                produto: produto,
              );
              if (resultado['success'] == true && resultado['item_id'] != null) {
                await doc.reference.update({
                  'shopee_item_id': resultado['item_id'].toString(),
                  'shopee_synced_at': FieldValue.serverTimestamp(),
                });
              }
            }
            if (resultado['success'] == true) {
              sincronizados++;
            } else {
              erros++;
            }
          } catch (e) {
            debugPrint('❌ [SHOPEE] Erro produto ${doc.id} (type=${e.runtimeType})');
            erros++;
          }
        }
      }

      if (produtoIds != null && produtoIds.isNotEmpty) {
        for (var i = 0; i < produtoIds.length; i += _whereInMax) {
          final end = (i + _whereInMax < produtoIds.length) ? i + _whereInMax : produtoIds.length;
          final chunk = produtoIds.sublist(i, end);
          final snap = await _firestore
              .collection('lojas')
              .doc(lojaId)
              .collection('produtos')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          total += snap.docs.length;
          await processarChunk(snap.docs);
        }
      } else {
        final snap = await _firestore.collection('lojas').doc(lojaId).collection('produtos').get();
        total = snap.docs.length;
        await processarChunk(snap.docs);
      }

      return {'success': true, 'sincronizados': sincronizados, 'erros': erros, 'total': total};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _criarProdutoShopee({
    required String partnerId,
    required String partnerKey,
    required String shopId,
    required String accessToken,
    required Map<String, dynamic> produto,
  }) async {
    try {
      const path = '/api/v2/product/add_item';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final itemData = {
        'name': produto['nome'] ?? 'Produto',
        'description': produto['descricao'] ?? '',
        'category_id': (produto['shopee_category_id'] as int?) ?? 100015,
        'brand': {'brand_id': 0, 'original_brand_name': 'Marca'},
        'price': (produto['preco'] as num?)?.toDouble() ?? 0,
        'stock': (produto['estoque'] as int?) ?? 0,
        'item_sku': produto['sku'] ?? produto['id'] ?? '',
        'images': [
          {'url': produto['imagem'] ?? ''}
        ],
        'weight': ((produto['peso'] as num?)?.toDouble() ?? 0.1) * 1000,
        'dimension': {
          'length': (produto['comprimento'] as num?)?.toDouble() ?? 10,
          'width': (produto['largura'] as num?)?.toDouble() ?? 10,
          'height': (produto['altura'] as num?)?.toDouble() ?? 10,
        },
      };

      final sign = _gerarAssinaturaShopee(partnerId, path, timestamp, accessToken, shopId, partnerKey);

      final body = {
        'partner_id': int.tryParse(partnerId) ?? 0,
        'timestamp': timestamp,
        'sign': sign,
        'shop_id': int.tryParse(shopId) ?? 0,
        ...itemData,
      };

      final response = await _requestWithRetry(() => http.post(
            Uri.parse('$_shopeeBaseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error'] == null || data['error'] == '') {
          final itemId = data['response']?['item_id'] ?? data['item_id'];
          return {'success': true, 'item_id': itemId, 'message': 'Produto criado na Shopee'};
        }
        return {'success': false, 'error': data['message'] ?? data['error'] ?? 'Erro na API Shopee'};
      }
      return {'success': false, 'error': _mensagemErroAmigavel(response.body, response.statusCode)};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _atualizarProdutoShopee({
    required String partnerId,
    required String partnerKey,
    required String shopId,
    required String accessToken,
    required String itemId,
    required Map<String, dynamic> produto,
  }) async {
    try {
      const path = '/api/v2/product/update_item';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign = _gerarAssinaturaShopee(partnerId, path, timestamp, accessToken, shopId, partnerKey);

      final body = {
        'partner_id': int.tryParse(partnerId) ?? 0,
        'timestamp': timestamp,
        'sign': sign,
        'shop_id': int.tryParse(shopId) ?? 0,
        'item_id': int.tryParse(itemId) ?? 0,
        'price': (produto['preco'] as num?)?.toDouble() ?? 0,
        'stock': (produto['estoque'] as int?) ?? 0,
        'name': produto['nome'] ?? 'Produto',
      };

      final response = await _requestWithRetry(() => http.post(
            Uri.parse('$_shopeeBaseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          ));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error'] == null || data['error'] == '') {
          return {'success': true, 'message': 'Produto atualizado na Shopee'};
        }
        return {'success': false, 'error': data['message'] ?? data['error'] ?? 'Erro na API Shopee'};
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  // ================================================================
  // 📦 ESTOQUE GLOBAL
  // ================================================================

  static Future<Map<String, dynamic>> atualizarEstoqueGlobal({
    required String lojaId,
    required String produtoId,
    required int novoEstoque,
  }) async {
    try {
      final config = await buscarConfig(lojaId);
      final resultados = <String, dynamic>{};

      final produtoDoc = await _firestore.collection('lojas').doc(lojaId).collection('produtos').doc(produtoId).get();
      if (!produtoDoc.exists) return {'success': false, 'error': 'Produto não encontrado'};
      final produto = {...?produtoDoc.data(), 'estoque': novoEstoque};

      final tiktok = config['tiktok_shop'] as Map<String, dynamic>?;
      if (tiktok != null && tiktok['ativo'] == true) {
        final tiktokId = produto['tiktok_product_id'] as String?;
        if (tiktokId != null && tiktokId.isNotEmpty) {
          final r = await _atualizarEstoqueTikTok(
            appKey: (tiktok['app_key'] ?? '').toString(),
            appSecret: (tiktok['app_secret'] ?? '').toString(),
            accessToken: (tiktok['access_token'] ?? '').toString(),
            shopId: (tiktok['shop_id'] ?? '').toString(),
            tiktokProductId: tiktokId,
            estoque: novoEstoque,
          );
          resultados['tiktok'] = r;
        }
      }

      final ml = config['mercado_livre'] as Map<String, dynamic>?;
      if (ml != null && ml['ativo'] == true) {
        final accessToken = await _obterAccessTokenML(lojaId);
        final mlId = produto['mercadolivre_id'] as String?;
        if (accessToken != null && mlId != null && mlId.isNotEmpty) {
          final r = await _atualizarEstoqueMercadoLivre(accessToken: accessToken, mlId: mlId, estoque: novoEstoque);
          resultados['mercadolivre'] = r;
        }
      }

      final shopee = config['shopee'] as Map<String, dynamic>?;
      if (shopee != null && shopee['ativo'] == true) {
        final shopeeId = produto['shopee_item_id'] as String?;
        if (shopeeId != null && shopeeId.isNotEmpty) {
          final r = await _atualizarEstoqueShopee(
            partnerId: (shopee['partner_id'] ?? '').toString(),
            partnerKey: (shopee['partner_key'] ?? '').toString(),
            shopId: (shopee['shop_id'] ?? '').toString(),
            accessToken: (shopee['access_token'] ?? '').toString(),
            itemId: shopeeId,
            estoque: novoEstoque,
          );
          resultados['shopee'] = r;
        }
      }

      return {'success': true, 'resultados': resultados};
    } catch (e) {
      return {'success': false, 'error': _mensagemErroAmigavel(e)};
    }
  }

  static Future<Map<String, dynamic>> _atualizarEstoqueTikTok({
    required String appKey,
    required String appSecret,
    required String accessToken,
    required String shopId,
    required String tiktokProductId,
    required int estoque,
  }) async {
    try {
      const path = '/api/products/stocks/update';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final body = {'product_id': tiktokProductId, 'skus': [{'seller_sku': '', 'available_stock': estoque}]};
      final sign = _gerarAssinaturaTikTok(appSecret, path, timestamp, body);

      final response = await http.post(
        Uri.parse('$_tiktokShopBaseUrl$path').replace(
          queryParameters: {'app_key': appKey, 'timestamp': timestamp.toString(), 'sign': sign, 'access_token': accessToken},
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['code'] == 0 ? {'success': true} : {'success': false, 'error': data['message']};
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _atualizarEstoqueMercadoLivre({
    required String accessToken,
    required String mlId,
    required int estoque,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$_mercadoLivreBaseUrl/items/$mlId'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
        body: jsonEncode({'available_quantity': estoque}),
      ).timeout(const Duration(seconds: 15));

      return response.statusCode == 200 ? {'success': true} : {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _atualizarEstoqueShopee({
    required String partnerId,
    required String partnerKey,
    required String shopId,
    required String accessToken,
    required String itemId,
    required int estoque,
  }) async {
    try {
      const path = '/api/v2/product/update_stock';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sign = _gerarAssinaturaShopee(partnerId, path, timestamp, accessToken, shopId, partnerKey);

      final body = {
        'partner_id': int.tryParse(partnerId) ?? 0,
        'timestamp': timestamp,
        'sign': sign,
        'shop_id': int.tryParse(shopId) ?? 0,
        'item_id': int.tryParse(itemId) ?? 0,
        'stock': estoque,
      };

      final response = await http.post(
        Uri.parse('$_shopeeBaseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['error'] == null || data['error'] == '') ? {'success': true} : {'success': false, 'error': data['message']};
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
