// lib/services/checkout_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'license_manager.dart';
import 'remote_config_service.dart';

/// POST em [planCreatePreference]: credencial MP só no backend (Secret Manager).
/// No Web: [reload] + [getIdToken(true)] antes do POST; em 401, pausa curta e repete uma vez
/// com [currentUser] atualizado (evita referência de [User] stale).
Future<http.Response> _postPlanCreatePreference({
  required Uri url,
  required Map<String, dynamic> body,
}) async {
  Future<http.Response> attempt({required int attemptNumber}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }
    if (kIsWeb) {
      try {
        await user.reload();
      } catch (e) {
        debugPrint(
          '⚠️ [CheckoutPlano] user.reload (tentativa $attemptNumber): $e',
        );
      }
    }
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Sessão inválida. Faça login novamente.');
    }
    return http
        .post(
          url,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));
  }

  debugPrint(
    '[CheckoutPlano] planCreatePreference — MP no servidor (não usa app_config/master)',
  );
  var resp = await attempt(attemptNumber: 1);
  if (resp.statusCode == 401) {
    debugPrint(
      '⚠️ [CheckoutPlano] planCreatePreference 401 na 1ª tentativa (Firebase ID token) — retry',
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    resp = await attempt(attemptNumber: 2);
    if (resp.statusCode == 401) {
      debugPrint(
        '❌ [CheckoutPlano] planCreatePreference 401 após retry — sessão recusada pelo servidor',
      );
    }
  }
  return resp;
}

/// No Web, [planCreatePreferenceCall] usa auth do SDK (evita 401 quando o browser não envia Bearer ao HTTP).
Future<Map<String, dynamic>?> _tryPlanCreatePreferenceCallOnWeb({
  required String plan,
  required String installationId,
}) async {
  if (!kIsWeb) return null;
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
    } catch (e) {
      debugPrint('[PlanosAuthDiag] callable reload: $e');
    }
    final idTok = await user.getIdToken(true);
    debugPrint(
      '[PlanosAuthDiag] planCreatePreferenceCall plan=$plan '
      'idTokenNonEmpty=${idTok != null && idTok.isNotEmpty}',
    );
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('planCreatePreferenceCall');
    final result = await callable.call(<String, dynamic>{
      'plan': plan,
      if (installationId.isNotEmpty) 'installationId': installationId,
    });
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  } on FirebaseFunctionsException catch (e) {
    final m = e.message ?? '';
    debugPrint(
      '[PlanosAuthDiag] planCreatePreferenceCall code=${e.code} '
      'message=${m.length > 120 ? m.substring(0, 120) : m}',
    );
    return null;
  } catch (e) {
    debugPrint('[PlanosAuthDiag] planCreatePreferenceCall erro: $e');
    return null;
  }
}

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
        debugPrint(
          '[PlanosAuthGate] checkout de planos abortado: sem usuário Firebase',
        );
        throw Exception(
          'Faça login para assinar um plano. Se já estiver logado, atualize a página.',
        );
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

      if (RemoteConfigService.shouldUseRecurringPlanBilling(
        uid: user.uid,
        email: user.email,
      )) {
        try {
          return await _abrirCheckoutPlanoRecorrente(
            planApi: plan,
          );
        } on FirebaseFunctionsException catch (e) {
          if (e.code == 'failed-precondition' &&
              (e.message ?? '').contains('RECURRING_PLAN_BILLING_DISABLED')) {
            debugPrint(
              '[PlanosPilot] fallback checkout legado: servidor RECURRING_PLAN_BILLING_DISABLED',
            );
          } else {
            rethrow;
          }
        }
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

      try {
        if (kIsWeb) {
          try {
            await user.reload();
          } catch (e) {
            debugPrint('[PlanosAuthDiag] pre_http reload: $e');
          }
        }
        final tok = await user.getIdToken(true);
        final prov =
            user.providerData.map((p) => p.providerId).join(',');
        debugPrint(
          '[PlanosAuthDiag] pre_http plan=$plan projectId=$projectId '
          'uidPrefix=${user.uid.length >= 6 ? user.uid.substring(0, 6) : user.uid}… '
          'providers=[$prov] idTokenNonEmpty=${tok != null && tok.isNotEmpty} url=$url',
        );
      } catch (e) {
        debugPrint('[PlanosAuthDiag] pre_http token: $e');
      }

      if (kIsWeb) {
        final viaCall = await _tryPlanCreatePreferenceCallOnWeb(
          plan: plan,
          installationId: installationId,
        );
        final initFromCall = viaCall?['init_point']?.toString() ?? '';
        if (initFromCall.isNotEmpty) {
          debugPrint(
            '[PlanosAuthDiag] checkout planos via planCreatePreferenceCall (OK)',
          );
          final uri = Uri.parse(initFromCall);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw Exception('Não foi possível abrir o checkout');
          }
          return true;
        }
        debugPrint(
          '[PlanosAuthDiag] fallback planCreatePreference HTTP (callable sem init_point ou falhou)',
        );
      }

      final resp = await _postPlanCreatePreference(
        url: url,
        body: {
          'plan': plan,
          if (installationId.isNotEmpty) 'installationId': installationId,
        },
      );

      if (resp.statusCode == 401) {
        throw Exception(
          'Não foi possível validar a sessão com o servidor. '
          'Atualize a página ou faça login de novo.',
        );
      }
      if (resp.statusCode == 429) {
        throw Exception('Muitas tentativas. Aguarde um minuto e tente de novo.');
      }
      if (resp.statusCode != 200) {
        debugPrint(
          '❌ planCreatePreference ${resp.statusCode} ${resp.body}',
        );
        var msg = 'Não foi possível iniciar o checkout. Tente novamente.';
        try {
          final err = jsonDecode(resp.body);
          if (err is Map) {
            final e = err['error'] ?? err['message'];
            if (e != null && e.toString().trim().isNotEmpty) {
              msg = e.toString();
            }
          }
        } catch (_) {
          final b = resp.body.trim();
          if (b.length > 3 && b.length < 200 && !b.contains('<')) {
            msg = b;
          }
        }
        throw Exception(msg);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        throw Exception('Resposta inválida do servidor de checkout.');
      }
      final data = Map<String, dynamic>.from(decoded);
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

  /// Assinatura recorrente (MP preapproval) — backend [createPlanSubscription].
  static Future<bool> _abrirCheckoutPlanoRecorrente({
    required String planApi,
  }) async {
    Future<HttpsCallableResult<dynamic>> callOnce() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');
      if (kIsWeb) {
        try {
          await user.reload();
        } catch (e) {
          debugPrint('⚠️ [CheckoutPlano] createPlanSubscription reload: $e');
        }
      }
      await user.getIdToken(true);
      final functions =
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = functions.httpsCallable('createPlanSubscription');
      return callable.call(<String, dynamic>{
        'plan': planApi,
      });
    }

    debugPrint(
      '[CheckoutPlano] createPlanSubscription — MP no servidor (Secret Manager)',
    );
    HttpsCallableResult<dynamic> result;
    try {
      result = await callOnce();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        debugPrint(
          '⚠️ [CheckoutPlano] createPlanSubscription unauthenticated — retry após refresh de token',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        result = await callOnce();
      } else {
        rethrow;
      }
    }
    final map = result.data;
    if (map is! Map) {
      throw Exception('Resposta inválida do servidor (recorrente).');
    }
    final ok = map['ok'] == true;
    final initPoint = map['initPoint']?.toString() ?? '';
    if (!ok || initPoint.isEmpty) {
      throw Exception(map['message']?.toString() ?? 'Falha ao iniciar assinatura recorrente.');
    }
    final uri = Uri.parse(initPoint);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Não foi possível abrir o checkout');
    }
    return true;
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
