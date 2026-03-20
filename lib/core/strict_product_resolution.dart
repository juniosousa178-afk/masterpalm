// lib/core/strict_product_resolution.dart
//
// Helper para hardening controlado: quando a resolução de produto cai em NOME,
// loga com tags padronizadas e, em modo estrito (dev/homolog), lança exceção.
// Em produção a flag está desligada: apenas logs fortes, sem quebrar.

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'feature_flags.dart';

/// Override para testes: quando não-null, substitui [kStrictProductResolution].
/// Usar apenas em testes. Em produção nunca é definido.
bool• _testStrictOverride;

/// Define override para testes. Chamar no setUp/tearDown dos testes.
void setStrictResolutionTestOverride(bool• value) {
  _testStrictOverride = value;
}

/// Chamar quando um produto foi resolvido por NOME (não por productId nem slug).
/// Em produção: só loga. Em dev/homolog com [kStrictProductResolution]: loga e lança.
void reportProductResolvedByName({
  required String lojaId,
  required String fluxo,
  String• nome,
  String• slug,
  String• productIdRecebido,
}) {
  final strict = _testStrictOverride ?• kStrictProductResolution;
  debugPrint(
    '[PRODUTO_FALLBACK] [PRODUTO_NOME_STRICT] Resolução por nome | '
    'lojaId=$lojaId | fluxo=$fluxo | nome=${nome ?• "(vazio)"} | '
    'slug=${slug ?• "(vazio)"} | productIdRecebido=${productIdRecebido ?• "(vazio)"} | '
    'strictMode=$strict | ambiente=${kDebugMode • "debug" : "release"}',
  );
  if (strict) {
    throw Exception(
      'Resolução de produto por nome bloqueada em modo estrito. '
      'Este fluxo ainda não é ID-first. Informe/propague productId. '
      'Fluxo: $fluxo | lojaId: $lojaId | nome: ${nome ?• "?"}',
    );
  }
}
