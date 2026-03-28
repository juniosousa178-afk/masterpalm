// lib/services/checkout_service.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'master_config_service.dart';

/// Serviço de checkout para pagamentos de planos via Mercado Pago
class CheckoutService {
  static final _db = FirebaseFirestore.instance;

  static String _normalizePlanId(String? raw) {
    final p = (raw ?? '').trim().toLowerCase();
    switch (p) {
      case 'mensal':
      case 'pro_monthly':
        return 'pro_monthly';
      case 'anual':
      case 'pro_yearly':
        return 'pro_yearly';
      case 'trial_90d':
      case 'free_trial_90d':
        return 'free_trial_90d';
      default:
        return p;
    }
  }

  static String _legacyPlanAliasFromCanonical(String canonical) {
    switch (canonical) {
      case 'pro_yearly':
        return 'anual';
      case 'pro_monthly':
        return 'mensal';
      default:
        return canonical;
    }
  }

  /// Cria preferência de pagamento no Mercado Pago e abre o checkout
  ///
  /// Parâmetros:
  /// - [titulo]: Título do produto (ex: "Plano Mensal MasterPalm")
  /// - [preco]: Valor do plano (ex: 25.90)
  /// - [planoId]: ID do plano (ex: "mensal", "anual")
  /// - [quantidade]: Quantidade (geralmente 1)
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

      final email = user.email?.toLowerCase().trim() ?? '';
      final normalizedPlanId = _normalizePlanId(planoId);
      final legacyPlanAlias = _legacyPlanAliasFromCanonical(normalizedPlanId);
      final externalReference =
          'plano_${legacyPlanAlias}_${DateTime.now().millisecondsSinceEpoch}';

      // Busca configurações do Mercado Pago da Tela Master
      final accessToken = await MasterConfigService.getMercadoPagoAccessToken();

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(
          'Mercado Pago não configurado.\n'
          'Configure o Mercado Pago em Configurações Master (menu lateral) primeiro.',
        );
      }

      // Cria preferência de pagamento
      final preference = await _criarPreferenciaMercadoPago(
        accessToken: accessToken,
        titulo: titulo,
        preco: preco,
        quantidade: quantidade,
        email: email,
        planoId: legacyPlanAlias,
        normalizedPlanId: normalizedPlanId,
        externalReference: externalReference,
        userId: user.uid,
      );

      if (preference == null || preference['init_point'] == null) {
        throw Exception('Falha ao criar preferência de pagamento');
      }

      // Salva registro do checkout iniciado
      await _db.collection('checkout_planos').add({
        'userId': user.uid,
        'userEmail': email,
        'planoId': legacyPlanAlias, // legado/fallback
        'normalizedPlanId': normalizedPlanId, // canônico
        'titulo': titulo,
        'preco': preco,
        'quantidade': quantidade,
        'preferenceId': preference['id'],
        'externalReference': externalReference,
        'source': 'planos_screen',
        'metadata': {
          'uid': user.uid,
          'email': email,
          'normalizedPlanId': normalizedPlanId,
        },
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Abre o checkout do Mercado Pago
      final checkoutUrl = preference['init_point'].toString();
      final uri = Uri.parse(checkoutUrl);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Não foi possível abrir o checkout');
      }

      return true;
    } catch (e) {
      debugPrint('❌ Erro ao abrir checkout (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Cria preferência de pagamento no Mercado Pago via API
  static Future<Map<String, dynamic>?> _criarPreferenciaMercadoPago({
    required String accessToken,
    required String titulo,
    required double preco,
    required int quantidade,
    required String email,
    required String planoId,
    required String normalizedPlanId,
    required String externalReference,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('https://api.mercadopago.com/checkout/preferences');

      // URLs de retorno (app.mastepalm.com.br - domínio principal)
      const baseUrl = 'https://app.mastepalm.com.br';
      final projectId = Firebase.app().options.projectId;
      final planWebhookUrl =
          'https://southamerica-east1-$projectId.cloudfunctions.net/planWebhook';

      final body = {
        'items': [
          {
            'title': titulo,
            'quantity': quantidade,
            'unit_price': preco,
            'currency_id': 'BRL',
          }
        ],
        'payer': {
          'email': email,
        },
        'back_urls': {
          'success': '$baseUrl/checkout/success?plano=$planoId',
          'failure': '$baseUrl/checkout/failure',
          'pending': '$baseUrl/checkout/pending',
        },
        'auto_return': 'approved',
        'notification_url': planWebhookUrl,
        'external_reference': externalReference,
        'metadata': {
          'plano_id': planoId,
          'normalized_plan_id': normalizedPlanId,
          'uid': userId,
          'user_id': userId,
          'user_email': email,
        },
      };

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('❌ Erro MP API: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Erro ao criar preferência (type=${e.runtimeType})');
      return null;
    }
  }

  /// Abre checkout PIX para pagamento de plano
  ///
  /// Alternativa ao Mercado Pago caso o usuário prefira PIX direto
  static Future<void> abrirCheckoutPix({
    required String titulo,
    required double preco,
    required String pixKey,
  }) async {
    // Implementação futura: gerar QR Code PIX
    throw UnimplementedError('Checkout PIX em desenvolvimento');
  }

  /// Verifica status de pagamento de um plano
  static Future<String> verificarStatusPagamento(String preferenceId) async {
    try {
      final snapshot = await _db
          .collection('checkout_planos')
          .where('preferenceId', isEqualTo: preferenceId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return 'not_found';
      }

      final doc = snapshot.docs.first;
      final data = doc.data();
      return data['status']?.toString() ?? 'pending';
    } catch (e) {
      debugPrint('❌ Erro ao verificar status (type=${e.runtimeType})');
      return 'error';
    }
  }

  /// Ativa o plano após confirmação de pagamento
  ///
  /// Este método deve ser chamado pelo webhook do Mercado Pago
  /// ou manualmente após verificar o pagamento
  static Future<void> ativarPlanoPagamento({
    required String userEmail,
    required String planoId,
    required String paymentId,
  }) async {
    try {
      // LEGADO/FALLBACK: manter compatibilidade sem ser fonte principal.
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado');
      }

      // Define duração baseada no plano
      int dias;
      switch (planoId) {
        case 'mensal':
        case 'pro_monthly':
          dias = 30;
          break;
        case 'anual':
        case 'pro_yearly':
          dias = 365;
          break;
        default:
          dias = 30;
      }

      final endDate = DateTime.now().add(Duration(days: dias));
      final normalizedPlanId = _normalizePlanId(planoId);

      // Fonte canônica: users/{uid}
      await _db.collection('users').doc(user.uid).set({
        'email': userEmail,
        'currentPlanId': normalizedPlanId,
        'status': 'active',
        'trialing': false,
        'currentPeriodEnd': Timestamp.fromDate(endDate),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // LEGADO/FALLBACK: manter em usuarios/{email} para não quebrar telas antigas.
      await _db.collection('usuarios').doc(userEmail).set({
        'email': userEmail,
        'planoId': planoId,
        'planoAtivo': true,
        'isLifetime': false,
        'manualOverride': false,
        'paymentId': paymentId,
        'activatedAt': FieldValue.serverTimestamp(),
        'currentPeriodEnd': Timestamp.fromDate(endDate),
      }, SetOptions(merge: true));

      debugPrint('✅ [PlanosCheckout] Ativação manual fallback concluída para $userEmail');
    } catch (e) {
      debugPrint('❌ Erro ao ativar plano (type=${e.runtimeType})');
      rethrow;
    }
  }
}
