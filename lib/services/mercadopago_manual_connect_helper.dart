// lib/services/mercadopago_manual_connect_helper.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'mercadopago_service.dart';
import 'pagamentos_service.dart';

/// Resultado do fluxo manual de colar Access Token (sem OAuth).
class MercadoPagoManualConnectResult {
  const MercadoPagoManualConnectResult({
    required this.success,
    this.invalidToken = false,
    this.errorMessage,
    required this.normalizedToken,
    this.tokenPersisted = false,
    required this.remoteValidationOk,
    this.continuedViaWebHeuristic = false,
    this.profileMerged = false,
    this.profileEmail,
  });

  final bool success;
  final bool invalidToken;
  final String? errorMessage;
  final String normalizedToken;
  final bool tokenPersisted;
  final bool remoteValidationOk;
  final bool continuedViaWebHeuristic;
  final bool profileMerged;
  final String? profileEmail;
}

/// Dependências do fluxo (permite testes sem Firestore/HTTP reais).
class MercadoPagoManualConnectDeps {
  const MercadoPagoManualConnectDeps({
    required this.validateRemote,
    required this.fetchProfile,
    required this.clearMpIdentityBeforeToken,
    required this.persistAccessToken,
    required this.mergeMpProfile,
  });

  final Future<bool> Function(String accessToken) validateRemote;
  final Future<Map<String, dynamic>?> Function(String accessToken) fetchProfile;

  /// Evita perfil antigo com access token novo (chamar antes de [persistAccessToken]).
  final Future<void> Function(String lojaId) clearMpIdentityBeforeToken;
  final Future<void> Function(
    String lojaId,
    String accessToken, {
    bool? catalogTokenValidated,
  }) persistAccessToken;
  final Future<void> Function(String lojaId, Map<String, dynamic> info)
      mergeMpProfile;

  static MercadoPagoManualConnectDeps live() {
    return MercadoPagoManualConnectDeps(
      validateRemote: (t) =>
          MercadoPagoService.validarCredenciais(accessToken: t),
      fetchProfile: (t) => MercadoPagoService.obterInfoConta(accessToken: t),
      clearMpIdentityBeforeToken: PagamentosService.limparPerfilMp,
      persistAccessToken: (lojaId, token, {catalogTokenValidated}) =>
          PagamentosService.salvarAccessToken(
        lojaId,
        token,
        catalogTokenValidated: catalogTokenValidated,
      ),
      mergeMpProfile: (lojaId, info) async {
        await PagamentosService.paymentsDoc(lojaId).set({
          'mp': {
            'email': info['email'],
            'user_id': info['id']?.toString(),
            'nickname': info['nickname'],
          },
        }, SetOptions(merge: true));
        await PagamentosService.syncPaymentsPublic(lojaId);
      },
    );
  }
}

/// Conecta MP colando token: valida (com mesma regra web da tela simples), persiste token e perfil quando [users/me] retorna dados.
class MercadoPagoManualConnectHelper {
  MercadoPagoManualConnectHelper._();

  static Future<MercadoPagoManualConnectResult> connect({
    required String lojaId,
    required String rawToken,
    MercadoPagoManualConnectDeps? deps,
  }) async {
    final d = deps ?? MercadoPagoManualConnectDeps.live();
    final token = MercadoPagoService.normalizarAccessToken(rawToken);
    if (token.isEmpty) {
      return MercadoPagoManualConnectResult(
        success: false,
        invalidToken: true,
        normalizedToken: '',
        remoteValidationOk: false,
      );
    }

    try {
      final remoteOk = await d.validateRemote(token);
      var continuedViaWeb = false;
      if (!remoteOk) {
        final formatoValido =
            MercadoPagoService.pareceAccessTokenProducao(token);
        final podeWeb = kIsWeb && formatoValido;
        if (podeWeb) {
          continuedViaWeb = true;
          debugPrint(
            '[MP] Web: validação remota falhou; seguindo por formato do token (APP_USR).',
          );
        } else {
          return MercadoPagoManualConnectResult(
            success: false,
            invalidToken: true,
            normalizedToken: token,
            remoteValidationOk: false,
            continuedViaWebHeuristic: false,
          );
        }
      }

      final info = await d.fetchProfile(token);
      await d.clearMpIdentityBeforeToken(lojaId);
      final validatedForCatalog = remoteOk && !continuedViaWeb;
      await d.persistAccessToken(
        lojaId,
        token,
        catalogTokenValidated: validatedForCatalog,
      );

      var profileMerged = false;
      String? profileEmail;
      if (info != null) {
        await d.mergeMpProfile(lojaId, info);
        profileMerged = true;
        profileEmail = info['email']?.toString();
      }

      return MercadoPagoManualConnectResult(
        success: true,
        normalizedToken: token,
        tokenPersisted: true,
        remoteValidationOk: remoteOk,
        continuedViaWebHeuristic: continuedViaWeb,
        profileMerged: profileMerged,
        profileEmail: profileEmail,
      );
    } catch (e) {
      return MercadoPagoManualConnectResult(
        success: false,
        errorMessage: e.toString(),
        normalizedToken: token,
        remoteValidationOk: false,
      );
    }
  }

  /// Mensagem curta para SnackBar (sem expor token).
  static String snackbarMessage(MercadoPagoManualConnectResult r) {
    if (!r.success) return '';
    if (r.profileEmail != null && r.profileEmail!.isNotEmpty) {
      return 'Mercado Pago conectado! ${r.profileEmail}';
    }
    if (r.continuedViaWebHeuristic && !r.profileMerged) {
      return 'Token salvo. Não foi possível carregar o perfil da conta neste navegador; '
          'o pagamento pode funcionar normalmente.';
    }
    return 'Mercado Pago conectado!';
  }
}
