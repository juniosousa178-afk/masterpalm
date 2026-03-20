// lib/services/globo_sorte_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/logger.dart';
import 'remote_config_service.dart';

/// Serviço de integração com a API da Globo da Sorte
/// Permite vincular números da sorte e consultar resultados de sorteios
class GloboSorteService {
  static const String _baseUrl = 'https://api.globosorte.com.br'; // URL da API

  /// Registra um número da sorte na Globo da Sorte
  ///
  /// Parâmetros:
  /// - numero: Número da sorte (ex: "53827")
  /// - campanhaId: ID da campanha na loja
  /// - clienteNome: Nome do cliente
  /// - clienteEmail: Email do cliente (opcional)
  /// - clienteWhatsApp: WhatsApp do cliente (opcional)
  /// - valorCompra: Valor da compra que gerou o número
  ///
  /// Retorna o ID do registro na Globo da Sorte ou null em caso de erro
  static Future<String?> registrarNumero({
    required String numero,
    required String campanhaId,
    required String clienteNome,
    String• clienteEmail,
    String• clienteWhatsApp,
    required double valorCompra,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/numeros'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_getApiKey()}',
        },
        body: jsonEncode({
          'numero': numero,
          'campanha_id': campanhaId,
          'cliente': {
            'nome': clienteNome,
            'email': clienteEmail,
            'whatsapp': clienteWhatsApp,
          },
          'valor_compra': valorCompra,
          'data_registro': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final id = data['id'] as String?;
        logD('✅ Número $numero registrado na Globo da Sorte: $id');
        return id;
      } else {
        logE('❌ Erro ao registrar número: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, st) {
      logE('❌ Exceção ao registrar número (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Consulta os números registrados de uma campanha
  ///
  /// Retorna lista de números com seus dados
  static Future<List<Map<String, dynamic>>> consultarNumerosCampanha({
    required String campanhaId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/campanhas/$campanhaId/numeros'),
        headers: {
          'Authorization': 'Bearer ${_getApiKey()}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['numeros'] ?• []);
      } else {
        logE('❌ Erro ao consultar números: ${response.statusCode}');
        return [];
      }
    } catch (e, st) {
      logE('❌ Exceção ao consultar números (type=${e.runtimeType})', error: e, st: st);
      return [];
    }
  }

  /// Consulta o resultado de um sorteio realizado
  ///
  /// Retorna o número vencedor e dados do vencedor, ou null se não houver
  static Future<Map<String, dynamic>?> consultarResultadoSorteio({
    required String campanhaId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/campanhas/$campanhaId/resultado'),
        headers: {
          'Authorization': 'Bearer ${_getApiKey()}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['sorteado'] == true) {
          return {
            'numero_vencedor': data['numero_vencedor'],
            'cliente_nome': data['cliente']['nome'],
            'cliente_email': data['cliente']['email'],
            'cliente_whatsapp': data['cliente']['whatsapp'],
            'data_sorteio': DateTime.parse(data['data_sorteio']),
          };
        }
        return null;
      } else {
        logE('❌ Erro ao consultar resultado: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      logE('❌ Exceção ao consultar resultado (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Solicita um sorteio aleatório via API
  ///
  /// Retorna os dados do vencedor ou null se não houver participantes
  static Future<Map<String, dynamic>?> realizarSorteio({
    required String campanhaId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/v1/campanhas/$campanhaId/sortear'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_getApiKey()}',
        },
        body: jsonEncode({
          'data_sorteio': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        logD('✅ Sorteio realizado: ${data['numero_vencedor']}');
        return {
          'numero_vencedor': data['numero_vencedor'],
          'cliente_nome': data['cliente']['nome'],
          'cliente_email': data['cliente']['email'],
          'cliente_whatsapp': data['cliente']['whatsapp'],
          'total_participantes': data['total_participantes'],
        };
      } else {
        logE('❌ Erro ao realizar sorteio: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      logE('❌ Exceção ao realizar sorteio (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Valida se um número existe e pertence à campanha
  static Future<bool> validarNumero({
    required String numero,
    required String campanhaId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/numeros/$numero/validar?campanha_id=$campanhaId'),
        headers: {
          'Authorization': 'Bearer ${_getApiKey()}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valido'] == true;
      } else {
        return false;
      }
    } catch (e, st) {
      logE('❌ Exceção ao validar número (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Obtém estatísticas de uma campanha
  static Future<Map<String, dynamic>?> obterEstatisticas({
    required String campanhaId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/v1/campanhas/$campanhaId/estatisticas'),
        headers: {
          'Authorization': 'Bearer ${_getApiKey()}',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'total_numeros': data['total_numeros'],
          'total_participantes': data['total_participantes'],
          'valor_total_compras': data['valor_total_compras'],
          'sorteio_realizado': data['sorteio_realizado'],
          'numero_vencedor': data['numero_vencedor'],
        };
      } else {
        logE('❌ Erro ao obter estatísticas: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      logE('❌ Exceção ao obter estatísticas (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  /// Retorna a API Key via Remote Config (nunca hardcoded).
  /// Configure a chave 'globo_sorte_api_key' no Firebase Remote Config.
  static String _getApiKey() {
    final apiKey = RemoteConfigService.globoSorteApiKey;
    if (apiKey.isEmpty) {
      logW('⚠️ API Key da Globo da Sorte não configurada (Remote Config: globo_sorte_api_key).');
    }
    return apiKey;
  }

  /// Sincroniza números locais com a Globo da Sorte
  ///
  /// Útil para sincronizar números que foram gerados offline
  static Future<int> sincronizarNumeros({
    required String campanhaId,
    required List<Map<String, dynamic>> numeros,
  }) async {
    int sucessos = 0;

    for (final numero in numeros) {
      final id = await registrarNumero(
        numero: numero['numero'] as String,
        campanhaId: campanhaId,
        clienteNome: numero['clienteNome'] as String,
        clienteEmail: numero['clienteEmail'] as String?,
        clienteWhatsApp: numero['clienteWhatsApp'] as String?,
        valorCompra: (numero['valorCompra'] as num).toDouble(),
      );

      if (id != null) {
        sucessos++;
      }
    }

    logD('✅ Sincronizados $sucessos de ${numeros.length} números');
    return sucessos;
  }
}

/// Modelo de dados para número da sorte
class NumeroSorte {
  final String numero;
  final String campanhaId;
  final String clienteNome;
  final String• clienteEmail;
  final String• clienteWhatsApp;
  final double valorCompra;
  final DateTime dataRegistro;
  final String• globoSorteId; // ID retornado pela API da Globo da Sorte

  NumeroSorte({
    required this.numero,
    required this.campanhaId,
    required this.clienteNome,
    this.clienteEmail,
    this.clienteWhatsApp,
    required this.valorCompra,
    required this.dataRegistro,
    this.globoSorteId,
  });

  Map<String, dynamic> toMap() {
    return {
      'numero': numero,
      'campanhaId': campanhaId,
      'clienteNome': clienteNome,
      'clienteEmail': clienteEmail,
      'clienteWhatsApp': clienteWhatsApp,
      'valorCompra': valorCompra,
      'dataRegistro': dataRegistro.toIso8601String(),
      'globoSorteId': globoSorteId,
    };
  }

  factory NumeroSorte.fromMap(Map<String, dynamic> map) {
    return NumeroSorte(
      numero: map['numero'] as String,
      campanhaId: map['campanhaId'] as String,
      clienteNome: map['clienteNome'] as String,
      clienteEmail: map['clienteEmail'] as String?,
      clienteWhatsApp: map['clienteWhatsApp'] as String?,
      valorCompra: (map['valorCompra'] as num).toDouble(),
      dataRegistro: DateTime.parse(map['dataRegistro'] as String),
      globoSorteId: map['globoSorteId'] as String?,
    );
  }
}
