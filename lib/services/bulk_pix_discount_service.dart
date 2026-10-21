import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/produto.dart';
import 'produto_remote_sync_guard.dart';
import 'stock_catalog_backend_service.dart';

/// Mirrors server `MAX_PRODUCTS_PER_BULK_PIX_OPERATION`.
const int kMaxProdutosPorOperacaoPix = 30;

String _produtos(int n) => n == 1 ? '1 produto' : '$n produtos';

class BulkPixCandidato {
  const BulkPixCandidato({
    required this.hiveKey,
    required this.docId,
    required this.nome,
    required this.percentualDescontoPix,
  });

  factory BulkPixCandidato.fromProduto(int hiveKey, Produto p) {
    final id = p.idFirebase.trim();
    return BulkPixCandidato(
      hiveKey: hiveKey,
      docId: id.isNotEmpty ? id : p.slug.trim(),
      nome: p.nome,
      percentualDescontoPix: p.percentualDescontoPix,
    );
  }

  final int hiveKey;

  /// Same document id used for `estoque_produtos`; empty when never synced.
  final String docId;
  final String nome;
  final double percentualDescontoPix;

  bool get temDescontoPix => percentualDescontoPix > 0;
}

/// Pre-write summary computed from the products the merchant sees; the server result is authoritative.
class BulkPixPreview {
  BulkPixPreview._({
    required this.selecionados,
    required this.comDescontoPix,
    required this.semDescontoPix,
    required this.naoSincronizados,
    required this.foraDoFiltro,
    required this.docIds,
  });

  factory BulkPixPreview.calcular(
    List<BulkPixCandidato> candidatos, {
    int foraDoFiltro = 0,
  }) {
    var com = 0, sem = 0, naoSync = 0;
    final ids = <String>{};
    for (final c in candidatos) {
      if (c.docId.isEmpty) {
        naoSync++;
        continue;
      }
      ids.add(c.docId);
      if (c.temDescontoPix) {
        com++;
      } else {
        sem++;
      }
    }
    return BulkPixPreview._(
      selecionados: candidatos.length,
      comDescontoPix: com,
      semDescontoPix: sem,
      naoSincronizados: naoSync,
      foraDoFiltro: foraDoFiltro,
      docIds: ids.toList()..sort(),
    );
  }

  final int selecionados;
  final int comDescontoPix;
  final int semDescontoPix;
  final int naoSincronizados;
  final int foraDoFiltro;
  final List<String> docIds;

  String get titulo => 'Remover desconto no Pix de ${_produtos(selecionados)}?';

  List<String> get linhas => [
        if (comDescontoPix > 0)
          comDescontoPix == 1
              ? '1 produto terá o desconto no Pix removido.'
              : '$comDescontoPix produtos terão o desconto no Pix removido.',
        if (semDescontoPix > 0)
          semDescontoPix == 1
              ? '1 já está sem desconto e não será alterado.'
              : '$semDescontoPix já estão sem desconto e não serão alterados.',
        if (naoSincronizados > 0)
          '${_produtos(naoSincronizados)} ainda não '
              '${naoSincronizados == 1 ? 'foi sincronizado' : 'foram sincronizados'} '
              'com a nuvem e ${naoSincronizados == 1 ? 'será ignorado' : 'serão ignorados'}.',
        if (foraDoFiltro > 0)
          'Atenção: ${_produtos(foraDoFiltro)} '
              '${foraDoFiltro == 1 ? 'selecionado não aparece' : 'selecionados não aparecem'} '
              'no filtro atual e também ${foraDoFiltro == 1 ? 'será incluído' : 'serão incluídos'}.',
        'O preço normal, o estoque, as categorias, as variações e as promoções não mudam.',
      ];

  bool get podeExecutar => docIds.isNotEmpty;
}

class BulkPixFalhaLote {
  const BulkPixFalhaLote({
    required this.productIds,
    required this.mensagem,
    this.productIdIndisponivel,
  });

  final List<String> productIds;
  final String mensagem;

  /// Product that made the server reject the whole batch (missing or deleted).
  final String? productIdIndisponivel;
}

class BulkPixResultado {
  BulkPixResultado({
    required this.solicitados,
    required this.atualizados,
    required this.semAlteracao,
    required this.falhas,
  });

  final int solicitados;
  final Set<String> atualizados;
  final Set<String> semAlteracao;
  final List<BulkPixFalhaLote> falhas;

  int get produtosComFalha =>
      falhas.fold(0, (n, f) => n + f.productIds.length);
  bool get sucessoTotal => falhas.isEmpty;

  /// Failed batches minus the product the server reported as unavailable.
  List<String> get idsParaNovaTentativa => falhas
      .expand((f) => f.productIds.where((id) => id != f.productIdIndisponivel))
      .toSet()
      .toList()
    ..sort();

  String get titulo => sucessoTotal
      ? 'Desconto no Pix removido'
      : (atualizados.isEmpty && semAlteracao.isEmpty
          ? 'Desconto no Pix não removido'
          : 'Desconto no Pix removido em parte');

  List<String> get linhas => [
        atualizados.length == 1
            ? '1 produto atualizado'
            : '${atualizados.length} produtos atualizados',
        semAlteracao.length == 1
            ? '1 já estava sem desconto'
            : '${semAlteracao.length} já estavam sem desconto',
        produtosComFalha == 1 ? '1 falha' : '$produtosComFalha falhas',
      ];
}

class BulkPixDiscountService {
  BulkPixDiscountService._();

  static String novoBulkId() => 'pixbulk_${const Uuid().v4()}';

  static List<List<String>> lotes(
    Iterable<String> docIds, {
    int tamanho = kMaxProdutosPorOperacaoPix,
  }) {
    final ids = docIds.toSet().toList()..sort();
    return [
      for (var i = 0; i < ids.length; i += tamanho)
        ids.sublist(i, i + tamanho > ids.length ? ids.length : i + tamanho),
    ];
  }

  /// Same store + bulk + batch contents => same id, so a retried batch replays on the server.
  static String operationId({
    required String lojaId,
    required String bulkId,
    required List<String> productIds,
  }) {
    final ids = [...productIds]..sort();
    final digest = sha256.convert(utf8.encode('$lojaId|$bulkId|${ids.join(',')}'));
    return 'pixrm_$digest';
  }

  static Future<BulkPixResultado> executar({
    required String lojaId,
    required List<String> docIds,
    required String bulkId,
    Map<String, String> nomes = const {},
    void Function(int processados, int total)? onProgresso,
  }) async {
    final batches = lotes(docIds);
    final total = batches.fold<int>(0, (n, b) => n + b.length);
    final atualizados = <String>{};
    final semAlteracao = <String>{};
    final falhas = <BulkPixFalhaLote>[];
    var processados = 0;
    onProgresso?.call(0, total);
    for (final batch in batches) {
      try {
        final result = await StockCatalogBackendService.removePixDiscount(
          lojaId: lojaId,
          operationId: operationId(
              lojaId: lojaId, bulkId: bulkId, productIds: batch),
          productIds: batch,
          bulkId: bulkId,
        );
        atualizados.addAll(_ids(result['updatedProductIds']));
        semAlteracao.addAll(_ids(result['noopProductIds']));
      } catch (error) {
        falhas.add(BulkPixFalhaLote(
          productIds: batch,
          mensagem: mensagemErro(error, nomes: nomes),
          productIdIndisponivel: _produtoIndisponivel(error),
        ));
      }
      processados += batch.length;
      onProgresso?.call(processados, total);
    }
    return BulkPixResultado(
      solicitados: total,
      atualizados: atualizados,
      semAlteracao: semAlteracao,
      falhas: falhas,
    );
  }

  static List<String> _ids(Object? raw) =>
      raw is List ? raw.map((e) => e.toString()).toList() : const [];

  static Map<dynamic, dynamic> _details(Object error) {
    if (error is! FirebaseFunctionsException) return const {};
    final d = error.details;
    return d is Map ? d : const {};
  }

  static String? _produtoIndisponivel(Object error) {
    final d = _details(error);
    if ('${d['code'] ?? ''}' != 'BULK_PIX_PRODUCT_UNAVAILABLE') return null;
    final id = '${d['productId'] ?? ''}'.trim();
    return id.isEmpty ? null : id;
  }

  static String mensagemErro(Object error, {Map<String, String> nomes = const {}}) {
    const nada = 'Nenhum produto deste lote foi alterado.';
    if (error is! FirebaseFunctionsException) {
      return 'Não foi possível concluir este lote. $nada';
    }
    final d = _details(error);
    final code = '${d['code'] ?? ''}';
    final productId = '${d['productId'] ?? ''}';
    final nome = nomes[productId] ?? productId;
    if (code == 'BULK_PIX_PRODUCT_UNAVAILABLE') {
      return d['reason'] == 'DELETED'
          ? '"$nome" foi excluído. $nada'
          : '"$nome" não foi encontrado na nuvem. $nada';
    }
    if (code == 'OPERATION_PAYLOAD_CONFLICT') {
      return 'Este lote já foi registrado com outros dados. $nada';
    }
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return 'Você não tem permissão para alterar produtos desta loja. $nada';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        return 'Falha de conexão: o lote não foi confirmado. '
            'Tentar novamente é seguro.';
      case 'invalid-argument':
        final msg = error.message ?? '';
        if (msg.contains('Unsupported command') ||
            msg.contains('Unknown or protected command field')) {
          return 'O servidor ainda não oferece esta ação. $nada';
        }
        return 'Não foi possível concluir este lote. $nada';
      case 'failed-precondition':
        return 'Esta loja não permite esta alteração no momento. $nada';
    }
    return 'Não foi possível concluir este lote. $nada';
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
          if (p == null || p.percentualDescontoPix == 0) continue;
          p.percentualDescontoPix = 0;
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
