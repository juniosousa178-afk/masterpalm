import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import 'produto_promocao.dart';
import 'produto_remote_sync_guard.dart';
import 'stock_catalog_backend_service.dart';

String _produtos(int n) => n == 1 ? '1 produto' : '$n produtos';

class BulkPromoCandidato {
  const BulkPromoCandidato({
    required this.hiveKey,
    required this.docId,
    required this.nome,
    required this.lojaId,
    required this.emPromocao,
  });

  factory BulkPromoCandidato.fromProduto(int hiveKey, Produto p) {
    final id = p.idFirebase.trim();
    return BulkPromoCandidato(
      hiveKey: hiveKey,
      docId: id.isNotEmpty ? id : p.slug.trim(),
      nome: p.nome,
      lojaId: p.lojaId.trim(),
      emPromocao: ProdutoPromocao.temPromocao(p),
    );
  }

  final int hiveKey;

  /// Same document id used for `estoque_produtos`; empty when never synced.
  final String docId;
  final String nome;

  /// Store recorded on the product; empty on legacy records (the per-store box is the boundary).
  final String lojaId;
  final bool emPromocao;
}

/// Pre-write summary computed from the products the merchant sees.
class BulkPromoPreview {
  BulkPromoPreview._({
    required this.selecionados,
    required this.comPromocao,
    required this.semPromocao,
    required this.naoSincronizados,
    required this.foraDoFiltro,
    required this.docIds,
  });

  factory BulkPromoPreview.calcular(
    List<BulkPromoCandidato> candidatos, {
    int foraDoFiltro = 0,
  }) {
    var sem = 0, naoSync = 0;
    final ids = <String>{};
    for (final c in candidatos) {
      if (!c.emPromocao) {
        sem++;
      } else if (c.docId.isEmpty) {
        naoSync++;
      } else {
        ids.add(c.docId);
      }
    }
    return BulkPromoPreview._(
      selecionados: candidatos.length,
      comPromocao: ids.length,
      semPromocao: sem,
      naoSincronizados: naoSync,
      foraDoFiltro: foraDoFiltro,
      docIds: ids.toList()..sort(),
    );
  }

  final int selecionados;
  final int comPromocao;
  final int semPromocao;
  final int naoSincronizados;
  final int foraDoFiltro;

  /// Only products that currently have a promotion; the others are never sent.
  final List<String> docIds;

  String get titulo => 'Desativar a promoção de ${_produtos(selecionados)}?';

  List<String> get linhas => [
        if (comPromocao > 0)
          comPromocao == 1
              ? '1 produto terá a promoção desativada.'
              : '$comPromocao produtos terão a promoção desativada.',
        if (semPromocao > 0)
          semPromocao == 1
              ? '1 já está sem promoção e não será alterado.'
              : '$semPromocao já estão sem promoção e não serão alterados.',
        if (naoSincronizados > 0)
          '${_produtos(naoSincronizados)} ainda não '
              '${naoSincronizados == 1 ? 'foi sincronizado' : 'foram sincronizados'} '
              'com a nuvem e ${naoSincronizados == 1 ? 'será ignorado' : 'serão ignorados'}.',
        if (foraDoFiltro > 0)
          'Atenção: ${_produtos(foraDoFiltro)} '
              '${foraDoFiltro == 1 ? 'selecionado não aparece' : 'selecionados não aparecem'} '
              'no filtro atual e também ${foraDoFiltro == 1 ? 'será incluído' : 'serão incluídos'}.',
        'O preço normal será mantido.',
        'O estoque não será alterado.',
        'Nenhum produto será excluído.',
      ];

  bool get podeExecutar => docIds.isNotEmpty;
}

class BulkPromoFalha {
  const BulkPromoFalha({
    required this.docId,
    required this.mensagem,
    required this.podeTentarDeNovo,
  });

  final String docId;
  final String mensagem;

  /// False when retrying cannot succeed (product deleted, missing, no permission).
  final bool podeTentarDeNovo;
}

class BulkPromoResultado {
  BulkPromoResultado({
    required this.desativados,
    required this.jaSemPromocao,
    required this.falhas,
  });

  final Set<String> desativados;
  final int jaSemPromocao;
  final List<BulkPromoFalha> falhas;

  bool get sucessoTotal => falhas.isEmpty;

  List<String> get idsParaNovaTentativa =>
      (falhas.where((f) => f.podeTentarDeNovo).map((f) => f.docId).toSet().toList())..sort();

  String get titulo => sucessoTotal
      ? 'Promoções desativadas'
      : (desativados.isEmpty ? 'Promoções não desativadas' : 'Promoções desativadas em parte');

  List<String> get linhas => [
        desativados.length == 1
            ? '1 promoção desativada'
            : '${desativados.length} promoções desativadas',
        jaSemPromocao == 1 ? '1 já estava sem promoção' : '$jaSemPromocao já estavam sem promoção',
        falhas.length == 1 ? '1 falhou' : '${falhas.length} falharam',
      ];

  String get mensagemSucesso {
    final base = desativados.length == 1
        ? '1 promoção desativada com sucesso.'
        : '${desativados.length} promoções desativadas com sucesso.';
    if (jaSemPromocao == 0) return base;
    return '$base ${jaSemPromocao == 1 ? '1 já estava' : '$jaSemPromocao já estavam'} sem promoção.';
  }
}

class BulkPromocaoService {
  BulkPromocaoService._();

  static String novoBulkId() => 'promobulk_${const Uuid().v4()}';

  /// Same store + bulk + product => same id, so a retried product replays on the server.
  static String operationId({
    required String lojaId,
    required String bulkId,
    required String docId,
  }) {
    final digest = sha256.convert(utf8.encode('$lojaId|$bulkId|$docId'));
    return 'promooff_$digest';
  }

  /// Fail-closed tenant check; returns the reason to abort, or null when every
  /// selected product belongs to the store open on screen.
  static String? validarLoja({
    required String lojaIdAtual,
    required String lojaIdTela,
    required String nomeBox,
    required Iterable<BulkPromoCandidato> candidatos,
  }) {
    const nada = 'Nenhuma alteração foi feita.';
    final atual = lojaIdAtual.trim();
    final tela = lojaIdTela.trim();
    if (atual.isEmpty || tela.isEmpty) return 'Loja não identificada. $nada';
    if (atual != tela) {
      return 'A loja ativa mudou desde que a lista foi aberta. Abra o estoque novamente. $nada';
    }
    if (nomeBox.toLowerCase() != HiveBoxNames.produtos(tela).toLowerCase()) {
      return 'A lista aberta não pertence à loja ativa. Abra o estoque novamente. $nada';
    }
    for (final c in candidatos) {
      if (c.lojaId.isNotEmpty && c.lojaId != tela) {
        return '"${c.nome}" pertence a outra loja. $nada';
      }
    }
    return null;
  }

  /// One editorial command per product (the server accepts a single product per
  /// editorial command), sent sequentially; a failure never stops the others.
  static Future<BulkPromoResultado> executar({
    required String lojaId,
    required List<String> docIds,
    required String bulkId,
    int jaSemPromocao = 0,
    Map<String, String> nomes = const {},
    void Function(int processados, int total)? onProgresso,
  }) async {
    final ids = docIds.toSet().toList()..sort();
    final desativados = <String>{};
    final falhas = <BulkPromoFalha>[];
    onProgresso?.call(0, ids.length);
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      try {
        await StockCatalogBackendService.command(
          lojaId: lojaId,
          operationId: operationId(lojaId: lojaId, bulkId: bulkId, docId: id),
          kind: 'editorial',
          items: [
            {'productId': id}
          ],
          editorial: ProdutoPromocao.camposDesativacao,
        );
        desativados.add(id);
      } catch (error) {
        falhas.add(BulkPromoFalha(
          docId: id,
          mensagem: mensagemErro(error, nome: nomes[id] ?? id),
          podeTentarDeNovo: podeTentarDeNovo(error),
        ));
      }
      onProgresso?.call(i + 1, ids.length);
    }
    return BulkPromoResultado(
      desativados: desativados,
      jaSemPromocao: jaSemPromocao,
      falhas: falhas,
    );
  }

  static bool _produtoAusente(FirebaseFunctionsException e) =>
      e.code == 'failed-precondition' && (e.message ?? '').startsWith('Canonical product');

  static bool _produtoExcluido(FirebaseFunctionsException e) =>
      e.code == 'failed-precondition' && (e.message ?? '').contains('tombstone');

  static bool podeTentarDeNovo(Object error) {
    if (error is StockCatalogProductValidationException) return false;
    if (error is! FirebaseFunctionsException) return true;
    return !{'permission-denied', 'unauthenticated', 'failed-precondition', 'invalid-argument', 'not-found'}
        .contains(error.code);
  }

  static String mensagemErro(Object error, {required String nome}) {
    final nada = '"$nome" não foi alterado.';
    if (error is StockCatalogProductValidationException) {
      return '"$nome" tem dados que precisam ser revisados no cadastro. $nada';
    }
    if (error is! FirebaseFunctionsException) {
      return 'Não foi possível desativar a promoção de "$nome". Tentar novamente é seguro.';
    }
    if (_produtoExcluido(error)) return '"$nome" foi excluído. $nada';
    if (_produtoAusente(error)) return '"$nome" não foi encontrado na nuvem. $nada';
    final d = error.details;
    if (d is Map && '${d['code'] ?? ''}' == 'OPERATION_PAYLOAD_CONFLICT') {
      return 'Esta operação já foi registrada com outros dados. $nada';
    }
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return 'Você não tem permissão para alterar produtos desta loja. $nada';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        return 'Falha de conexão ao desativar "$nome": não confirmado. Tentar novamente é seguro.';
      case 'failed-precondition':
        return 'Esta loja não permite alterar "$nome" no momento. $nada';
    }
    return 'Não foi possível desativar a promoção de "$nome". $nada';
  }

  /// Mirrors the server outcome in Hive without triggering the full-document auto-sync push.
  static Future<int> aplicarNoHive({
    required Box<Produto> box,
    required Map<String, List<int>> hiveKeysPorDocId,
    required Iterable<String> docIds,
  }) async {
    var n = 0;
    ProdutoRemoteSyncGuard.applyingRemoteToHive = true;
    try {
      for (final id in docIds) {
        for (final key in hiveKeysPorDocId[id] ?? const <int>[]) {
          final p = box.get(key);
          if (p == null || !ProdutoPromocao.desativar(p)) continue;
          await p.save();
          n++;
        }
      }
    } finally {
      ProdutoRemoteSyncGuard.applyingRemoteToHive = false;
    }
    return n;
  }
}
