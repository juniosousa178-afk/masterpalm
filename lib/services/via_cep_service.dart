// lib/services/via_cep_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resultado da busca de CEP via ViaCEP
class ViaCepResult {
  final String cep;
  final String logradouro;
  final String complemento;
  final String bairro;
  final String localidade;
  final String uf;

  ViaCepResult({
    required this.cep,
    required this.logradouro,
    required this.complemento,
    required this.bairro,
    required this.localidade,
    required this.uf,
  });

  /// Endereço formatado (logradouro, bairro)
  String get enderecoCompleto {
    final partes = <String>[];
    if (logradouro.isNotEmpty) partes.add(logradouro);
    if (bairro.isNotEmpty) partes.add(bairro);
    return partes.join(', ');
  }
}

/// Serviço de busca de CEP via API ViaCEP (gratuita)
class ViaCepService {
  static const String _baseUrl = 'https://viacep.com.br/ws';

  /// Indica se a resposta da API indica "CEP não encontrado" (erro explícito)
  static bool _isErroResposta(Map<String, dynamic> data) {
    if (!data.containsKey('erro')) return false;
    final v = data['erro'];
    return v == true || v == 'true' || v == 1;
  }

  /// Busca endereço pelo CEP (apenas dígitos, 8 caracteres)
  static Future<ViaCepResult?> buscar(String cep) async {
    final apenasDigitos = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (apenasDigitos.length != 8) return null;

    try {
      final url = Uri.parse('$_baseUrl/$apenasDigitos/json/');
      final response = await http.get(url).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('Timeout ao buscar CEP'),
      );

      final body = response.body.trim();
      if (body.isEmpty) {
        if (kDebugMode) debugPrint('⚠️ [ViaCEP] Resposta vazia');
        return null;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        if (kDebugMode) debugPrint('⚠️ [ViaCEP] Resposta não é JSON válido');
        return null;
      }

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('⚠️ [ViaCEP] HTTP ${response.statusCode}');
        return null;
      }

      if (_isErroResposta(data)) return null;

      return ViaCepResult(
        cep: (data['cep'] ?? '').toString().trim(),
        logradouro: (data['logradouro'] ?? '').toString().trim(),
        complemento: (data['complemento'] ?? '').toString().trim(),
        bairro: (data['bairro'] ?? '').toString().trim(),
        localidade: (data['localidade'] ?? '').toString().trim(),
        uf: (data['uf'] ?? '').toString().trim(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [ViaCEP] Erro (type=${e.runtimeType})');
      return null;
    }
  }
}
