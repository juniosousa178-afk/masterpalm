// Classificação de intents replace obsoletas — puro / testável.
// Não envia comando; não repara remoto; não usa EPT como autoridade.

import 'produto_estoque_grade_snapshot.dart';
import 'produto_stock_revision.dart';
import 'produto_variacao_extra.dart';
import 'produto_variation_cas_rebase.dart';
import '../models/produto.dart';
import '../services/produto_stock_catalog_cadastro_sync.dart';

enum StaleReplaceIntentClass {
  currentAndSendable,
  supersededNoLocalEdit,
  staleWithGenuineUnsyncedEdit,
  alreadyReflectedRemote,
  conflictUnknown,
  invalidOrCorrupt,
  notReplace,
}

enum StaleReplaceDispatch {
  sendReplaceOnce,
  sendEditorialRebase,
  suppress,
  blockConflict,
  passthrough,
}

class StaleReplacePeer {
  const StaleReplacePeer({
    required this.createdAt,
    this.expectedRevision,
  });

  final int createdAt;
  final int? expectedRevision;
}

class StaleReplaceDecision {
  const StaleReplaceDecision({
    required this.classification,
    required this.dispatch,
    this.reason = '',
  });

  final StaleReplaceIntentClass classification;
  final StaleReplaceDispatch dispatch;
  final String reason;

  bool get sendsReplace => dispatch == StaleReplaceDispatch.sendReplaceOnce;
  bool get sendsAnything =>
      dispatch == StaleReplaceDispatch.sendReplaceOnce ||
      dispatch == StaleReplaceDispatch.sendEditorialRebase;
}

class ProdutoStaleReplaceIntent {
  ProdutoStaleReplaceIntent._();

  static const bool passiveListHydrationEmitsReplace = false;
  static const bool editorOpenWithoutSaveEmitsReplace = false;

  static const versionConflictUserMessage =
      'conflito de versão do estoque — reabra o produto e salve novamente';

  static int? expectedRevisionOf(ProdutoStockCatalogCadastroIntent intent) {
    if (intent.expectedRevision != null) return intent.expectedRevision;
    if (intent.items.isEmpty) return null;
    return (intent.items.first['expectedRevision'] as num?)?.toInt();
  }

  static bool olderIntentMustYield({
    required int thisCreatedAt,
    required int? thisExpectedRevision,
    required List<StaleReplacePeer> peers,
  }) {
    for (final peer in peers) {
      final peerRev = peer.expectedRevision ?? -1;
      final thisRev = thisExpectedRevision ?? -1;
      if (peerRev > thisRev) return true;
      if (peerRev == thisRev && peer.createdAt > thisCreatedAt) return true;
    }
    return false;
  }

  static bool isRetryableTransportError(Object error) {
    return ProdutoStockCatalogCadastroSync.isRetryableTransportError(error) &&
        !ProdutoVariationCasRebase.isStockRevisionConflict(error);
  }

  /// Compara stock canónico (variacoes / quantidade). Ignora EPT.
  static bool canonicalStockEquals({
    required Map<String, dynamic>? intentDefinition,
    required Map<String, dynamic> remoteData,
  }) {
    final intentSnap = _canonicalSnapshotFromDefinition(intentDefinition);
    final remoteSnap = _canonicalSnapshotFromRemote(remoteData);
    return _cellsEqual(intentSnap, remoteSnap);
  }

  static bool editorialHasUniqueChange({
    required Map<String, dynamic> intentEditorial,
    required Map<String, dynamic> remoteData,
  }) {
    const keys = <String>[
      'nome',
      'descricao',
      'preco',
      'preco_venda',
      'precoFinal',
      'imagens',
      'categoria',
      'categoriaId',
      'subcategoria',
      'subcategoriaId',
      'publicadoNoCatalogo',
      'exibir_no_catalogo',
      'ocultar_catalogo',
      'slug',
    ];
    for (final key in keys) {
      if (!intentEditorial.containsKey(key)) continue;
      final remoteVal = remoteData.containsKey(key)
          ? remoteData[key]
          : _editorialRemoteAlias(remoteData, key);
      if (!_looseEquals(intentEditorial[key], remoteVal)) return true;
    }
    return false;
  }

  static StaleReplaceDecision classify({
    required ProdutoStockCatalogCadastroIntent intent,
    Map<String, dynamic>? remoteData,
    bool remoteReadAvailable = true,
    bool frozenQueueIntent = false,
    int intentCreatedAt = 0,
    List<StaleReplacePeer> newerPeers = const [],
  }) {
    if (intent.kind != 'replace') {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.notReplace,
        dispatch: StaleReplaceDispatch.passthrough,
        reason: 'not-replace',
      );
    }
    if (intent.items.isEmpty || intent.operationId.trim().isEmpty) {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.invalidOrCorrupt,
        dispatch: StaleReplaceDispatch.blockConflict,
        reason: 'invalid-intent',
      );
    }

    if (olderIntentMustYield(
      thisCreatedAt: intentCreatedAt,
      thisExpectedRevision: expectedRevisionOf(intent),
      peers: newerPeers,
    )) {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.supersededNoLocalEdit,
        dispatch: StaleReplaceDispatch.suppress,
        reason: 'older-intent-overtaken',
      );
    }

    final expected = expectedRevisionOf(intent);
    if (!remoteReadAvailable || remoteData == null) {
      if (frozenQueueIntent) {
        return const StaleReplaceDecision(
          classification: StaleReplaceIntentClass.conflictUnknown,
          dispatch: StaleReplaceDispatch.blockConflict,
          reason: 'frozen-without-remote',
        );
      }
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.currentAndSendable,
        dispatch: StaleReplaceDispatch.sendReplaceOnce,
        reason: 'no-remote-online-send',
      );
    }

    final remoteRev = parseStockRevisionFromRemote(remoteData);
    final stockEq = canonicalStockEquals(
      intentDefinition: intent.definition,
      remoteData: remoteData,
    );
    final editorialUnique = editorialHasUniqueChange(
      intentEditorial: intent.editorial,
      remoteData: remoteData,
    );

    if (expected == null) {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.invalidOrCorrupt,
        dispatch: StaleReplaceDispatch.blockConflict,
        reason: 'missing-expected-revision',
      );
    }

    if (expected == remoteRev) {
      if (stockEq && !editorialUnique) {
        return const StaleReplaceDecision(
          classification: StaleReplaceIntentClass.alreadyReflectedRemote,
          dispatch: StaleReplaceDispatch.suppress,
          reason: 'equal-rev-already-reflected',
        );
      }
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.currentAndSendable,
        dispatch: StaleReplaceDispatch.sendReplaceOnce,
        reason: 'equal-rev-valid',
      );
    }

    if (expected > remoteRev) {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.currentAndSendable,
        dispatch: StaleReplaceDispatch.sendReplaceOnce,
        reason: 'local-ahead-valid',
      );
    }

    // expected < remoteRev → stale vs authoritative remote.
    if (stockEq && !editorialUnique) {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.alreadyReflectedRemote,
        dispatch: StaleReplaceDispatch.suppress,
        reason: 'stale-already-reflected',
      );
    }
    if (stockEq && editorialUnique) {
      return const StaleReplaceDecision(
        classification: StaleReplaceIntentClass.staleWithGenuineUnsyncedEdit,
        dispatch: StaleReplaceDispatch.sendEditorialRebase,
        reason: 'stale-non-stock-rebase',
      );
    }

    // Stock differs and we have no per-cell baseline on frozen intents.
    // Never copy stale variacoes/EPT over newer remote.
    return const StaleReplaceDecision(
      classification: StaleReplaceIntentClass.staleWithGenuineUnsyncedEdit,
      dispatch: StaleReplaceDispatch.blockConflict,
      reason: 'stale-stock-unproven-edit',
    );
  }

  static ProdutoStockCatalogCadastroIntent asEditorialRebase(
    ProdutoStockCatalogCadastroIntent intent,
  ) {
    return ProdutoStockCatalogCadastroIntent(
      operationId: intent.operationId,
      kind: 'editorial',
      items: [
        {'productId': intent.items.first['productId']},
      ],
      editorial: Map<String, dynamic>.from(intent.editorial),
    );
  }

  static Map<String, int> _canonicalSnapshotFromDefinition(
    Map<String, dynamic>? definition,
  ) {
    if (definition == null) return const {};
    final varsRaw = definition['variacoes'];
    final vars = varsRaw is Map
        ? ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(
            Map<String, dynamic>.from(varsRaw),
          )
        : <String, dynamic>{};
    final qty = ProdutoVariacaoExtra.valorFirestoreComoInt(
      definition['quantidade'],
    );
    return _cellsIgnoringEpt(variacoes: vars, quantidade: qty);
  }

  static Map<String, int> _canonicalSnapshotFromRemote(
    Map<String, dynamic> remote,
  ) {
    final varsRaw = remote['variacoes'];
    final vars = varsRaw is Map
        ? ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(
            Map<String, dynamic>.from(varsRaw),
          )
        : <String, dynamic>{};
    final qty =
        ProdutoVariacaoExtra.valorFirestoreComoInt(remote['quantidade']);
    return _cellsIgnoringEpt(variacoes: vars, quantidade: qty);
  }

  static Map<String, int> _cellsIgnoringEpt({
    required Map<String, dynamic>? variacoes,
    required int quantidade,
  }) {
    final p = Produto.vazio()
      ..quantidade = quantidade
      ..variacoes = variacoes == null || variacoes.isEmpty
          ? null
          : Map<String, dynamic>.from(variacoes)
      ..estoquePorTamanho = {};
    return Map<String, int>.from(
      ProdutoEstoqueGradeSnapshot.fromProduto(p).cells,
    );
  }

  static bool _cellsEqual(Map<String, int> a, Map<String, int> b) {
    final keys = {...a.keys, ...b.keys};
    for (final k in keys) {
      if ((a[k] ?? 0) != (b[k] ?? 0)) return false;
    }
    return true;
  }

  static Object? _editorialRemoteAlias(
      Map<String, dynamic> remote, String key) {
    switch (key) {
      case 'preco':
      case 'preco_venda':
        return remote['precoFinal'] ?? remote['preco'] ?? remote['preco_venda'];
      case 'precoFinal':
        return remote['precoFinal'] ?? remote['preco'];
      case 'exibir_no_catalogo':
        return remote['publicadoNoCatalogo'] ?? remote['exibir_no_catalogo'];
      case 'ocultar_catalogo':
        final pub = remote['publicadoNoCatalogo'];
        if (pub is bool) return !pub;
        return remote['ocultar_catalogo'];
      default:
        return null;
    }
  }

  static bool _looseEquals(Object? a, Object? b) {
    if (a == b) return true;
    if (a == null || b == null) {
      if (a == '' && b == null) return true;
      if (b == '' && a == null) return true;
      return false;
    }
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_looseEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a.toString() == b.toString();
  }
}
