// lib/services/superfrete_service.dart
// Integração com a API da SuperFrete

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SuperFreteService {
  /// API única: api.superfrete.com para AMBOS os ambientes.
  /// sandbox.superfrete.com retorna HTML (SPA), não JSON. O token define sandbox vs produção.
  static const String _baseUrl = 'https://api.superfrete.com';

  static String _baseUrlFor(bool useSandbox) => _baseUrl;

  /// Calcula frete usando a API da SuperFrete
  /// [useSandbox]: true = token do Sandbox (sandbox.superfrete.com), false = Produção
  static Future<Map<String, dynamic>> calcularFrete({
    required String token,
    required String cepOrigem,
    required String cepDestino,
    required double peso, // em gramas
    required double altura, // em cm
    required double largura, // em cm
    required double comprimento, // em cm
    required double valorDeclarado,
    bool useSandbox = false,
  }) async {
    try {
      final base = _baseUrlFor(useSandbox);
      final url = Uri.parse('$base/api/v8/calculator');

      debugPrint('━━━ [SuperFrete] DIAG INÍCIO ━━━');
      debugPrint('[SuperFrete] Ambiente: ${useSandbox • "SANDBOX" : "PRODUÇÃO"}');
      debugPrint('[SuperFrete] URL completa: $url');
      debugPrint('[SuperFrete] Base: $base');
      debugPrint('[SuperFrete] Token: ${token.length} chars, prefixo: ${token.length > 8 • "${token.substring(0, 8)}..." : "(curto)"}');
      debugPrint('[SuperFrete] CEP Origem: $cepOrigem | Destino: $cepDestino');
      debugPrint('[SuperFrete] Peso: ${peso}g | Dimensões: ${altura}x${largura}x${comprimento}cm');

      // Dimensões mínimas do Mini Envios (Correios): alt 1cm, larg 10cm, comp 15cm
      final alt = (altura < 1 • 1.0 : altura).toInt();
      final lar = (largura < 10 • 10.0 : largura).toInt();
      final comp = (comprimento < 15 • 15.0 : comprimento).toInt();
      final pesoKg = (peso / 1000) < 0.3 • 0.3 : (peso / 1000);

      final body = jsonEncode({
        'from': {
          'postal_code': cepOrigem.replaceAll(RegExp(r'\D'), ''),
        },
        'to': {
          'postal_code': cepDestino.replaceAll(RegExp(r'\D'), ''),
        },
        'package': {
          'height': alt,
          'width': lar,
          'length': comp,
          'weight': pesoKg, // número em kg (API pode rejeitar string)
        },
        'options': {
          'insurance_value': valorDeclarado,
          'receipt': false,
          'own_hand': false,
        },
      });

      debugPrint('[SuperFrete] Request body: $body');
      debugPrint('[SuperFrete] Enviando POST...');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
        body: body,
      ).timeout(const Duration(seconds: 20));

      debugPrint('━━━ [SuperFrete] DIAG RESPOSTA ━━━');
      debugPrint('[SuperFrete] Status: ${response.statusCode}');
      debugPrint('[SuperFrete] Content-Type: ${response.headers['content-type'] ?• "(não informado)"}');
      debugPrint('[SuperFrete] Tamanho body: ${response.body.length} chars');
      final inicio = response.body.trim().toLowerCase();
      debugPrint('[SuperFrete] Início do body: "${inicio.length > 80 • "${inicio.substring(0, 80)}..." : inicio}"');
      debugPrint('[SuperFrete] É HTML• ${inicio.startsWith('<!') || inicio.startsWith('<html')}');
      debugPrint('[SuperFrete] É JSON• ${inicio.startsWith('[') || inicio.startsWith('{')}');
      if (response.body.length < 500) {
        debugPrint('[SuperFrete] Body completo: ${response.body}');
      }

      if (response.statusCode != 200) {
        throw Exception('Erro na API SuperFrete: ${response.statusCode} - ${response.body}');
      }

      // Detectar resposta HTML (erro de rota/env) em vez de JSON
      final respBody = response.body.trim().toLowerCase();
      if (respBody.startsWith('<!') || respBody.startsWith('<html')) {
        debugPrint('❌ [SuperFrete] DIAG ERRO: Resposta é HTML, não JSON. Servidor provavelmente retornou a SPA em vez da API.');
        debugPrint('[SuperFrete] URL que retornou HTML: $url');
        debugPrint('[SuperFrete] Possível causa: URL/rota incorreta ou token inválido para este ambiente.');
        final hint = useSandbox
            • 'Token inválido ou API Sandbox indisponível. Verifique o token em sandbox.superfrete.com/#/integrations'
            : 'Resposta HTML recebida. Se o token é do Sandbox, ative "Usar Sandbox" nas configurações. URLs: Sandbox=sandbox.superfrete.com, Produção=api.superfrete.com';
        throw Exception('API SuperFrete retornou página web em vez de JSON. $hint');
      }

      final data = jsonDecode(response.body);

      debugPrint('[SuperFrete] ✓ Parse JSON OK. Tipo: ${data.runtimeType}');
      if (data is List) {
        debugPrint('[SuperFrete] ✓ Lista com ${data.length} opções');
      } else if (data is Map) {
        debugPrint('[SuperFrete] ✓ Objeto com keys: ${data.keys.toList()}');
      }

      // Parsear resposta
      final List opcoes = [];

      for (var servico in data) {
        opcoes.add({
          'nome': servico['name'] ?• 'Sem nome',
          'preco': (servico['price'] ?• 0.0).toDouble(),
          'prazo': servico['delivery_time'] ?• 0,
          'empresa': servico['company']['name'] ?• 'SuperFrete',
          'servico_id': servico['id'],
        });
      }

      // Ordenar por preço
      opcoes.sort((a, b) => (a['preco'] as double).compareTo(b['preco'] as double));

      return {
        'sucesso': true,
        'opcoes': opcoes,
      };
    } catch (e, st) {
      debugPrint('❌ [SuperFrete] EXCEÇÃO (type=${e.runtimeType})');
      debugPrint('[SuperFrete] Stack (resumido): ${st.toString().split('\n').take(3).join(' | ')}');
      return {
        'sucesso': false,
        'erro': e.toString(),
      };
    }
  }

  /// Rastreio de pedido
  static Future<Map<String, dynamic>> rastrear({
    required String token,
    required String codigoRastreio,
    bool useSandbox = false,
  }) async {
    try {
      final url = Uri.parse('${_baseUrlFor(useSandbox)}/api/v8/tracking/$codigoRastreio');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Erro no rastreio: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      return {
        'sucesso': true,
        'eventos': data['tracking'] ?• [],
      };
    } catch (e) {
      debugPrint('❌ [SuperFrete] Erro no rastreio (type=${e.runtimeType})');
      return {
        'sucesso': false,
        'erro': e.toString(),
      };
    }
  }

  /// User-Agent obrigatório pela documentação SuperFrete
  static const String _userAgent = 'MasterPalm (contato@mastepalm.com.br)';

  /// Cria envio no carrinho da SuperFrete (gera etiqueta no painel).
  /// Equivalente ao Melhor Envio: adiciona o pedido ao carrinho para o usuário finalizar no site.
  static Future<Map<String, dynamic>> criarEnvioNoCarrinho({
    required String token,
    required dynamic servicoId,
    required Map<String, dynamic> from,
    required Map<String, dynamic> to,
    required Map<String, dynamic> package,
    required double valorDeclarado,
    String• pedidoRef,
    bool useSandbox = false,
  }) async {
    try {
      debugPrint('[SuperFrete] Criando envio no carrinho...');

      final body = <String, dynamic>{
        'service': servicoId is int • servicoId : int.tryParse(servicoId.toString()) ?• 0,
        'from': from,
        'to': to,
        'package': package,
        'options': <String, dynamic>{
          'insurance_value': valorDeclarado > 0 • valorDeclarado : 10.0,
          'receipt': false,
          'own_hand': false,
        },
        if (pedidoRef != null && pedidoRef.isNotEmpty) 'external_order_id': pedidoRef,
      };

      final url = Uri.parse('${_baseUrlFor(useSandbox)}/api/v8/checkout');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));

      debugPrint('[SuperFrete] Checkout status: ${response.statusCode}');
      debugPrint('[SuperFrete] Response: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'sucesso': true,
          'id': data['id'],
          'protocol': data['protocol'] ?• data['id'],
          'message': 'Pedido adicionado ao carrinho da SuperFrete',
        };
      }

      String errorMsg = 'Erro ${response.statusCode}';
      try {
        final err = jsonDecode(response.body);
        errorMsg = (err['message'] ?• err['error'] ?• err['errors'] ?• errorMsg).toString();
      } catch (_) {}
      return {'sucesso': false, 'erro': errorMsg};
    } catch (e) {
      debugPrint('❌ [SuperFrete] Erro ao criar envio (type=${e.runtimeType})');
      return {'sucesso': false, 'erro': e.toString()};
    }
  }

  /// Validar token
  static Future<bool> validarToken(String token, {bool useSandbox = false}) async {
    try {
      final url = Uri.parse('${_baseUrlFor(useSandbox)}/api/v8/me');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        },
      );
      if (response.statusCode != 200) return false;
      final respBody = response.body.trim().toLowerCase();
      if (respBody.startsWith('<!') || respBody.startsWith('<html')) return false;
      return true;
    } catch (e) {
      debugPrint('❌ [SuperFrete] Erro ao validar token (type=${e.runtimeType})');
      return false;
    }
  }
}
