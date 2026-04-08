// lib/services/checkout_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'license_manager.dart';

/// Checkout de planos: preferência criada **somente** no backend (token MP fora do app).
class CheckoutService {
  static String _normalizePlanId(String? raw) {
    final p = (raw ?? '').trim().toLowerCase();
    switch (p) {
      case 'mensal':
      case 'pro_monthly':
        return 'pro_monthly';
      case 'anual':
      case 'pro_yearly':
        return 'pro_yearly';
      case 'basic':
      case 'basic_monthly':
        return 'basic_monthly';
      case 'intermediate':
      case 'intermediate_monthly':
        return 'intermediate_monthly';
      case 'trial_90d':
      case 'free_trial_90d':
        return 'free_trial_90d';
      case 'trial_30d':
      case 'free_trial_30d':
        return 'free_trial_30d';
      default:
        return p;
    }
  }

  /// Corpo `plan` aceito por [planCreatePreference] (Cloud Function).
  static String _apiPlanFromCanonical(String canonical) {
    switch (canonical) {
      case 'pro_yearly':
        return 'anual';
      case 'pro_monthly':
        return 'mensal';
      case 'basic_monthly':
      case 'intermediate_monthly':
        return canonical;
      default:
        return canonical;
    }
  }

  /// Abre checkout MP: POST autenticado em [planCreatePreference] (Cloud Function).
  ///
  /// [titulo], [preco] e [quantidade] são ignorados — mantidos na assinatura por compatibilidade
  /// com telas existentes; valores vêm do servidor.
  static Future<bool> abrirCheckoutPlano({
    required String titulo,
    required double preco,
    required String planoId,
    int quantidade = 1,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }

      final canonical = _normalizePlanId(planoId);
      const paid = {
        'mensal',
        'anual',
        'basic_monthly',
        'intermediate_monthly',
        'pro_monthly',
        'pro_yearly',
      };
      final plan = _apiPlanFromCanonical(canonical);
      if (!paid.contains(plan)) {
        throw Exception('Plano inválido para assinatura paga');
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Sessão inválida. Faça login novamente.');
      }

      final projectId = Firebase.app().options.projectId;
      final url = Uri.parse(
        'https://southamerica-east1-$projectId.cloudfunctions.net/planCreatePreference',
      );

      String installationId;
      try {
        installationId = await LicenseManager.getDeviceId();
      } catch (_) {
        installationId = '';
      }

      final resp = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'plan': plan,
              if (installationId.isNotEmpty) 'installationId': installationId,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode == 401) {
        throw Exception('Sessão expirada. Faça login novamente.');
      }
      if (resp.statusCode == 429) {
        throw Exception('Muitas tentativas. Aguarde um minuto e tente de novo.');
      }
      if (resp.statusCode != 200) {
        debugPrint(
          '❌ planCreatePreference ${resp.statusCode} ${resp.body}',
        );
        throw Exception(
          'Não foi possível iniciar o checkout. Tente novamente.',
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final initPoint = data['init_point']?.toString() ?? '';
      if (initPoint.isEmpty) {
        throw Exception('Resposta inválida do servidor');
      }

      final uri = Uri.parse(initPoint);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Não foi possível abrir o checkout');
      }

      return true;
    } catch (e) {
      debugPrint('❌ Erro ao abrir checkout (type=${e.runtimeType})');
      rethrow;
    }
  }

  static Future<void> abrirCheckoutPix({
    required String titulo,
    required double preco,
    required String pixKey,
  }) async {
    throw UnimplementedError('Checkout PIX em desenvolvimento');
  }

  /// Descontinuado: status de pagamento vem do webhook + doc users no Firestore.
  @Deprecated('Use PlanosService.fetchCurrentPlan / snapshots em users/{uid}')
  static Future<String> verificarStatusPagamento(String preferenceId) async {
    return 'not_found';
  }

  /// Bloqueado: ativação só no backend após confirmação real no Mercado Pago.
  static Future<void> ativarPlanoPagamento({
    required String userEmail,
    required String planoId,
    required String paymentId,
  }) async {
    throw UnsupportedError(
      'A liberação do plano ocorre apenas no servidor após o webhook e consulta '
      'do pagamento no Mercado Pago. O app não pode ativar plano localmente.',
    );
  }
}
