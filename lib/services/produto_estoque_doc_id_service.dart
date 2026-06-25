// Identificador canônico de `estoque_produtos` — evita reutilizar doc tombstonado no cadastro.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/firestore_access_guard.dart';
import 'firestore_paths.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produtos_firestore_service.dart';

/// Resolve `slug` / `idFirebase` seguros para produto **novo** (cadastro).
class ProdutoEstoqueDocIdService {
  ProdutoEstoqueDocIdService._();

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: ProdutosFirestoreService.debugFirestoreOverride,
      );

  /// Mesma regra de [gerarSlug] em `produto_form_screen.dart`.
  @visibleForTesting
  static String slugPartFromNome(String nome) {
    return nome
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Padrão do app: `{lojaId}-{slugNome}`.
  static String slugCanonicoParaLoja({
    required String lojaId,
    required String nome,
  }) {
    final li = lojaId.trim();
    final part = slugPartFromNome(nome);
    return part.isEmpty ? li : '$li-$part';
  }

  /// `true` se o doc não pode ser usado para um produto novo (tombstone ou já existe).
  static Future<bool> docIdIndisponivelParaNovoProduto({
    required String lojaId,
    required String docId,
  }) async {
    final id = docId.trim();
    final l = lojaId.trim();
    if (l.isEmpty || id.isEmpty) return true;

    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(l);
    if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
      lojaId: l,
      estoqueDocId: id,
    )) {
      return true;
    }

    final col =
        _db.collection('lojas').doc(l).collection(FSPaths.estoqueProdutosCol);
    return (await col.doc(id).get()).exists;
  }

  /// Escolhe o primeiro id livre: base, base-2, base-3, …
  static Future<String> resolverDocIdSeguroNovoProduto({
    required String lojaId,
    required String nome,
  }) async {
    final base = slugCanonicoParaLoja(lojaId: lojaId, nome: nome);
    if (!await docIdIndisponivelParaNovoProduto(lojaId: lojaId, docId: base)) {
      return base;
    }

    for (var n = 2; n <= 99; n++) {
      final candidato = '$base-$n';
      if (!await docIdIndisponivelParaNovoProduto(
        lojaId: lojaId,
        docId: candidato,
      )) {
        if (kDebugMode) {
          debugPrint(
            '[PRODUTO_DOC_ID] id base "$base" indisponível (tombstone ou doc existente) → "$candidato"',
          );
        }
        return candidato;
      }
    }

    throw Exception(
      'Não foi possível gerar um identificador único para este produto. '
      'Tente um nome diferente.',
    );
  }
}
