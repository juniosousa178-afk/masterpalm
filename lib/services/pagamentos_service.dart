// lib/services/pagamentos_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import 'loja_id_service.dart';
import '../utils/http_client_helper.dart';

/// Serviço de Pagamentos (Mercado Pago + outros gateways)
/// usado pela tela de Configuração de Pagamentos.
class PagamentosService {
  static final FirebaseFirestore db = FirebaseFirestore.instance;

  /// Descobre a loja atual. Prioridade: StoreResolver/LojaIdService → Hive (fallback offline).
  /// Nunca retorna loja fixa; lança StateError se não conseguir resolver.
  static Future<String> getLojaId() async {
    String• storeId = (await LojaIdService.get())?.trim();
    if (storeId != null && storeId.isNotEmpty) return storeId;

    try {
      final sessao = Hive.isBoxOpen('sessao')
          • Hive.box('sessao')
          : await Hive.openBox('sessao');
      storeId = (sessao.get('store_id') ?• sessao.get('storeId'))?.toString().trim();
      if (storeId != null && storeId.isNotEmpty) return storeId;
    } catch (_) {}

    try {
      final config = Hive.isBoxOpen('config')
          • Hive.box('config')
          : await Hive.openBox('config');
      storeId = (config.get('store_id') ?• config.get('store_slug') ?• config.get('loja_slug'))
          ?.toString()
          .trim();
      if (storeId != null && storeId.isNotEmpty) return storeId;
    } catch (_) {}

    throw StateError(
      'Nenhuma loja ativa encontrada. Faça login ou configure a loja.',
    );
  }

  /// Referência do doc de pagamentos:
  /// /lojas/{lojaId}/config/payments
  static DocumentReference<Map<String, dynamic>> paymentsDoc(String lojaId) {
    return db.doc('lojas/$lojaId/config/payments');
  }

  /// Stream do documento de pagamentos da loja
  /// usado pela tela de configuração.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> paymentsDocStream(
    String lojaId,
  ) {
    return paymentsDoc(lojaId).snapshots();
  }

  /// Salva o Access Token do Mercado Pago no doc /lojas/{lojaId}/config/payments
  /// dentro do objeto "mp" e marca como conectado.
  static Future<void> salvarAccessToken(
    String lojaId,
    String accessToken,
  ) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': {
          'access_token': accessToken,
          'token': accessToken, // também salva como 'token' para compatibilidade
          'connected': true, // marca como conectado
          'public_key': accessToken, // mantém por compatibilidade
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Salva a public key (opcional, separada do access token)
  /// Usada para widgets no frontend.
  static Future<void> salvarPublicKey(
    String lojaId,
    String publicKey,
  ) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': {
          'public_key': publicKey,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Salva configurações de um gateway específico (PagSeguro, Ton, InfinitePay etc)
  ///
  /// Exemplo:
  ///   salvarGatewayConfig(
  ///     lojaId: 'minhaLoja',
  ///     gateway: 'pagseguro',
  ///     data: {'token': 'xxx', 'seller_id': 'yyy'},
  ///   );
  ///
  /// Fica salvo em:
  ///   /lojas/{lojaId}/config/payments  com campo:
  ///     { "pagseguro": { ...data... } }
  static Future<void> salvarGatewayConfig({
    required String lojaId,
    required String gateway,
    required Map<String, dynamic> data,
  }) async {
    await paymentsDoc(lojaId).set(
      {
        gateway: data,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Inicia o fluxo de conexão OAuth com o Mercado Pago.
  /// Abre a Cloud Function que redireciona para o MP → usuário autoriza → volta conectado.
  static Future<void> abrirConexaoOAuth(String lojaId) async {
    // URL curta via hosting para evitar truncamento em navegadores mobile
    final oauthUrl =
        'https://app.mastepalm.com.br/mp-oauth?lojaId=${Uri.encodeComponent(lojaId)}';
    final uri = Uri.parse(oauthUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception(
        'Não foi possível abrir a página de conexão do Mercado Pago.',
      );
    }
  }

  /// Desconecta a conta MP da loja (limpa os campos no Firestore)
  /// em /lojas/{lojaId}/config/payments
  static Future<void> desconectarLoja(String lojaId) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': {
          'connected': false,
          'user_id': null,
          'public_key': null,
          'access_token_hint': null,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// (Opcional) Exemplo de chamada ao backend para trocar código por tokens.
  /// Use quando seu fluxo OAuth retornar `code`/`state` para o seu backend.
  static Future<void> finalizarOAuthNoBackend({
    required String code,
    required String state,
  }) async {
    // Ajuste a URL do seu backend/Function
    final uri = Uri.parse(
      'https://app.mastepalm.com.br/api/mp/oauth/callback',
    );

    final resp = await HttpClientHelper.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'state': state}),
      timeout: HttpTimeouts.cloudFunction,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Falha ao finalizar OAuth no backend (${resp.statusCode}): ${resp.body}',
      );
    }
  }
}
