// lib/core/strict_product_resolution.dart
//
// Helper para hardening controlado: quando a resolução de produto cai em NOME,
// loga com tags padronizadas e, em modo estrito (dev/homolog), lança exceção.
// Em produção a flag está desligada: apenas logs fortes, sem quebrar.

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'feature_flags.dart';

/// Override para testes: quando não-null, substitui [kStrictProductResolution].
/// Usar apenas em testes. Em produção nunca é definido.
bool? _testStrictOverride;

/// Define override para testes. Chamar no setUp/tearDown dos testes.
void setStrictResolutionTestOverride(bool? value) {
  _testStrictOverride = value;
}

/// `productId` da linha de venda aponta para outro produto que o nome exibido?
bool productIdIncoerenteComNomeExibido({
  required String nomeProdutoResolvido,
  required String nomeExibido,
}) {
  final nProd = nomeProdutoResolvido.trim().toLowerCase();
  final nLinha = nomeExibido.trim().toLowerCase();
  if (nProd.isEmpty || nLinha.isEmpty) return false;
  return nProd != nLinha;
}

/// Precedência de identidade na linha de venda (edit-sale / combo).
///
/// ID da mesma loja é primário. Nome é metadado + fallback legado.
/// Rename (ID bate, nome da linha não existe noutro produto) mantém o ID.
/// Conflito Lavile (ID=A, nome único=B distinto) usa o candidato por nome.
enum ProdutoLinhaIdentityChoice {
  useIdCandidate,
  useNameCandidate,
  notFound,
}

bool produtoLinhaStableIdsIguais(String? a, String? b) {
  final xa = (a ?? '').trim();
  final xb = (b ?? '').trim();
  if (xa.isEmpty || xb.isEmpty) return false;
  return xa == xb;
}

ProdutoLinhaIdentityChoice decideProdutoLinhaIdentity({
  required bool hasIdCandidate,
  required bool hasNameCandidate,
  required bool idCandidateNameAgreesWithLine,
  required bool idAndNameAreSameProduct,
}) {
  if (hasIdCandidate) {
    if (idCandidateNameAgreesWithLine) {
      return ProdutoLinhaIdentityChoice.useIdCandidate;
    }
    if (!hasNameCandidate) {
      return ProdutoLinhaIdentityChoice.useIdCandidate;
    }
    if (idAndNameAreSameProduct) {
      return ProdutoLinhaIdentityChoice.useIdCandidate;
    }
    return ProdutoLinhaIdentityChoice.useNameCandidate;
  }
  if (hasNameCandidate) {
    return ProdutoLinhaIdentityChoice.useNameCandidate;
  }
  return ProdutoLinhaIdentityChoice.notFound;
}

/// Chamar quando um produto foi resolvido por NOME (não por productId nem slug).
/// Em produção: só loga. Em dev/homolog com [kStrictProductResolution]: loga e lança.
void reportProductResolvedByName({
  required String lojaId,
  required String fluxo,
  String? nome,
  String? slug,
  String? productIdRecebido,
}) {
  final strict = _testStrictOverride ?? kStrictProductResolution;
  debugPrint(
    '[PRODUTO_FALLBACK] [PRODUTO_NOME_STRICT] Resolução por nome | '
    'lojaId=$lojaId | fluxo=$fluxo | nome=${nome ?? "(vazio)"} | '
    'slug=${slug ?? "(vazio)"} | productIdRecebido=${productIdRecebido ?? "(vazio)"} | '
    'strictMode=$strict | ambiente=${kDebugMode ? "debug" : "release"}',
  );
  if (strict) {
    throw Exception(
      'Resolução de produto por nome bloqueada em modo estrito. '
      'Este fluxo ainda não é ID-first. Informe/propague productId. '
      'Fluxo: $fluxo | lojaId: $lojaId | nome: ${nome ?? "?"}',
    );
  }
}
