import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cliente do `sendEmail` (Cloud Function). O app não tem credencial SMTP: só pede
/// e-mails de tipos aprovados; destinatário e conteúdo são derivados no servidor a
/// partir do pedido / participação / carrinho, com o usuário autenticado da loja.
class EmailService {
  EmailService._();

  static const String tipoConfirmacaoPedido = 'order_confirmation';
  static const String tipoParticipacaoSorteio = 'raffle_participation';
  static const String tipoLembreteCarrinho = 'abandoned_cart_reminder';

  @visibleForTesting
  static Future<({int statusCode, String body})> Function(
    Map<String, String> payload,
  )? debugEnviarOverride;

  /// Confirmação de pagamento do pedido [vendaId]. Bloco de sorteio só com
  /// [camposSorteio] completos (o servidor ainda valida a participação).
  static Map<String, String> payloadConfirmacaoPedido({
    required String lojaId,
    required String vendaId,
    Map<String, String>? camposSorteio,
  }) =>
      {
        'emailType': tipoConfirmacaoPedido,
        'lojaId': lojaId.trim(),
        'saleId': vendaId.trim(),
        if (camposSorteio != null) ...{
          'campaignId': camposSorteio['campaignId'] ?? '',
          'participationId': camposSorteio['participationId'] ?? '',
          'luckyNumber': camposSorteio['luckyNumber'] ?? '',
        },
      };

  /// Participação persistida em campanha (campos de `camposSorteioEstruturados`).
  static Map<String, String> payloadParticipacaoSorteio(
    Map<String, String> camposSorteio,
  ) =>
      {
        'emailType': tipoParticipacaoSorteio,
        'lojaId': camposSorteio['lojaId'] ?? '',
        'saleId': camposSorteio['saleId'] ?? '',
        'campaignId': camposSorteio['campaignId'] ?? '',
        'participationId': camposSorteio['participationId'] ?? '',
        'luckyNumber': camposSorteio['luckyNumber'] ?? '',
      };

  /// Lembrete de carrinho abandonado: [cartId] (catálogo) ou [clienteId] (cadastro).
  static Map<String, String> payloadLembreteCarrinho({
    required String lojaId,
    String? clienteId,
    String? cartId,
    String? destinatario,
    String? link,
  }) {
    final cart = (cartId ?? '').trim();
    final cliente = (clienteId ?? '').trim();
    final to = (destinatario ?? '').trim();
    final url = (link ?? '').trim();
    return {
      'emailType': tipoLembreteCarrinho,
      'lojaId': lojaId.trim(),
      if (cart.isNotEmpty) 'cartId': cart else if (cliente.isNotEmpty) 'clienteId': cliente,
      if (to.isNotEmpty) 'to': to,
      if (url.isNotEmpty) 'link': url,
    };
  }

  /// `true` só quando o servidor confirmou o envio.
  static bool foiEnviado(int statusCode, String body) {
    if (statusCode != 200) return false;
    try {
      final json = jsonDecode(body);
      return json is Map && json['sent'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Código de erro/recusa devolvido pelo servidor (ex.: `EMAIL_COOLDOWN`).
  static String? codigoResposta(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['code'] != null) return json['code'].toString();
    } catch (_) {}
    return null;
  }

  static Future<({int statusCode, String body})> enviar(
    Map<String, String> payload,
  ) async {
    final override = debugEnviarOverride;
    if (override != null) return override(payload);

    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final projectId = Firebase.app().options.projectId;
    final response = await http.post(
      Uri.parse(
        'https://southamerica-east1-$projectId.cloudfunctions.net/sendEmail',
      ),
      headers: {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    return (statusCode: response.statusCode, body: response.body);
  }
}
