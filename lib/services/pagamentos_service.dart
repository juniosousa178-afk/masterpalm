// lib/services/pagamentos_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_urls.dart';
import 'loja_id_service.dart';
import 'pagamentos_mp_firestore_writes.dart';
import '../utils/http_client_helper.dart';

/// Falha na troca OAuth. [statusCode] null = sem resposta (rede/timeout).
/// [message] vem do servidor (texto público fixo) ou é genérica; nunca contém code/state/tokens.
class MpOAuthExchangeException implements Exception {
  const MpOAuthExchangeException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Serviço de Pagamentos (Mercado Pago + outros gateways)
/// usado pela tela de Configuração de Pagamentos.
class PagamentosService {
  static final FirebaseFirestore db = FirebaseFirestore.instance;

  /// Descobre a loja atual. Prioridade: StoreResolver/LojaIdService → Hive (fallback offline).
  /// Nunca retorna loja fixa; lança StateError se não conseguir resolver.
  static Future<String> getLojaId() async {
    String? storeId = (await LojaIdService.get())?.trim();
    if (storeId != null && storeId.isNotEmpty) return storeId;

    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      storeId =
          (sessao.get('store_id') ?? sessao.get('storeId'))?.toString().trim();
      if (storeId != null && storeId.isNotEmpty) return storeId;
    } catch (_) {}

    try {
      final config = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      storeId = (config.get('store_id') ??
              config.get('store_slug') ??
              config.get('loja_slug'))
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

  /// Subconjunto seguro para catálogo público (sem tokens). Regras: leitura world-readable.
  /// /lojas/{lojaId}/config/payments_public
  static DocumentReference<Map<String, dynamic>> paymentsPublicDoc(
      String lojaId) {
    return db.doc('lojas/$lojaId/config/payments_public');
  }

  /// Remove segredos antes de expor em [payments_public].
  static Map<String, dynamic> stripSecretsFromPaymentsMap(
      Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    if (out['mp'] is Map) {
      final m = Map<String, dynamic>.from(out['mp'] as Map);
      m.remove('access_token');
      m.remove('token');
      m.remove('refresh_token');
      m.remove('webhook_secret');
      out['mp'] = m;
    }
    if (out['pagseguro'] is Map) {
      final p = Map<String, dynamic>.from(out['pagseguro'] as Map);
      p.remove('token');
      out['pagseguro'] = p;
    }
    if (out['ton'] is Map) {
      final t = Map<String, dynamic>.from(out['ton'] as Map);
      t.remove('client_secret');
      out['ton'] = t;
    }
    if (out['infinitpay'] is Map) {
      final i = Map<String, dynamic>.from(out['infinitpay'] as Map);
      i.remove('api_key');
      out['infinitpay'] = i;
    }
    return out;
  }

  /// Espelha [config/payments] sem segredos para [payments_public] (catálogo anônimo).
  static Future<void> syncPaymentsPublic(String lojaId) async {
    final snap = await paymentsDoc(lojaId).get();
    if (!snap.exists || snap.data() == null) {
      return;
    }
    await paymentsPublicDoc(lojaId).set(
      stripSecretsFromPaymentsMap(Map<String, dynamic>.from(snap.data()!)),
      SetOptions(merge: true),
    );
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
  ///
  /// Não grava [mp.public_key]: não confundir com chave pública pk_live.
  /// Limpeza de perfil (email/user_id/nickname) antes de trocar token fica a cargo do
  /// fluxo chamador (ex.: [limparPerfilMp] + helper manual) para evitar janela incoerente.
  /// [catalogTokenValidated] deve ser true apenas quando o token foi validado contra a API MP
  /// (fluxo manual com sucesso remoto). OAuth usa o callback Cloud e não este método.
  static Future<void> salvarAccessToken(
    String lojaId,
    String accessToken, {
    bool? catalogTokenValidated,
  }) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': PagamentosMpFirestoreWrites.manualAccessToken(
          accessToken,
          catalogTokenValidated: catalogTokenValidated,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await syncPaymentsPublic(lojaId);
  }

  /// Remove apenas dados de exibição da conta MP em [mp] (antes de persistir novo token).
  static Future<void> limparPerfilMp(String lojaId) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': PagamentosMpFirestoreWrites.clearIdentityFields(),
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
    await syncPaymentsPublic(lojaId);
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
    await syncPaymentsPublic(lojaId);
  }

  /// Janela em que novos cliques em "Conectar" são ignorados (evita abas/states paralelos).
  static const Duration oauthAberturaCooldown = Duration(seconds: 5);
  static DateTime? _ultimaAberturaOAuth;

  @visibleForTesting
  static Future<bool> Function(Uri url) oauthPageLauncher =
      (url) => launchUrl(url, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static void resetOAuthAberturaCooldown() => _ultimaAberturaOAuth = null;

  /// Abre `/mp-oauth-start` (página web que exige sessão e pede o state ao servidor).
  /// O lojaId é só o pedido; quem decide se o utilizador administra a loja é o backend.
  /// Devolve false quando o clique é ignorado por repetição.
  static Future<bool> abrirConexaoOAuth(String lojaId) async {
    final agora = DateTime.now();
    final ultima = _ultimaAberturaOAuth;
    if (ultima != null && agora.difference(ultima) < oauthAberturaCooldown) {
      return false;
    }
    _ultimaAberturaOAuth = agora;
    final uri = Uri.parse(
      '${AppUrls.appWebBase}/mp-oauth-start?lojaId=${Uri.encodeComponent(lojaId)}',
    );
    var aberto = false;
    try {
      aberto = await oauthPageLauncher(uri);
    } finally {
      if (!aberto) _ultimaAberturaOAuth = null;
    }
    if (!aberto) {
      throw Exception(
        'Não foi possível abrir a página de conexão do Mercado Pago.',
      );
    }
    return true;
  }

  /// Desconecta a conta MP da loja (limpa os campos no Firestore)
  /// em /lojas/{lojaId}/config/payments
  static Future<void> desconectarLoja(String lojaId) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': PagamentosMpFirestoreWrites.disconnect(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await syncPaymentsPublic(lojaId);
  }

  /// Pede ao servidor um state OAuth vinculado ao utilizador autenticado e à loja.
  /// Devolve a URL de autorização do Mercado Pago.
  static Future<String> criarAutorizacaoOAuth(String lojaId) async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final result = await functions
        .httpsCallable('mpOAuthStart')
        .call(<String, dynamic>{'lojaId': lojaId});
    final data = result.data;
    final authUrl = data is Map ? (data['authUrl'] ?? '').toString() : '';
    if (!authUrl.startsWith('https://auth.mercadopago.com/')) {
      throw Exception('Resposta inválida do servidor.');
    }
    return authUrl;
  }

  /// Troca `code`/`state` no backend. Exige sessão Firebase do mesmo utilizador que iniciou a conexão.
  /// O state é opaco: só é reenviado tal como veio do Mercado Pago.
  static Future<void> finalizarOAuthNoBackend({
    required String code,
    required String state,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const MpOAuthExchangeException(
          401, 'Faça login para concluir a conexão.');
    }
    final idToken = await user.getIdToken();
    final uri = kIsWeb
        ? Uri.base.resolve('/api/mp/oauth/callback')
        : Uri.parse('${AppUrls.appWebBase}/api/mp/oauth/callback');

    final http.Response resp;
    try {
      resp = await HttpClientHelper.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'code': code, 'state': state}),
        timeout: HttpTimeouts.cloudFunction,
      );
    } catch (_) {
      throw const MpOAuthExchangeException(null, 'Sem resposta do servidor.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Falha ao concluir a conexão (${resp.statusCode}).';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'].toString();
        }
      } catch (_) {}
      throw MpOAuthExchangeException(resp.statusCode, msg);
    }
  }

  /// Healthcheck server-side do token OAuth MP salvo na loja.
  /// Retorna apenas dados seguros para UI (sem token).
  static Future<Map<String, dynamic>> validarConexaoMercadoPago({
    required String lojaId,
  }) async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('mpOAuthHealthcheck');
    final result = await callable.call(<String, dynamic>{
      'lojaId': lojaId,
    });
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{
      'ok': false,
      'connected': false,
      'message': 'Resposta inválida do servidor.',
    };
  }
}
