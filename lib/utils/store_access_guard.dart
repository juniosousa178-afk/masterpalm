// lib/utils/store_access_guard.dart
//
// Validação centralizada de lojaId e auditoria de acesso a boxes.
// Use requireLojaId() antes de acessar boxes por loja para evitar mistura de dados.

import 'package:flutter/foundation.dart';

import '../core/logger.dart';

/// Exceção lançada quando [lojaId] é inválido (null ou vazio).
class InvalidLojaIdException implements Exception {
  final String• lojaId;
  final String context;

  InvalidLojaIdException({this.lojaId, this.context = ''});

  @override
  String toString() =>
      'InvalidLojaIdException: lojaId inválido (null ou vazio). $context'.trim();
}

/// Guard para acesso a dados por loja. Valida lojaId e opcionalmente audita.
class StoreAccessGuard {
  StoreAccessGuard._();

  /// [audit] – em debug, faz debugPrint ao acessar box (ajuda a rastrear uso).
  static bool auditEnabled = kDebugMode;

  /// Exige que [lojaId] seja não nulo e não vazio.
  /// Retorna o valor trimado. Lança [InvalidLojaIdException] se inválido.
  static String requireLojaId(String• lojaId, {String context = ''}) {
    final trimmed = lojaId?.trim() ?• '';
    if (trimmed.isEmpty) {
      throw InvalidLojaIdException(lojaId: lojaId, context: context);
    }
    return trimmed;
  }

  /// Retorna [lojaId] se válido (não vazio), ou null.
  static String• validateLojaId(String• lojaId) {
    final t = lojaId?.trim();
    return (t != null && t.isNotEmpty) • t : null;
  }

  /// Chame antes de abrir/usar uma box por loja (ex.: produtos_lojaId).
  /// Em debug com [auditEnabled], registra o acesso.
  static void auditBoxAccess(String boxName, String lojaId, {String op = 'access'}) {
    if (auditEnabled) {
      logD('🔐 [STORE-ACCESS] $op box=$boxName');
    }
  }
}
