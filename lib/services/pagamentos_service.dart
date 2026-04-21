// lib/services/pagamentos_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import 'loja_id_service.dart';
import 'pagamentos_mp_firestore_writes.dart';
import '../utils/http_client_helper.dart';

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
  static Future<void> salvarAccessToken(
    String lojaId,
    String accessToken,
  ) async {
    await paymentsDoc(lojaId).set(
      {
        'mp': PagamentosMpFirestoreWrites.manualAccessToken(accessToken),
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
        'mp': PagamentosMpFirestoreWrites.disconnect(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await syncPaymentsPublic(lojaId);
  }

  /// (Opcional) Exemplo de chamada ao backend para trocar código por tokens.
  /// Use quando seu fluxo OAuth retornar `code`/`state` para o seu backend.
  static Future<void> finalizarOAuthNoBackend({
    required String code,
    required String state,
  }) async {
    final uri = Uri.parse('https://app.mastepalm.com.br/api/mp/oauth/callback');

    final resp = await HttpClientHelper.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'state': state}),
      timeout: HttpTimeouts.cloudFunction,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Falha ao finalizar OAuth no backend (${resp.statusCode}).';
      try {
        final data = jsonDecode(resp.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'].toString();
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }
}
