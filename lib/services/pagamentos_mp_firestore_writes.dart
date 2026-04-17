// lib/services/pagamentos_mp_firestore_writes.dart
//
// Blocos de merge em `lojas/{id}/config/payments` → campo `mp`.
// Separado para testes e para documentar semântica sem duplicar FieldValue no serviço.
import 'package:cloud_firestore/cloud_firestore.dart';

abstract final class PagamentosMpFirestoreWrites {
  /// Credenciais manuais (access token): não grava public_key (evita confundir com pk_live).
  /// Remove refresh_token legado de OAuth ao colar token manual.
  static Map<String, dynamic> manualAccessToken(String accessToken) {
    return {
      'access_token': accessToken,
      'token': accessToken,
      'connected': true,
      'refresh_token': FieldValue.delete(),
    };
  }

  /// Remove e-mail / ids de exibição antes de trocar o token (evita conta antiga com token novo).
  static Map<String, dynamic> clearIdentityFields() {
    return {
      'email': FieldValue.delete(),
      'user_id': FieldValue.delete(),
      'nickname': FieldValue.delete(),
    };
  }

  /// Desconectar: sem credenciais sensíveis; connected coerente.
  static Map<String, dynamic> disconnect() {
    return {
      'connected': false,
      'access_token': FieldValue.delete(),
      'token': FieldValue.delete(),
      'refresh_token': FieldValue.delete(),
      'email': FieldValue.delete(),
      'user_id': FieldValue.delete(),
      'nickname': FieldValue.delete(),
      'public_key': FieldValue.delete(),
      'access_token_hint': FieldValue.delete(),
    };
  }
}
