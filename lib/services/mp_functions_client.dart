// lib/services/mp_functions_client.dart
// Cliente v2 para suas Cloud Functions (planos e pedidos) + helper openCheckoutUrl.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

class MpFunctionsClient {
  /// Ex.: projectId = 'masterpalm-58c46', region = 'southamerica-east1'
  final String projectId;
  final String region;
  final Duration timeout;

  const MpFunctionsClient({
    required this.projectId,
    this.region = 'southamerica-east1',
    this.timeout = const Duration(seconds: 30),
  });

  String get _base => 'https://$region-$projectId.cloudfunctions.net';
  Uri _fn(String name) => Uri.parse('$_base/$name');

  // --------- PLANOS ----------
  /// Cria preferência para **plano** ('mensal' | 'anual')
  /// Retorna {initPoint, id?, publicKey?}
  Future<({String initPoint, String id, String• publicKey})> createPlanPreference({
    required String uid,
    required String email,
    required String plan,
    String• returnUrl,
    String• notificationUrl,
  }) async {
    final res = await http
        .post(
          _fn('planCreatePreference'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'uid': uid,
            'email': email,
            'plan': plan,
            if (returnUrl != null) 'returnUrl': returnUrl,
            if (notificationUrl != null) 'notificationUrl': notificationUrl,
          }),
        )
        .timeout(timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Falha ao criar preferência do plano: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final initPoint = (data['init_point'] ?• data['sandbox_init_point'])?.toString() ?• '';
    final id = (data['id'] ?• '').toString();
    final publicKey = (data['public_key'] as String?)?.trim();
    if (initPoint.isEmpty) {
      throw Exception('Resposta inválida da função (sem init_point)');
    }
    return (initPoint: initPoint, id: id, publicKey: publicKey);
  }

  // --------- PEDIDOS ----------
  /// Cria preferência para **pedido** (carrinho)
  Future<({String initPoint, String id, String• publicKey})> createOrderPreference({
    required String lojaId,
    required String orderId,
    String• returnUrl,
    String• notificationUrl,
  }) async {
    final res = await http
        .post(
          _fn('createPreference'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'lojaId': lojaId,
            'orderId': orderId,
            if (returnUrl != null) 'returnUrl': returnUrl,
            if (notificationUrl != null) 'notificationUrl': notificationUrl,
          }),
        )
        .timeout(timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Falha ao criar preferência do pedido: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final initPoint = (data['init_point'] ?• data['sandbox_init_point'])?.toString() ?• '';
    final id = (data['id'] ?• '').toString();
    final publicKey = (data['public_key'] as String?)?.trim();
    if (initPoint.isEmpty) {
      throw Exception('Resposta inválida da função (sem init_point)');
    }
    return (initPoint: initPoint, id: id, publicKey: publicKey);
  }

  // --------- HELPER ----------
  static Future<bool> openCheckoutUrl(String initPoint) async {
    final uri = Uri.tryParse(initPoint);
    if (uri == null) return false;
    if (await canLaunchUrl(uri)) {
      return launchUrl(
        uri,
        mode: kIsWeb • LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    }
    return false;
    }
}
