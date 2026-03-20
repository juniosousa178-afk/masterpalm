// lib/utils/http_client_helper.dart
//
// Helpers reutilizáveis para chamadas HTTP com timeout padronizado e retry seguro.
// Evita travamentos e padroniza comportamento SRE.
//
// NÃO altera comportamento funcional: retorna os mesmos resultados,
// apenas adiciona timeout e retry onde é seguro.

import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Timeouts padrão por tipo de chamada
class HttpTimeouts {
  /// APIs de pagamento (Ton, MercadoPago, PagSeguro, InfinitePay) - 20s
  static const Duration payment = Duration(seconds: 20);

  /// Cloud Functions (createPreference, gerarCupom, etc) - 30s
  static const Duration cloudFunction = Duration(seconds: 30);

  /// APIs de frete (Melhor Envio, Frenet, SuperFrete) - 20s
  static const Duration freight = Duration(seconds: 20);

  /// APIs de terceiros lentas (ViaCEP, etc) - 15s
  static const Duration external = Duration(seconds: 15);

  /// Chamadas rápidas (validação, health check) - 10s
  static const Duration quick = Duration(seconds: 10);

  /// Genérico - 15s
  static const Duration standard = Duration(seconds: 15);
}

/// Helper centralizado para chamadas HTTP
class HttpClientHelper {
  /// Executa GET com timeout (sem retry - GET é idempotente, mas retry é opcional)
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final t = timeout ?? HttpTimeouts.standard;
    return http.get(url, headers: headers).timeout(
          t,
          onTimeout: () => throw TimeoutException('GET $url excedeu ${t.inSeconds}s'),
        );
  }

  /// Executa POST com timeout (sem retry por padrão - operações de criação podem duplicar)
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final t = timeout ?? HttpTimeouts.standard;
    return http.post(url, headers: headers, body: body).timeout(
          t,
          onTimeout: () => throw TimeoutException('POST $url excedeu ${t.inSeconds}s'),
        );
  }

  /// Executa PUT com timeout
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final t = timeout ?? HttpTimeouts.standard;
    return http.put(url, headers: headers, body: body).timeout(
          t,
          onTimeout: () => throw TimeoutException('PUT $url excedeu ${t.inSeconds}s'),
        );
  }

  /// Executa DELETE com timeout
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final t = timeout ?? HttpTimeouts.standard;
    return http.delete(url, headers: headers, body: body).timeout(
          t,
          onTimeout: () => throw TimeoutException('DELETE $url excedeu ${t.inSeconds}s'),
        );
  }

  /// GET com retry exponencial (seguro para leituras)
  /// [maxAttempts] padrão 3, [baseDelay] 500ms
  static Future<http.Response> getWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 500),
  }) async {
    final t = timeout ?? HttpTimeouts.standard;
    Exception? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await http.get(url, headers: headers).timeout(
              t,
              onTimeout: () => throw TimeoutException('GET $url excedeu ${t.inSeconds}s'),
            );
        if (resp.statusCode < 500) return resp; // Não retry em 4xx
        lastError = Exception('Status ${resp.statusCode}');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ [HTTP] GET $url tentativa $attempt/$maxAttempts (type=${e.runtimeType})');
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(baseDelay * (1 << (attempt - 1)));
      }
    }
    throw lastError ?? Exception('getWithRetry falhou');
  }

  /// POST com retry exponencial - USAR APENAS para operações idempotentes
  /// (ex: criar preferência de checkout que gera link, não cobrança)
  static Future<http.Response> postWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 500),
  }) async {
    final t = timeout ?? HttpTimeouts.standard;
    Exception? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await http.post(url, headers: headers, body: body).timeout(
              t,
              onTimeout: () => throw TimeoutException('POST $url excedeu ${t.inSeconds}s'),
            );
        if (resp.statusCode < 500) return resp;
        lastError = Exception('Status ${resp.statusCode}');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ [HTTP] POST $url tentativa $attempt/$maxAttempts (type=${e.runtimeType})');
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(baseDelay * (1 << (attempt - 1)));
      }
    }
    throw lastError ?? Exception('postWithRetry falhou');
  }

  /// Executa request com timeout - wrapper genérico
  static Future<T> runWithTimeout<T>(
    Future<T> Function() fn, {
    required Duration timeout,
    String? operationName,
  }) async {
    return fn().timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        '${operationName ?? "Operação"} excedeu ${timeout.inSeconds}s',
      ),
    );
  }
}
