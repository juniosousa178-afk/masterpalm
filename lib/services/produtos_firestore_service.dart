// lib/services/produtos_firestore_service.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, visibleForTesting;
import 'package:firebase_storage/firebase_storage.dart';

import '../core/combo_config_canonical.dart';
import '../core/firestore_access_guard.dart';
import '../core/hive_box_names.dart';
import '../core/produto_custo_guard.dart';
import '../core/produto_estoque_grade_canonical_guard.dart';
import '../core/produto_form_grade_hydration.dart';
import '../core/produto_variacao_extra.dart';
import '../core/produto_estoque_grade_snapshot.dart';
import '../core/produto_stock_revision.dart';
import '../core/produto_stock_version_fields.dart';
import 'firestore_paths.dart';
import '../core/logger.dart';
import 'package:hive/hive.dart';
import '../models/produto.dart';
import 'catalogo_sync_service.dart';
import 'produto_remote_sync_guard.dart';
import 'store_resolver_facade.dart';
import 'combo_receita_normalizacao.dart';
import 'firestore_payload_sanitizer.dart';
import 'image_upload_service.dart';
import 'produto_sync_erro_util.dart';
import 'catalogo_live_inline_policy.dart';
import 'catalogo_queue_publish_plan.dart';
import 'sync_queue_service.dart';
import 'produto_catalogo_upsert_falha.dart';
import 'catalogo_sync_attempt_context.dart';
import 'catalogo_sync_diagnostics_service.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produto_import_sync_prep_service.dart';
import '../core/produto_firestore_doc_id_validator.dart';
import 'produto_pull_skip_guard.dart';
import 'sync_mass_delete_guard.dart';
import '../src/blob_fetch_stub.dart'
    if (dart.library.html) '../src/blob_fetch_web.dart' as blob_fetch;

/// Serviço para sincronizar produtos com Firestore.
///
/// Estoque autoritativo:
/// - O saldo oficial de estoque vive em `lojas/{lojaId}/estoque_produtos`:
///   - `quantidade` (total),
///   - `variacoes` (tamanho+cor),
///   - `estoquePorTamanho`.
/// - Baixas de venda devem ser feitas via `EstoqueTransactionService` (transações atômicas).
/// - Este serviço reflete o estado local (Hive) para o Firestore e deve ser usado com cuidado
///   após operações de venda para não sobrescrever saldos já atualizados por transações.
enum ProdutoSyncRemotoStatus {
  confirmado,
  pendenteFila,
  falhaRemota,
  lojaInvalida,
  produtoInvalido,
  semMudancas,

  /// Produto com exclusão definitiva (tombstone) — upsert remoto descartado.
  bloqueadoExclusaoTombstone,

  /// Produto com venda/referência e colisão remota — sem troca automática de ID.
  recuperacaoManualNecessaria,
}

class ProdutosFirestoreService {
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static bool get debugForbidFirestoreAccess => FirestoreAccessGuard.forbidAccess;

  @visibleForTesting
  static set debugForbidFirestoreAccess(bool value) {
    FirestoreAccessGuard.forbidAccess = value;
  }

  @visibleForTesting
  static int get debugFirestoreAccessCount => FirestoreAccessGuard.accessCount;

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: debugFirestoreOverride,
      );

  /// Chaves de variação/grade no Firestore.
  @visibleForTesting
  static const variationFirestoreFieldKeys = <String>[
    'variacoes',
    'variacoesExtraTipo',
    'estoquePorTamanho',
    'precoPorTamanho',
  ];

  /// Campos internos que não devem existir no doc público `produtos`.
  static const _publicoInternoKeysToStrip = <String>{
    'custoReal',
    'custo',
    'precoCusto',
    'fornecedor',
    'frete',
    'gastosFixos',
    'gastosVariaveis',
    'precoSugerido',
    'custoEditadoNoCadastro',
    'dataEntrada',
    'ativoNoRascunho',
  };

  /// Aplica campos de variação/grade no patch. Mapas vazios não usam
  /// [FieldValue.delete] (inválido em `set()` sem merge); a remoção no doc
  /// final é feita via [variationKeysToRemove] + [buildFinalDocumentPayloadForSet].
  @visibleForTesting
  static void applyVariationFieldsToFirestorePayload(
    Map<String, dynamic> payload, {
    required Map<String, dynamic> variacoes,
    required Map<String, dynamic> variacoesExtraTipo,
    required Map<String, int> estoquePorTamanho,
    Map<String, double>? precoPorTamanho,
    Set<String>? variationKeysToRemove,
    bool treatEmptyAsOmitOnly = false,
  }) {
    void setOrMarkRemove(String key, dynamic value, bool hasValue) {
      if (hasValue) {
        payload[key] = value;
      } else {
        payload.remove(key);
        if (!treatEmptyAsOmitOnly) {
          variationKeysToRemove?.add(key);
        }
      }
    }

    setOrMarkRemove('variacoes', variacoes, variacoes.isNotEmpty);
    setOrMarkRemove(
      'variacoesExtraTipo',
      variacoesExtraTipo,
      variacoesExtraTipo.isNotEmpty,
    );
    setOrMarkRemove(
      'estoquePorTamanho',
      estoquePorTamanho,
      estoquePorTamanho.isNotEmpty,
    );
    setOrMarkRemove(
      'precoPorTamanho',
      precoPorTamanho,
      precoPorTamanho != null && precoPorTamanho.isNotEmpty,
    );
  }

  static bool _isFirestoreDeleteValue(dynamic value) {
    return FirestorePayloadSanitizer.isDeleteFieldValue(value);
  }

  /// Monta o documento final em memória (campos do patch substituem o existente
  /// no topo; mapas aninhados não sofrem merge profundo). Uma única [set] grava
  /// o resultado — equivalente a merge sem janela entre delete e write.
  @visibleForTesting
  static Map<String, dynamic> buildFinalDocumentPayloadForSet({
    required Map<String, dynamic>? existingData,
    required Map<String, dynamic> patch,
    Set<String> forceRemoveKeys = const {},
  }) {
    final out = existingData != null
        ? Map<String, dynamic>.from(existingData)
        : <String, dynamic>{};
    for (final key in forceRemoveKeys) {
      out.remove(key);
    }
    for (final entry in patch.entries) {
      final value = entry.value;
      if (value == null || _isFirestoreDeleteValue(value)) {
        out.remove(entry.key);
      } else {
        out[entry.key] = value;
      }
    }
    return FirestorePayloadSanitizer.stripDeleteSentinelsForFullSet(out);
  }

  /// Uma única escrita no documento ([set] do payload final já mesclado).
  static Future<void> _upsertProdutoDocument(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> payload, {
    Map<String, dynamic>? existingData,
    Set<String> forceRemoveKeys = const {},
  }) async {
    final merged = buildFinalDocumentPayloadForSet(
      existingData: existingData,
      patch: payload,
      forceRemoveKeys: forceRemoveKeys,
    );
    final sanitize = sanitizePayloadForFirestore(
      merged,
      rootPath: ref.path,
      forFullDocumentSet: true,
    );
    if (sanitize.adjustedPaths.isNotEmpty) {
      logW(
        '[PRODUTOS-SYNC] payload final sanitizado em ${ref.path}: '
        '${sanitize.adjustedPaths.join(' | ')}',
      );
    }
    await ref.set(sanitize.payload);
  }

  @visibleForTesting
  static FirestorePayloadSanitizeResult sanitizePayloadForFirestore(
    Map<String, dynamic> payload, {
    required String rootPath,
    bool forFullDocumentSet = false,
  }) {
    return FirestorePayloadSanitizer.sanitizeMap(
      payload,
      rootPath: rootPath,
      forFullDocumentSet: forFullDocumentSet,
    );
  }

  /// Grade manual persistida localmente (cadastro/edição de variações).
  @visibleForTesting
  static bool localTemGradeManualPersistida(Produto local) {
    final localVars = local.variacoes;
    if (localVars != null && localVars.isNotEmpty) return true;
    if (local.custoEditadoNoCadastro == true && local.estoquePorTamanho.isNotEmpty) {
      return true;
    }
    if (local.custoEditadoNoCadastro == true && local.tamanhos.isNotEmpty) {
      return true;
    }
    return false;
  }

  /// Pull: não apagar variações locais cadastradas quando o remoto vier vazio/null
  /// (ex.: estado transitório corrompido no doc remoto).
  @visibleForTesting
  static bool shouldIgnoreEmptyRemoteVariacoesOnPull({
    required Produto local,
    required dynamic remoteVariacoes,
  }) {
    if (!localTemGradeManualPersistida(local)) return false;
    if (remoteVariacoes == null) return true;
    if (remoteVariacoes is Map && remoteVariacoes.isEmpty) return true;
    return false;
  }

  @visibleForTesting
  static bool shouldIgnoreEmptyRemoteEstoquePorTamanhoOnPull({
    required Produto local,
    required dynamic remoteEstoquePorTamanho,
  }) {
    if (!localTemGradeManualPersistida(local)) return false;
    if (remoteEstoquePorTamanho == null) return true;
    if (remoteEstoquePorTamanho is Map && remoteEstoquePorTamanho.isEmpty) {
      return true;
    }
    return false;
  }

  /// Mescla campos de grade do doc remoto em [local] com guards anti-sobrescrita vazia.
  static void applyRemoteVariationFieldsToExistingOnPull({
    required Produto local,
    required Map<String, dynamic> data,
  }) {
    if (data.containsKey('tamanhos')) {
      final rawT = data['tamanhos'];
      if (rawT is List && rawT.isNotEmpty) {
        local.tamanhos = _dedupeStringListPreserveOrder(
          rawT.map((e) => e.toString()).toList(),
        );
      } else if (rawT == null || (rawT is List && rawT.isEmpty)) {
        if (!localTemGradeManualPersistida(local)) {
          local.tamanhos = [];
        } else {
          logW(
            '[VARIACAO_PULL] tamanhos remotos vazios ignorados — mantendo local',
            tag: 'VARIACAO_GUARD',
          );
        }
      }
    }

    if (data.containsKey('cores')) {
      final rawC = data['cores'];
      if (rawC is List) {
        local.cores = _dedupeStringListPreserveOrder(
          rawC.map((e) => e.toString()).toList(),
        );
      }
    }

    if (data.containsKey('estoquePorTamanho')) {
      final rawE = data['estoquePorTamanho'];
      if (shouldIgnoreEmptyRemoteEstoquePorTamanhoOnPull(
        local: local,
        remoteEstoquePorTamanho: rawE,
      )) {
        logW(
          '[VARIACAO_PULL] estoquePorTamanho remoto vazio ignorado — '
          'mantendo grade local',
          tag: 'VARIACAO_GUARD',
        );
      } else if (rawE == null) {
        local.estoquePorTamanho = {};
        logD('[VARIACAO_PULL] estoquePorTamanho remoto null → limpo');
      } else if (rawE is Map) {
        if (rawE.isEmpty) {
          local.estoquePorTamanho = {};
          logD('[VARIACAO_PULL] estoquePorTamanho remoto {} → limpo');
        } else {
          local.estoquePorTamanho = rawE.map(
            (k, v) => MapEntry(
              k.toString(),
              ProdutoVariacaoExtra.valorFirestoreComoInt(v),
            ),
          );
        }
      }
    } else {
      logW(
        '[VARIACAO_PULL] estoquePorTamanho ausente no doc — mantendo local (legado)',
        tag: 'VARIACAO_GUARD',
      );
    }

    if (data.containsKey('variacoes')) {
      final varData = data['variacoes'];
      if (shouldIgnoreEmptyRemoteVariacoesOnPull(
        local: local,
        remoteVariacoes: varData,
      )) {
        logW(
          '[VARIACAO_PULL] variacoes remotas vazias ignoradas — '
          'mantendo grade local (cadastro manual)',
          tag: 'VARIACAO_GUARD',
        );
      } else if (varData == null) {
        local.variacoes = null;
        logD('[VARIACAO_PULL] variacoes remotas null → limpo local');
      } else if (varData is Map) {
        if (varData.isEmpty) {
          local.variacoes = null;
          logD('[VARIACAO_PULL] variacoes remotas {} → limpo local');
        } else {
          local.variacoes = parseVariacoesFromFirestore(varData);
        }
      }
    } else {
      logW(
        '[VARIACAO_PULL] variacoes ausente no doc — mantendo local (legado)',
        tag: 'VARIACAO_GUARD',
      );
    }

    if (data.containsKey('variacoesExtraTipo')) {
      final vet = data['variacoesExtraTipo'];
      if (vet == null) {
        local.variacoesExtraTipo = null;
        logD('[VARIACAO_PULL] variacoesExtraTipo remoto null → limpo');
      } else if (vet is Map) {
        if (vet.isEmpty) {
          local.variacoesExtraTipo = null;
          logD('[VARIACAO_PULL] variacoesExtraTipo remoto {} → limpo');
        } else {
          local.variacoesExtraTipo =
              _parseVariacoesExtraTipoFromFirestore(vet);
        }
      }
    } else {
      logW(
        '[VARIACAO_PULL] variacoesExtraTipo ausente — mantendo local (legado)',
        tag: 'VARIACAO_GUARD',
      );
    }

    if (data.containsKey('precoPorTamanho')) {
      final ppt = data['precoPorTamanho'];
      if (ppt != null && ppt is Map) {
        local.precoPorTamanho = parsePrecoPorTamanhoFromFirestore(ppt);
      } else if (ppt == null) {
        local.precoPorTamanho = null;
      }
    }
  }

  /// Remoto com grade rica (variações ou estoque por tamanho preenchidos).
  @visibleForTesting
  static bool remoteTemGradeRica(Map<String, dynamic>? data) {
    if (data == null) return false;
    final v = data['variacoes'];
    if (v is Map && v.isNotEmpty) return true;
    final e = data['estoquePorTamanho'];
    if (e is Map && e.isNotEmpty) return true;
    return false;
  }

  static bool _localPushVariationContentVazia({
    required Map<String, dynamic> variacoes,
    required Map<String, dynamic> variacoesExtraTipo,
    required Map<String, int> estoquePorTamanho,
  }) {
    return variacoes.isEmpty &&
        variacoesExtraTipo.isEmpty &&
        estoquePorTamanho.isEmpty;
  }

  static DateTime? _firestoreUpdatedAtToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  /// Push explícito para apagar grade: usuário salvou versão mais nova sem grade.
  @visibleForTesting
  static bool isExplicitGradeRemovalOnPush({
    required Produto local,
    required Map<String, dynamic>? existingData,
    required Map<String, dynamic> variacoesPush,
    required Map<String, dynamic> variacoesExtraPush,
    required Map<String, int> estoquePorTamPush,
  }) {
    if (!_localPushVariationContentVazia(
      variacoes: variacoesPush,
      variacoesExtraTipo: variacoesExtraPush,
      estoquePorTamanho: estoquePorTamPush,
    )) {
      return false;
    }
    if (!remoteTemGradeRica(existingData)) return true;

    final remoteAt = _firestoreUpdatedAtToDate(existingData?['updatedAt']);
    final localAt = local.updatedAt;
    if (localAt == null) return false;
    if (remoteAt == null) return false;
    return localAt.isAfter(remoteAt.add(const Duration(seconds: 2)));
  }

  /// Push: não apagar grade remota quando o local enviaria mapas vazios/stale.
  @visibleForTesting
  static bool shouldPreserveRemoteGradeOnEmptyLocalPush({
    required Produto local,
    required Map<String, dynamic>? existingData,
    required Map<String, dynamic> variacoesPush,
    required Map<String, dynamic> variacoesExtraPush,
    required Map<String, int> estoquePorTamPush,
  }) {
    if (!remoteTemGradeRica(existingData)) return false;
    if (!_localPushVariationContentVazia(
      variacoes: variacoesPush,
      variacoesExtraTipo: variacoesExtraPush,
      estoquePorTamanho: estoquePorTamPush,
    )) {
      return false;
    }
    if (isExplicitGradeRemovalOnPush(
      local: local,
      existingData: existingData,
      variacoesPush: variacoesPush,
      variacoesExtraPush: variacoesExtraPush,
      estoquePorTamPush: estoquePorTamPush,
    )) {
      return false;
    }
    return true;
  }

  static Map<String, dynamic> _variacoesMapParaPushFromRemoteData(
    Map<String, dynamic> data,
  ) {
    final raw = data['variacoes'];
    if (raw is! Map || raw.isEmpty) return {};
    return sanitizeVariacoesForFirestore(Map<String, dynamic>.from(raw));
  }

  static Map<String, dynamic> _variacoesExtraTipoParaPushFromRemoteData(
    Map<String, dynamic> data,
  ) {
    final raw = data['variacoesExtraTipo'];
    if (raw is! Map || raw.isEmpty) return {};
    return _parseVariacoesExtraTipoFromFirestore(raw) ?? {};
  }

  static Map<String, int> _estoquePorTamanhoParaPushFromRemoteData(
    Map<String, dynamic> data,
  ) {
    final raw = data['estoquePorTamanho'];
    if (raw is! Map || raw.isEmpty) return {};
    return raw.map(
      (k, v) => MapEntry(
        k.toString(),
        ProdutoVariacaoExtra.valorFirestoreComoInt(v),
      ),
    );
  }

  static List<String> _tamanhosParaPushFromRemoteData(Map<String, dynamic> data) {
    final raw = data['tamanhos'];
    if (raw is! List || raw.isEmpty) return [];
    return _dedupeStringListPreserveOrder(
      raw.map((e) => e.toString()).toList(),
    );
  }

  static Map<String, double>? _precoPorTamanhoParaPushFromRemoteData(
    Map<String, dynamic> data,
  ) {
    final raw = data['precoPorTamanho'];
    if (raw is! Map || raw.isEmpty) return null;
    return parsePrecoPorTamanhoFromFirestore(raw);
  }

  static void _applyRemoteGradeToProdutoForRehydrate({
    required Produto produto,
    required Map<String, dynamic> existingData,
  }) {
    final tamanhos = _tamanhosParaPushFromRemoteData(existingData);
    if (tamanhos.isNotEmpty) produto.tamanhos = tamanhos;

    final estoque = _estoquePorTamanhoParaPushFromRemoteData(existingData);
    if (estoque.isNotEmpty) produto.estoquePorTamanho = estoque;

    final varData = existingData['variacoes'];
    if (varData is Map && varData.isNotEmpty) {
      produto.variacoes = parseVariacoesFromFirestore(varData);
    }

    final vetData = existingData['variacoesExtraTipo'];
    if (vetData is Map && vetData.isNotEmpty) {
      produto.variacoesExtraTipo =
          _parseVariacoesExtraTipoFromFirestore(vetData);
    }

    final ppt = _precoPorTamanhoParaPushFromRemoteData(existingData);
    produto.precoPorTamanho = ppt;
  }

  static Future<void> _rehydrateLocalGradeFromRemoteOnStalePush(
    Produto produto,
    Map<String, dynamic> existingData,
  ) async {
    ProdutoRemoteSyncGuard.applyingRemoteToHive = true;
    try {
      _applyRemoteGradeToProdutoForRehydrate(
        produto: produto,
        existingData: existingData,
      );
      await produto.save();
      logW(
        '[VARIACAO_PUSH] Hive reidratado a partir de grade remota preservada',
        tag: 'VARIACAO_GUARD',
      );
    } finally {
      ProdutoRemoteSyncGuard.applyingRemoteToHive = false;
    }
  }

  @visibleForTesting
  static ({
    Map<String, dynamic> variacoes,
    Map<String, dynamic> variacoesExtraTipo,
    Map<String, int> estoquePorTamanho,
    Map<String, double>? precoPorTamanho,
    List<String> tamanhos,
    bool rehydrateLocalFromRemote,
  }) resolveVariationFieldsForFirestorePush({
    required Produto local,
    required Map<String, dynamic>? existingData,
    required Map<String, dynamic> variacoesPush,
    required Map<String, dynamic> variacoesExtraPush,
    required Map<String, int> estoquePorTamPush,
    Map<String, double>? precoPorTamanhoPush,
  }) {
    final tamanhosLocal = List<String>.from(local.tamanhos);
    if (!shouldPreserveRemoteGradeOnEmptyLocalPush(
      local: local,
      existingData: existingData,
      variacoesPush: variacoesPush,
      variacoesExtraPush: variacoesExtraPush,
      estoquePorTamPush: estoquePorTamPush,
    )) {
      return (
        variacoes: variacoesPush,
        variacoesExtraTipo: variacoesExtraPush,
        estoquePorTamanho: estoquePorTamPush,
        precoPorTamanho: precoPorTamanhoPush,
        tamanhos: tamanhosLocal,
        rehydrateLocalFromRemote: false,
      );
    }

    final data = existingData!;
    logW(
      '[VARIACAO_PUSH] push local vazio com remoto rico — preservando grade remota',
      tag: 'VARIACAO_GUARD',
    );
    final tamanhosRemotos = _tamanhosParaPushFromRemoteData(data);
    return (
      variacoes: _variacoesMapParaPushFromRemoteData(data),
      variacoesExtraTipo: _variacoesExtraTipoParaPushFromRemoteData(data),
      estoquePorTamanho: _estoquePorTamanhoParaPushFromRemoteData(data),
      precoPorTamanho:
          _precoPorTamanhoParaPushFromRemoteData(data) ?? precoPorTamanhoPush,
      tamanhos:
          tamanhosRemotos.isNotEmpty ? tamanhosRemotos : tamanhosLocal,
      rehydrateLocalFromRemote: true,
    );
  }

  /// Estado explícito da persistência remota de produto.
  /// - confirmado: escrita remota concluída
  /// - pendenteFila: falhou remoto, item foi enfileirado para retry
  /// - falhaRemota: falhou remoto e não houve enfileiramento
  /// - lojaInvalida: sem contexto de loja para sincronizar
  /// - produtoInvalido: chave local inválida para enfileirar retry
  /// - semMudancas: reservado para uso futuro
  ///
  /// Tombstone em `estoque_produtos` durante soft delete (antes da exclusão definitiva).
  /// Evita que [syncFirestoreToHive] recrie o produto no Hive enquanto o doc ainda existir.
  static const String fieldEstoquePendingSoftDelete = 'pendingSoftDelete';
  static const String fieldEstoquePendingSoftDeleteAt = 'pendingSoftDeleteAt';

  /// `true` quando o pull deve ignorar o documento (não atualizar nem criar Hive).
  static bool isEstoqueDocPendingSoftDelete(Map<String, dynamic> data) {
    final v = data[fieldEstoquePendingSoftDelete];
    return v == true;
  }

  /// Resolve o documento em `estoque_produtos` quando o Hive ainda não tem [idFirebase].
  static Future<String?> findEstoqueProdutoDocIdBySlug({
    required String lojaId,
    required String slug,
  }) async {
    final s = slug.trim();
    if (lojaId.trim().isEmpty || s.isEmpty) return null;
    try {
      final snap = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .where('slug', isEqualTo: s)
          .limit(3)
          .get();
      if (snap.docs.isEmpty) return null;
      if (snap.docs.length > 1) {
        logW(
          '[PRODUTOS-SYNC] slug duplicado em estoque_produtos (slug=$s, n=${snap.docs.length})',
          tag: 'PRODUTO_MATCH_GUARD',
        );
      }
      return snap.docs.first.id;
    } catch (e, st) {
      logW(
        '[PRODUTOS-SYNC] findEstoqueProdutoDocIdBySlug falhou (type=${e.runtimeType})',
        tag: 'PRODUTO_MATCH_GUARD',
      );
      if (kDebugMode) logD('$st');
      return null;
    }
  }

  /// Pull pontual de `estoque_produtos` para o Hive quando o aparelho ainda não tem o produto
  /// (ex.: lojista confirma pagamento de pedido web sem ter aberto o estoque local).
  static Future<void> ensureEstoqueProdutoDocsInHive({
    required String lojaId,
    required Box<Produto> produtosBox,
    required Iterable<String> firebaseDocIds,
    bool forceRefreshFromRemoto = false,
  }) async {
    final lid = lojaId.trim();
    if (lid.isEmpty) return;

    for (final raw in firebaseDocIds) {
      final produtoId = raw.trim();
      if (produtoId.isEmpty) continue;

      final already = !forceRefreshFromRemoto &&
          produtosBox.values.any(
            (p) =>
                p.lojaId == lid &&
                (p.idFirebase == produtoId || p.slug == produtoId),
          );
      if (already) continue;

      try {
        final snap = await _db
            .collection('lojas')
            .doc(lid)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(produtoId)
            .get();
        if (!snap.exists) {
          logW(
            '[ESTOQUE_HYDRATE] Doc estoque_produtos ausente: $produtoId',
            tag: 'ESTOQUE_HYDRATE',
          );
          continue;
        }
        final data = Map<String, dynamic>.from(snap.data() ?? {});
        if (isEstoqueDocPendingSoftDelete(data)) {
          logW(
            '[ESTOQUE_HYDRATE] Doc em soft-delete, ignorando: $produtoId',
            tag: 'ESTOQUE_HYDRATE',
          );
          continue;
        }

        final uAt = data['updatedAt'];
        final updatedAtDt =
            uAt != null && uAt is Timestamp ? uAt.toDate() : null;
        final comboNovo = comboFieldsForNewProductPull(
          data,
          produtosBox: produtosBox,
          lojaId: lid,
          docId: produtoId,
        );
        final produto = Produto(
          idFirebase: produtoId,
          nome: data['nome'] ?? 'Produto sem nome',
          custoReal: (data['custoReal'] as num?)?.toDouble() ?? 0.0,
          frete: (data['frete'] as num?)?.toDouble() ?? 0.0,
          gastosFixos: (data['gastosFixos'] as num?)?.toDouble() ?? 0.0,
          gastosVariaveis: (data['gastosVariaveis'] as num?)?.toDouble() ?? 0.0,
          precoSugerido: (data['precoSugerido'] as num?)?.toDouble() ??
              (data['preco'] as num?)?.toDouble() ??
              0.0,
          precoFinal: (data['preco'] as num?)?.toDouble() ?? 0.0,
          precoUnitario: (data['precoUnitario'] as num?)?.toDouble() ??
              (data['preco'] as num?)?.toDouble() ??
              0.0,
          quantidade: (data['quantidade'] as num?)?.toInt() ?? 0,
          categoria: data['categoria'] ?? '',
          categoriasExtras: (data['categoriasExtras'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          dataEntrada: data['dataEntrada'] is Timestamp
              ? (data['dataEntrada'] as Timestamp).toDate()
              : DateTime.now(),
          descricao: data['descricao'] ?? '',
          imagens: (data['imagens'] as List?)?.cast<String>() ?? [],
          slug: data['slug'] ?? '',
          lojaId: lid,
          subcategoria: data['subcategoria'] ?? '',
          subcategoriasExtras: (data['subcategoriasExtras'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          publicadoNoCatalogo: data['publicadoNoCatalogo'] ?? false,
          tamanhos: _dedupeStringListPreserveOrder(
            (data['tamanhos'] as List?)?.map((e) => e.toString()).toList(),
          ),
          estoquePorTamanho:
              Map<String, int>.from(data['estoquePorTamanho'] ?? {}),
          cores: _dedupeStringListPreserveOrder(
            (data['cores'] as List?)?.map((e) => e.toString()).toList(),
          ),
          variacoes: parseVariacoesFromFirestore(data['variacoes']),
          variacoesExtraTipo:
              _parseVariacoesExtraTipoFromFirestore(data['variacoesExtraTipo']),
          precoPorTamanho:
              parsePrecoPorTamanhoFromFirestore(data['precoPorTamanho']),
          tipoProduto: comboNovo.$1,
          itensCombo: comboNovo.$2,
          comboConfig: comboNovo.$3,
          divideSemJuros: data['divideSemJuros'] == true,
          percentualDescontoPix: (data['percentualDescontoPix'] is num)
              ? (data['percentualDescontoPix'] as num).toDouble()
              : 0.0,
          maxParcelasSemJuros: (data['maxParcelasSemJuros'] is num)
              ? (data['maxParcelasSemJuros'] as num).toInt()
              : 12,
          codigoBarras: (data['codigoBarras'] ?? '').toString(),
          sku: (data['sku'] ?? '').toString(),
          estoqueMinimo: (data['estoqueMinimo'] is num)
              ? (data['estoqueMinimo'] as num).toInt()
              : 0,
          fornecedor: (data['fornecedor'] ?? '').toString().trim(),
          peso: (data['peso'] as num?)?.toDouble() ?? 0.0,
          tipoEmbalagem: (data['tipoEmbalagem'] ?? 'padrao').toString(),
          updatedAt: updatedAtDt,
          custoEditadoNoCadastro:
              (data['custoEditadoNoCadastro'] as bool?) ?? false,
          emPromocao: data['emPromocao'] == true,
          percentualPromo: (data['percentualPromo'] as num?)?.toDouble(),
          valorPromo: (data['valorPromo'] as num?)?.toDouble(),
          dataInicioPromo: data['dataInicioPromo'] is Timestamp
              ? (data['dataInicioPromo'] as Timestamp).toDate()
              : null,
          dataFimPromo: data['dataFimPromo'] is Timestamp
              ? (data['dataFimPromo'] as Timestamp).toDate()
              : null,
          videoUrl: (data['videoUrl'] ?? '').toString(),
          marketplaces: (data['marketplaces'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          ativoNoRascunho: data['ativoNoRascunho'] == true,
        );

        produto.recalcularQuantidadeTotal();

        Produto? existente;
        for (final key in produtosBox.keys) {
          final p = produtosBox.get(key);
          if (p == null || p.lojaId != lid) continue;
          if (p.idFirebase == produtoId || p.slug == produtoId) {
            existente = p;
            break;
          }
        }

        if (existente != null) {
          existente
            ..idFirebase = produto.idFirebase
            ..nome = produto.nome
            ..quantidade = produto.quantidade
            ..tamanhos = produto.tamanhos
            ..estoquePorTamanho = produto.estoquePorTamanho
            ..variacoes = produto.variacoes
            ..variacoesExtraTipo = produto.variacoesExtraTipo
            ..precoPorTamanho = produto.precoPorTamanho
            ..updatedAt = produto.updatedAt
            ..slug = produto.slug;
          existente.recalcularQuantidadeTotal();
          await existente.save();
          logD(
            '[ESTOQUE_HYDRATE] Produto $produtoId atualizado do Firestore → Hive (refresh)',
          );
        } else {
          await produtosBox.add(produto);
          logD(
            '[ESTOQUE_HYDRATE] Produto $produtoId carregado do Firestore → Hive',
          );
        }
      } catch (e, st) {
        logW(
          '[ESTOQUE_HYDRATE] Falha ao hidratar $produtoId (type=${e.runtimeType})',
          tag: 'ESTOQUE_HYDRATE',
        );
        if (kDebugMode) logD('$st');
      }
    }
  }

  static List<String> _dedupeStringListPreserveOrder(List<String>? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final e in raw) {
      final t = e.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      out.add(t);
    }
    return out;
  }

  /// Pull `estoque_produtos`: evita sobrescrever edição local quando o Hive
  /// foi modificado **depois** do `updatedAt` remoto (push atrasado/falho antes do próximo pull).
  static bool shouldPreserveLocalQuantidadeOnFirestorePull({
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  }) {
    return shouldPreserveLocalEditsOnFirestorePull(
      localUpdatedAt: localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt,
    );
  }

  @visibleForTesting
  static bool shouldPreserveLocalEditsOnFirestorePull({
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  }) {
    if (localUpdatedAt == null) return false;
    if (remoteUpdatedAt == null) return true;
    return localUpdatedAt.isAfter(remoteUpdatedAt);
  }

  /// Pull com guard de quantidade: ainda aplicar código de barras remoto quando
  /// o local está vazio ou desatualizado (cross-device).
  static void mergeRemoteCodigoBarrasWhenPreservingLocalEdits({
    required Produto local,
    required Map<String, dynamic> remoteData,
  }) {
    if (!remoteData.containsKey('codigoBarras')) return;
    final remote = (remoteData['codigoBarras'] ?? '').toString().trim();
    if (remote.isEmpty) return;
    final localCode = local.codigoBarras.trim();
    if (localCode.isEmpty) {
      local.codigoBarras = remote;
    }
  }

  /// Push: não sobrescrever remoto mais novo com Hive stale.
  ///
  /// Usa [updatedAtBeforeBump] (capturado antes de `bumpHiveTimestamp`) para que
  /// `bump=true` não mascare conteúdo antigo com timestamp local fresco.
  /// [forcePushFromCadastro] só no save explícito do formulário.
  @visibleForTesting
  static bool shouldSkipStaleProdutoPushOnAutoSync({
    required Produto local,
    required Map<String, dynamic>? existingData,
    required bool bumpHiveTimestamp,
    DateTime? updatedAtBeforeBump,
    bool forcePushFromCadastro = false,
  }) {
    if (forcePushFromCadastro) return false;
    if (existingData == null || existingData.isEmpty) return false;

    // Mutação de estoque pendente no Hive deve conseguir push (R8.4).
    if (hasPendingStockMutation(local)) return false;

    if (evaluatePushStockSkip(
      local: local,
      existingData: existingData,
      forcePushFromCadastro: false,
    )) {
      return true;
    }

    // Baseline aae9c74: produto stale por updatedAt (combo/convergência, cadastro).
    final remoteAt = parseFirestoreUpdatedAt(existingData) ??
        _firestoreUpdatedAtToDate(existingData['updatedAt']);
    final localAt = updatedAtBeforeBump ?? local.updatedAt;
    if (localAt == null || remoteAt == null) return false;
    return remoteAt.isAfter(localAt.add(const Duration(seconds: 2)));
  }

  static DateTime? parseFirestoreUpdatedAt(Map<String, dynamic> data) {
    final u = data['updatedAt'];
    return u is Timestamp ? u.toDate() : null;
  }

  static DateTime? parseFirestoreStockUpdatedAt(Map<String, dynamic> data) {
    final u = data[kProdutoStockUpdatedAtField];
    return u is Timestamp ? u.toDate() : null;
  }

  /// Pull: regressão de grade remota (por célula) sem janela temporal arbitrária.
  @visibleForTesting
  static bool shouldPreserveLocalStockOnRemoteRegression({
    required Produto local,
    required Map<String, dynamic> remoteData,
  }) {
    final decision = evaluatePullStockMerge(
      local: local,
      remoteData: remoteData,
      remoteStockUpdatedAt: parseFirestoreStockUpdatedAt(remoteData),
      localStockUpdatedAt: local.stockUpdatedAt,
      localStockUpdatedAtServer: local.stockUpdatedAtServer,
    );
    return decision == PullStockMergeDecision.preserveLocalGrade;
  }

  static DateTime? _maxDateTime(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static void _dlog(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(msg);
    }
  }

  /// Mapas sempre serializados (vazios = limpar no remoto com `merge: true`).
  static Map<String, dynamic> _variacoesParaFirestorePush(Produto p) {
    if (p.variacoes != null && p.variacoes!.isNotEmpty) {
      return sanitizeVariacoesForFirestore(
          Map<String, dynamic>.from(p.variacoes!));
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic> sanitizeVariacoesForFirestore(
    Map<String, dynamic> variacoes,
  ) {
    return ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(variacoes);
  }

  static Map<String, dynamic> _variacoesExtraTipoParaFirestorePush(Produto p) {
    if (p.variacoesExtraTipo != null && p.variacoesExtraTipo!.isNotEmpty) {
      return ProdutoVariacaoExtra.sanitizeVariacoesExtraTipoMapForFirestore(
        Map<String, dynamic>.from(p.variacoesExtraTipo!),
      );
    }
    return <String, dynamic>{};
  }

  static Map<String, int> _estoquePorTamanhoParaFirestorePush(Produto p) {
    if (p.estoquePorTamanho.isNotEmpty) {
      return Map<String, int>.from(p.estoquePorTamanho);
    }
    return <String, int>{};
  }

  static Map<String, double>? _sanitizePrecoPorTamanhoForFirestore(
    Map<String, double>? src,
  ) {
    if (src == null || src.isEmpty) return null;
    final out = <String, double>{};
    for (final e in src.entries) {
      final key = e.key.toString().trim();
      if (key.isEmpty) continue;
      final v = e.value;
      if (v > 0) out[key] = v;
    }
    return out.isEmpty ? null : out;
  }

  static bool shouldClearPrecoPorTamanhoBeforeMerge(
    Map<String, double>? precoPorTamanhoPush,
  ) {
    return precoPorTamanhoPush != null && precoPorTamanhoPush.isNotEmpty;
  }

  /// Sincroniza um produto para o Firestore (Hive → Firestore).
  ///
  /// Chamado após salvar no cadastro (produto/combo/catálogo), import e fluxos que alteram
  /// o registro manualmente — mantém a nuvem alinhada à edição local.
  static Future<void> syncProduto(
    Produto produto, {
    String? lojaId,

    /// Quando false, não grava Hive só para atualizar [Produto.updatedAt] após a nuvem
    /// (evita re-disparar [ProdutoAutoSyncService] em loop). Upload de imagem / novo
    /// [Produto.idFirebase] continuam persistindo no Hive.
    bool bumpHiveTimestamp = true,

    /// Save explícito do cadastro: ignora guard de push stale.
    bool forcePushFromCadastro = false,

    /// Metadado de auditoria opcional (não commitar em produção sem aprovação).
    String? writeOrigin,
  }) async {
    await syncProdutoComStatus(
      produto,
      lojaId: lojaId,
      bumpHiveTimestamp: bumpHiveTimestamp,
      forcePushFromCadastro: forcePushFromCadastro,
      writeOrigin: writeOrigin,
      enqueueOnFailure: true,
    );
  }

  /// Apenas testes: falhas forçadas antes do sync real (enfileira / retentativa).
  @visibleForTesting
  static int debugForceSyncFailureRemaining = 0;

  /// Apenas testes: contagem de execuções reais de upsert_produtos_live_inline.
  @visibleForTesting
  static int debugInlineUpsertCallCount = 0;

  /// Último erro sanitizado do ciclo de sync (UI / fila).
  static String? ultimoErroSyncSanitizado;

  /// Falhas parciais de upsert em draft/live no último ciclo de sync do cadastro.
  static List<ProdutoCatalogoUpsertFalha> ultimasFalhasUpsertCatalogo = [];

  static void limparFalhasUpsertCatalogo() {
    ultimasFalhasUpsertCatalogo = [];
  }

  static List<ProdutoCatalogoUpsertFalha> get falhasUpsertCatalogo =>
      List<ProdutoCatalogoUpsertFalha>.unmodifiable(ultimasFalhasUpsertCatalogo);

  static bool get temFalhasUpsertCatalogo =>
      ultimasFalhasUpsertCatalogo.isNotEmpty;

  /// Falhas canônicas (draft/live) do attemptId ativo — para snackbar do formulário.
  static List<ProdutoCatalogoUpsertFalha> falhasCanonicalDoAttempt(
    String? attemptId,
  ) {
    return ultimasFalhasUpsertCatalogo
        .where(
          (f) =>
              f.isCanonicalCatalogo &&
              attemptId != null &&
              attemptId.isNotEmpty &&
              f.attemptId == attemptId,
        )
        .toList(growable: false);
  }

  static void registrarFalhaUpsertCatalogo({
    required String lojaId,
    required String produtoId,
    required String path,
    required String operacao,
    required Object error,
    String? attemptId,
    String? origin,
  }) {
    final falha = ProdutoCatalogoUpsertFalha(
      lojaId: lojaId,
      produtoId: produtoId,
      path: path,
      operacao: operacao,
      erro: ProdutoCatalogoUpsertFalha.erroDe(error),
      attemptId: attemptId,
      origin: origin,
      timestampUtc: DateTime.now().toUtc(),
    );
    ultimasFalhasUpsertCatalogo = [...ultimasFalhasUpsertCatalogo, falha];
    logE(
      '[CATALOGO_UPSERT_FAIL] lojaId=$lojaId produtoId=$produtoId '
      'path=$path operacao=$operacao erro=${falha.erro}',
      tag: 'CATALOGO_UPSERT_FAIL',
    );
  }

  static void _applyGradeRehydrateDecisionToProduto({
    required Produto produto,
    required Map<String, dynamic> remoteData,
    required ProdutoEstoqueGradeRehydrateResult gradeDecision,
  }) {
    if (gradeDecision.aplicarGradeRemota) {
      _applyRemoteGradeToProdutoForRehydrate(
        produto: produto,
        existingData: remoteData,
      );
      return;
    }
    if (gradeDecision.variacoes == null ||
        gradeDecision.estoquePorTamanho == null) {
      return;
    }
    produto.variacoes = gradeDecision.variacoes!.isNotEmpty
        ? Map<String, dynamic>.from(gradeDecision.variacoes!)
        : null;
    produto.variacoesExtraTipo = gradeDecision.variacoesExtraTipo;
    produto.estoquePorTamanho =
        Map<String, int>.from(gradeDecision.estoquePorTamanho!);
    if (gradeDecision.tamanhos != null &&
        gradeDecision.tamanhos!.isNotEmpty) {
      produto.tamanhos = List<String>.from(gradeDecision.tamanhos!);
    }
    if (gradeDecision.precoPorTamanho != null) {
      produto.precoPorTamanho = gradeDecision.precoPorTamanho;
    }
  }

  @visibleForTesting
  static bool deveAtualizarGradeRemotaAoAbrirForm({
    required Produto local,
    required Map<String, dynamic> remoteData,
  }) {
    final remoteV = remoteData['variacoes'];
    final remoteE = remoteData['estoquePorTamanho'];
    if (remoteV is! Map || remoteV.isEmpty) return false;
    if (remoteE is! Map || remoteE.isEmpty) return false;

    final localRaw = local.variacoes;
    if (localRaw == null || localRaw.isEmpty) {
      return true;
    }
    final localV = Map<String, dynamic>.from(localRaw);
    final remoteMap = Map<String, dynamic>.from(remoteV);
    final localTam = localV.keys.map((k) => k.toString()).toSet();
    final remoteTam = remoteMap.keys.map((k) => k.toString()).toSet();
    if (localTam.every(remoteTam.contains) && localTam.length < remoteTam.length) {
      return true;
    }
    return remoteTam.length > localTam.length &&
        localTam.every(remoteTam.contains);
  }

  /// Ao abrir o formulário: se Hive tem grade parcial e remoto tem mais tamanhos,
  /// mescla a grade canônica antes de montar os controllers.
  static Future<bool> refreshGradeFromEstoqueRemotoAoAbrirForm({
    required Produto produto,
    required String lojaId,
  }) async {
    final storeId = lojaId.trim();
    final produtoId = produto.idFirebase.trim().isNotEmpty
        ? produto.idFirebase.trim()
        : produto.slug.trim();
    if (storeId.isEmpty || produtoId.isEmpty) return false;

    try {
      final snap = await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      if (!snap.exists) return false;
      final data = Map<String, dynamic>.from(snap.data() ?? {});
      if (!deveAtualizarGradeRemotaAoAbrirForm(local: produto, remoteData: data)) {
        return false;
      }

      final baseline = ProdutoFormGradeBaseline.capture(produto);
      final gradeDecision =
          ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: produto,
        remoteData: data,
        baseline: baseline,
      );

      ProdutoRemoteSyncGuard.applyingRemoteToHive = true;
      try {
        _applyGradeRehydrateDecisionToProduto(
          produto: produto,
          remoteData: data,
          gradeDecision: gradeDecision,
        );
        produto.recalcularQuantidadeTotal();
        await produto.save();
      } finally {
        ProdutoRemoteSyncGuard.applyingRemoteToHive = false;
      }

      logD(
        '[FORM_OPEN_GRADE_REFRESH] grade alinhada ao abrir form '
        'produtoId=$produtoId linhasTam='
        '${produtoFormColetarTamanhosGradeAlvo(produto).length}',
        tag: 'FORM_OPEN_GRADE_REFRESH',
      );
      return true;
    } catch (e) {
      logW(
        '[FORM_OPEN_GRADE_REFRESH] falha produtoId=$produtoId '
        '${e.runtimeType}',
        tag: 'FORM_OPEN_GRADE_REFRESH',
      );
      return false;
    }
  }

  /// Após save confirmado em estoque_produtos, alinha Hive com o doc remoto canônico.
  static Future<ProdutoRehydratePosSaveResult>
      rehydrateProdutoConfirmadoFromEstoqueRemoto(
    Produto produto, {
    required String lojaId,
    ProdutoFormGradeBaseline? gradeBaseline,
  }) async {
    final storeId = lojaId.trim();
    final produtoId = produto.idFirebase.trim().isNotEmpty
        ? produto.idFirebase.trim()
        : produto.slug.trim();
    if (storeId.isEmpty || produtoId.isEmpty) {
      return const ProdutoRehydratePosSaveResult(
        sucesso: false,
        aviso: 'identificador ausente para reidratação',
      );
    }

    try {
      final snap = await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .get();
      if (!snap.exists) {
        return const ProdutoRehydratePosSaveResult(
          sucesso: false,
          aviso: 'documento estoque_produtos ausente após save',
        );
      }
      final data = Map<String, dynamic>.from(snap.data() ?? {});
      final gradeDecision =
          ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: produto,
        remoteData: data,
        baseline: gradeBaseline,
      );
      await _applyEstoqueRemotoConfirmadoToProdutoLocal(
        produto,
        data,
        gradeDecision: gradeDecision,
      );
      logD(
        '[REHYDRATE_POS_SAVE] Hive alinhado com estoque_produtos/$produtoId '
        'gradeRemota=${gradeDecision.aplicarGradeRemota} '
        'aviso=${gradeDecision.aviso ?? '-'}',
        tag: 'REHYDRATE_POS_SAVE',
      );
      return ProdutoRehydratePosSaveResult(
        sucesso: true,
        aviso: gradeDecision.aviso,
      );
    } catch (e, st) {
      final aviso = ProdutoSyncErroUtil.sanitizar(e);
      logE(
        '[REHYDRATE_POS_SAVE] falha estoque_produtos/$produtoId '
        '${aviso ?? e.runtimeType}',
        tag: 'REHYDRATE_POS_SAVE',
        error: e,
        st: st,
      );
      return ProdutoRehydratePosSaveResult(
        sucesso: false,
        aviso: aviso ?? 'falha ao ler estoque remoto',
      );
    }
  }

  static Future<void> _applyEstoqueRemotoConfirmadoToProdutoLocal(
    Produto produto,
    Map<String, dynamic> data, {
    ProdutoEstoqueGradeRehydrateResult? gradeDecision,
  }) async {
    ProdutoRemoteSyncGuard.applyingRemoteToHive = true;
    try {
      produto.descricao = (data['descricao'] ?? produto.descricao).toString();
      produto.quantidade =
          (data['quantidade'] as num?)?.toInt() ?? produto.quantidade;
      produto.nome = (data['nome'] ?? produto.nome).toString();
      produto.precoFinal =
          (data['preco'] as num?)?.toDouble() ?? produto.precoFinal;
      produto.precoUnitario = (data['precoUnitario'] as num?)?.toDouble() ??
          (data['preco'] as num?)?.toDouble() ??
          produto.precoUnitario;
      produto.publicadoNoCatalogo =
          data['publicadoNoCatalogo'] == true || produto.publicadoNoCatalogo;
      ProdutoCustoGuard.applyRemoteCustoOnExistingProduct(
        local: produto,
        remoteData: data,
        logContext: 'rehydrate_pos_save',
      );
      if (gradeDecision != null) {
        _applyGradeRehydrateDecisionToProduto(
          produto: produto,
          remoteData: data,
          gradeDecision: gradeDecision,
        );
      } else {
        _applyRemoteGradeToProdutoForRehydrate(
          produto: produto,
          existingData: data,
        );
      }
      final uAt = data['updatedAt'];
      if (uAt is Timestamp) {
        produto.updatedAt = uAt.toDate();
      }
      await produto.save();
    } finally {
      ProdutoRemoteSyncGuard.applyingRemoteToHive = false;
    }
  }

  static Future<ProdutoSyncRemotoStatus> syncProdutoComStatus(
    Produto produto, {
    String? lojaId,
    bool bumpHiveTimestamp = true,
    bool forcePushFromCadastro = false,
    String? writeOrigin,
    bool enqueueOnFailure = true,
    ProdutoFormGradeBaseline? gradeBaseline,
    CatalogoSyncAttemptContext? catalogoDiagContext,
    CatalogoLiveInlinePolicy catalogoLiveInlinePolicy =
        CatalogoLiveInlinePolicy.executar,
  }) async {
    ultimoErroSyncSanitizado = null;
    limparFalhasUpsertCatalogo();
    try {
      if (debugForceSyncFailureRemaining > 0) {
        debugForceSyncFailureRemaining--;
        throw Exception('debug: sync produto forçado a falhar (teste)');
      }

      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) {
        logD('❌ [PRODUTOS-SYNC] LojaId vazio, não pode sincronizar');
        ultimoErroSyncSanitizado = ProdutoSyncErroUtil.sanitizar(
          null,
          status: ProdutoSyncRemotoStatus.lojaInvalida,
        );
        return ProdutoSyncRemotoStatus.lojaInvalida;
      }

      final produtoIdRaw = produto.idFirebase.isNotEmpty
          ? produto.idFirebase
          : produto.slug.isNotEmpty
              ? produto.slug
              : DateTime.now().millisecondsSinceEpoch.toString();

      final idValidation = ProdutoFirestoreDocIdValidator.validate(
        storeId: storeId,
        produtoId: produtoIdRaw,
      );
      if (!idValidation.ok) {
        logW(
          '[PRODUTOS-SYNC] docId inválido (${idValidation.code}) — push abortado',
          tag: 'PRODUTO_ID',
        );
        ultimoErroSyncSanitizado = idValidation.sanitizedMessage ??
            ProdutoSyncErroUtil.sanitizar(
              null,
              status: ProdutoSyncRemotoStatus.produtoInvalido,
            );
        return ProdutoSyncRemotoStatus.produtoInvalido;
      }

      var produtoId = produtoIdRaw.trim();

      final prep = await ProdutoImportSyncPrepService.prepareBeforeRemotePush(
        produto: produto,
        lojaId: storeId,
      );
      if (prep.recuperacaoManual) {
        ultimoErroSyncSanitizado = prep.mensagem ??
            'Produto requer recuperação manual antes da sincronização.';
        return ProdutoSyncRemotoStatus.recuperacaoManualNecessaria;
      }
      if (prep.tentativasEsgotadas) {
        ultimoErroSyncSanitizado = prep.mensagem ??
            'Não foi possível sincronizar o produto importado.';
        return ProdutoSyncRemotoStatus.falhaRemota;
      }

      produtoId = produto.idFirebase.isNotEmpty
          ? produto.idFirebase.trim()
          : produto.slug.trim();

      await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(storeId);
      if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
        lojaId: storeId,
        estoqueDocId: produtoId,
      )) {
        logW(
          '[TOMBSTONE_BLOCK] upsert bloqueado — produto excluído: $produtoId',
          tag: 'TOMBSTONE',
        );
        ultimoErroSyncSanitizado = ProdutoSyncErroUtil.sanitizar(
          null,
          status: ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone,
        );
        return ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone;
      }

      // 📸 Fazer upload das imagens locais para Firebase Storage
      final imagensFinais = <String>[];
      bool imagensAtualizadas = false;

      for (final imagemPath in produto.imagens) {
        if (ImageUploadService.isLocalPath(imagemPath)) {
          logD(
              '📤 [PRODUTOS-SYNC] Fazendo upload da imagem (ficheiro original): $imagemPath');
          final url = await ImageUploadService.uploadImage(
            imagePath: imagemPath,
            folder: 'produtos',
            lojaId: storeId,
          );
          if (url != null) {
            imagensFinais.add(url);
            imagensAtualizadas = true;
          } else {
            imagensFinais.add(imagemPath);
          }
        } else if (ImageUploadService.isFirebaseUrl(imagemPath)) {
          imagensFinais.add(imagemPath);
        } else if (_isDataImageUrl(imagemPath)) {
          // data:image/... (base64) - fazer upload para Firebase Storage
          final url = await _uploadDataImageUrl(imagemPath, storeId);
          if (url != null) {
            imagensFinais.add(url);
            imagensAtualizadas = true;
          } else {
            imagensFinais.add(imagemPath);
          }
        } else if (_isBlobUrl(imagemPath)) {
          // Web: tentar buscar bytes da blob URL e fazer upload para Firebase
          bool blobConvertido = false;
          if (kIsWeb) {
            try {
              final bytes = await blob_fetch
                  .fetchBlobUrlAsBytes(imagemPath)
                  .timeout(const Duration(seconds: 15), onTimeout: () => null);
              if (bytes != null && bytes.isNotEmpty) {
                final url = await ImageUploadService.uploadImageFromBytes(
                  bytes: bytes,
                  folder: 'produtos',
                  lojaId: storeId,
                  extension: 'jpg',
                  contentType: 'image/jpeg',
                ).timeout(const Duration(seconds: 45), onTimeout: () => null);
                if (url != null) {
                  imagensFinais.add(url);
                  imagensAtualizadas = true;
                  blobConvertido = true;
                  logD(
                      '[PRODUTOS-SYNC] blob: URL convertida para Firebase: $url');
                }
              }
            } catch (_) {
              logW('[PRODUTOS-SYNC] blob: falha ao converter: $imagemPath');
            }
          }
          if (!blobConvertido) {
            logW(
                '[PRODUTOS-SYNC] blob: URL ignorada (não persiste fora do browser): $imagemPath');
          }
        } else {
          imagensFinais.add(imagemPath);
        }
      }

      // Se as imagens foram atualizadas, salvar no produto local
      if (imagensAtualizadas) {
        produto.imagens = imagensFinais;
        await produto.save();
        logD(
            '✅ [PRODUTOS-SYNC] Imagens atualizadas no Hive com URLs do Firebase');
      }

      final updatedAtBeforeBump = produto.updatedAt;

      if (bumpHiveTimestamp) {
        produto.updatedAt = DateTime.now();
        await produto.save();
      }

      final docRef = _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId);
      final docSnap = await docRef.get();
      final existingData = docSnap.data();
      final dynamic createdAtPersistido = existingData?['createdAt'];

      if (shouldSkipStaleProdutoPushOnAutoSync(
        local: produto,
        existingData: docSnap.exists ? existingData : null,
        bumpHiveTimestamp: bumpHiveTimestamp,
        updatedAtBeforeBump: updatedAtBeforeBump,
        forcePushFromCadastro: forcePushFromCadastro,
      )) {
        logW(
          '[PUSH_EDIT_GUARD] push ignorado — remoto mais recente que Hive '
          '(doc=$produtoId bump=$bumpHiveTimestamp '
          'localBeforeBump=$updatedAtBeforeBump forceCadastro=$forcePushFromCadastro)',
          tag: 'PUSH_EDIT_GUARD',
        );
        return ProdutoSyncRemotoStatus.semMudancas;
      }

      // Não registrar tombstone de variação via diff remoto×local no sync geral: payload
      // local pode estar incompleto (pull parcial, import, race) e marcar célula ativa como "excluída".

      final unfilteredVariacoes = _variacoesParaFirestorePush(produto);
      final unfilteredExtra = _variacoesExtraTipoParaFirestorePush(produto);
      final unfilteredEstoque = _estoquePorTamanhoParaFirestorePush(produto);

      // Sempre enviar mapas explícitos (vazios = limpar com merge:true).
      var variacoesPush = ProdutoExclusaoTombstoneService.filtrarMapVariacoes(
        storeId,
        produtoId,
        unfilteredVariacoes,
      );
      var variacoesExtraPush =
          ProdutoExclusaoTombstoneService.filtrarVariacoesExtraTipo(
        storeId,
        produtoId,
        unfilteredExtra,
      );
      var estoquePorTamPush =
          ProdutoExclusaoTombstoneService.filtrarEstoquePorTamanho(
        storeId,
        produtoId,
        unfilteredEstoque,
      );
      var precoPorTamanhoPush =
          _sanitizePrecoPorTamanhoForFirestore(produto.precoPorTamanho);

      final gradeCompleted =
          ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: storeId,
        produtoId: produtoId,
        variacoesPush: variacoesPush,
        variacoesExtraPush: variacoesExtraPush,
        estoquePorTamPush: estoquePorTamPush,
        tamanhosPush: List<String>.from(produto.tamanhos),
        precoPorTamanhoPush: precoPorTamanhoPush,
        quantidade: produto.quantidade,
        existingEstoqueData: docSnap.exists ? existingData : null,
        localUnfilteredVariacoes: unfilteredVariacoes,
        localUnfilteredEstoque: unfilteredEstoque,
        localUnfilteredExtra: unfilteredExtra,
        localUnfilteredTamanhos: List<String>.from(produto.tamanhos),
        baseline: gradeBaseline,
      );
      variacoesPush = gradeCompleted.variacoes;
      variacoesExtraPush = gradeCompleted.variacoesExtraTipo;
      estoquePorTamPush = gradeCompleted.estoquePorTamanho;
      precoPorTamanhoPush =
          gradeCompleted.precoPorTamanho ?? precoPorTamanhoPush;

      logD(
        '[VARIACAO_CLEAR] push estoque_produtos/$produtoId '
        'variacoesKeys=${variacoesPush.length} extraKeys=${variacoesExtraPush.length} '
        'estoquePorTamKeys=${estoquePorTamPush.length} '
        'gradeAcao=${gradeCompleted.acao ?? 'none'} '
        'gradeOrigem=${gradeCompleted.origem ?? '-'}',
      );

      final resolvedVariationPush = resolveVariationFieldsForFirestorePush(
        local: produto,
        existingData: docSnap.exists ? existingData : null,
        variacoesPush: variacoesPush,
        variacoesExtraPush: variacoesExtraPush,
        estoquePorTamPush: estoquePorTamPush,
        precoPorTamanhoPush: precoPorTamanhoPush,
      );
      if (resolvedVariationPush.rehydrateLocalFromRemote && existingData != null) {
        await _rehydrateLocalGradeFromRemoteOnStalePush(produto, existingData);
      }
      final variacoesPushEfetivo = resolvedVariationPush.variacoes;
      final variacoesExtraPushEfetivo = resolvedVariationPush.variacoesExtraTipo;
      final estoquePorTamPushEfetivo = resolvedVariationPush.estoquePorTamanho;
      final precoPorTamanhoPushEfetivo = resolvedVariationPush.precoPorTamanho;
      final tamanhosPushEfetivo = gradeCompleted.tamanhos.isNotEmpty
          ? gradeCompleted.tamanhos
          : resolvedVariationPush.tamanhos;

      final produtoData = {
        'id': produtoId,
        'lojaId': storeId,
        'nome': produto.nome,
        'preco': produto.precoFinal,
        'quantidade': produto.quantidade,
        'categoria': produto.categoria,
        'subcategoria': produto.subcategoria,
        'categoriasExtras': produto.categoriasExtras,
        'subcategoriasExtras': produto.subcategoriasExtras,
        'descricao': produto.descricao,
        'imagens': imagensFinais, // ✅ Usa URLs do Firebase
        'slug': produto.slug,
        'tamanhos': tamanhosPushEfetivo,
        'publicadoNoCatalogo': produto.publicadoNoCatalogo,
        'custoReal': produto.custoReal,
        'precoUnitario': produto.precoUnitario,
        'frete': produto.frete,
        'gastosFixos': produto.gastosFixos,
        'gastosVariaveis': produto.gastosVariaveis,
        'precoSugerido': produto.precoSugerido,
        'peso': produto.peso,
        'tipoEmbalagem': produto.tipoEmbalagem,
        'custoEditadoNoCadastro': produto.custoEditadoNoCadastro,

        // Promoção
        'emPromocao': produto.emPromocao,
        'percentualPromo': produto.percentualPromo,
        'valorPromo': produto.valorPromo,
        'dataInicioPromo': produto.dataInicioPromo != null
            ? Timestamp.fromDate(produto.dataInicioPromo!)
            : null,
        'dataFimPromo': produto.dataFimPromo != null
            ? Timestamp.fromDate(produto.dataFimPromo!)
            : null,

        // Variações (tamanho + cor) — aplicadas via [applyVariationFieldsToFirestorePayload]
        'cores': produto.cores,
        'tipoProduto': produto.tipoProduto,
        // itensCombo omitido quando vazio: merge não apaga chave no Firestore.
        // Limpeza remota explícita: enviar []. Pull: applyComboMetadataPullForExisting.
        if (produto.itensCombo != null && produto.itensCombo!.isNotEmpty)
          'itensCombo': produto.itensCombo,
        if (produto.comboConfig != null &&
            ComboConfigCanonical.isEffective(produto.comboConfig))
          'comboConfig': produto.comboConfig,

        'divideSemJuros': produto.divideSemJuros,
        'percentualDescontoPix': produto.percentualDescontoPix,
        'maxParcelasSemJuros': produto.maxParcelasSemJuros,

        'videoUrl': produto.videoUrl.isNotEmpty ? produto.videoUrl : null,
        'codigoBarras':
            produto.codigoBarras.isNotEmpty ? produto.codigoBarras : null,
        'sku': produto.sku.isNotEmpty ? produto.sku : null,
        'estoqueMinimo': produto.estoqueMinimo,
        'fornecedor': produto.fornecedor.isNotEmpty ? produto.fornecedor : null,
        'marketplaces': produto.marketplaces,
        // Campos internos úteis para continuidade multi-dispositivo (admin)
        'dataEntrada': Timestamp.fromDate(produto.dataEntrada),
        'ativoNoRascunho': produto.ativoNoRascunho,

        // Metadata
        'updatedAt': FieldValue.serverTimestamp(),
        if (writeOrigin != null && writeOrigin.isNotEmpty)
          'lastWriteOrigin': writeOrigin,
        if (writeOrigin != null && writeOrigin.isNotEmpty)
          'lastWriteReason': writeOrigin,
        'lastWriteAtClient': Timestamp.fromDate(DateTime.now()),
        'lastWriteBumpHiveTimestamp': bumpHiveTimestamp,
        'lastWritePath': 'lojas/$storeId/${FSPaths.estoqueProdutosCol}/$produtoId',
        'lastWriteBuildId': const String.fromEnvironment(
          'CATALOG_BUILD_ID',
          defaultValue: 'dev',
        ),
      };
      if (docSnap.exists) {
        if (createdAtPersistido != null) {
          produtoData['createdAt'] = createdAtPersistido;
        } else {
          // Fallback conservador para docs legados sem createdAt.
          produtoData['createdAt'] = FieldValue.serverTimestamp();
        }
        _dlog(
            '[ProdutoSync] update estoque_produtos/$produtoId (createdAt preservado)');
      } else {
        produtoData['createdAt'] = FieldValue.serverTimestamp();
        _dlog('[ProdutoSync] create estoque_produtos/$produtoId');
      }

      final variationKeysToRemove = <String>{};
      final preservouGradeRemotaNoPush =
          resolvedVariationPush.rehydrateLocalFromRemote;
      applyVariationFieldsToFirestorePayload(
        produtoData,
        variacoes: variacoesPushEfetivo,
        variacoesExtraTipo: variacoesExtraPushEfetivo,
        estoquePorTamanho: estoquePorTamPushEfetivo,
        precoPorTamanho: precoPorTamanhoPushEfetivo,
        variationKeysToRemove: variationKeysToRemove,
        treatEmptyAsOmitOnly: preservouGradeRemotaNoPush,
      );
      final sanitizeEstoque = sanitizePayloadForFirestore(
        produtoData,
        rootPath: 'estoque_produtos/$produtoId',
        forFullDocumentSet: true,
      );
      if (sanitizeEstoque.adjustedPaths.isNotEmpty) {
        logW(
          '[PRODUTOS-SYNC] payload sanitizado em estoque_produtos/$produtoId: '
          '${sanitizeEstoque.adjustedPaths.join(' | ')}',
        );
      }

      await _upsertProdutoDocument(
        docRef,
        sanitizeEstoque.payload,
        existingData: docSnap.exists ? docSnap.data() : null,
        forceRemoveKeys: variationKeysToRemove,
      );

      // 🔹 TAMBÉM atualizar no catálogo público (produtos) se o produto está publicado
      if (produto.publicadoNoCatalogo) {
        final inlinePath = 'lojas/$storeId/produtos/$produtoId';
        if (catalogoLiveInlinePolicy ==
            CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico) {
          if (catalogoDiagContext != null) {
            await CatalogoSyncDiagnosticsService.skipOperation(
              context: catalogoDiagContext,
              operationName: 'upsert_produtos_live_inline',
              collectionName: 'produtos',
              storeId: storeId,
              produtoId: produtoId,
              path: inlinePath,
              skipReason: 'canonical_post_save',
              sourceMethod: 'ProdutosFirestoreService.syncProdutoComStatus',
            );
          }
          logD(
            '[PRODUTOS-SYNC] inline produtos/$produtoId ignorado — pós-save canônico',
          );
        } else {
          CatalogoSyncOperationHandle? diagHandle;
          CatalogoSyncAttemptContext? inlineDiagContext = catalogoDiagContext;
          if (inlineDiagContext == null) {
            try {
              inlineDiagContext = await CatalogoSyncAttemptContext.capture(
                origin: 'produtos_firestore.inline_fallback',
                sessionStoreIdHint: storeId,
              );
            } catch (_) {}
          }
          try {
            final publicoRef = _db
                .collection('lojas')
                .doc(storeId)
                .collection('produtos')
                .doc(produtoId);
            final publicoData = <String, dynamic>{
              // Campos mínimos para o stream/filtros do catálogo web.
              // Sem esses campos, o doc pode ser ignorado por filtros de publicação.
              'ativo': true,
              'publicar': true,
              'publicadoNoCatalogo': true,
              'nome': produto.nome,
              'descricao': produto.descricao,
              'preco': produto.precoFinal,
              'preco_venda': produto.precoFinal,
              'precoFinal': produto.precoFinal,
              'quantidade': produto.quantidade,
              'estoque': produto.quantidade,
              'estoque_atual': produto.quantidade,
              'qtdEstoque': produto.quantidade,
              'imagens': imagensFinais,
              'slug': produto.slug,
              'cores': produto.cores,
              'categoria': produto.categoria,
              'categoriaId': produto.categoria,
              'subcategoria': produto.subcategoria,
              'subcategoriaId': produto.subcategoria,
              'categoriasExtras': produto.categoriasExtras,
              'subcategoriasExtras': produto.subcategoriasExtras,
              'categoriasAssociadas': produto.categoriasAssociadas,
              'subcategoriasAssociadas': produto.subcategoriasAssociadas,
              'emPromocao': produto.emPromocao,
              'percentualPromo': produto.percentualPromo,
              'valorPromo': produto.valorPromo,
              'peso': produto.peso,
              'tipoEmbalagem': produto.tipoEmbalagem,
              'codigoBarras':
                  produto.codigoBarras.isNotEmpty ? produto.codigoBarras : null,
              'sku': produto.sku.isNotEmpty ? produto.sku : null,
              'estoqueMinimo': produto.estoqueMinimo,
              // Custo e campos internos: removidos no doc final via forceRemoveKeys (set sem merge).
              'marketplaces': produto.marketplaces,
              'divideSemJuros': produto.divideSemJuros,
              'maxParcelasSemJuros': produto.maxParcelasSemJuros,
              'percentualDescontoPix': produto.percentualDescontoPix,
              if (produto.videoUrl.isNotEmpty) 'videoUrl': produto.videoUrl,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            final publicoSnap = await publicoRef.get();
            final publicoVariationKeysToRemove = <String>{};
            applyVariationFieldsToFirestorePayload(
              publicoData,
              variacoes: variacoesPushEfetivo,
              variacoesExtraTipo: variacoesExtraPushEfetivo,
              estoquePorTamanho: estoquePorTamPushEfetivo,
              precoPorTamanho: precoPorTamanhoPushEfetivo,
              variationKeysToRemove: publicoVariationKeysToRemove,
              treatEmptyAsOmitOnly: preservouGradeRemotaNoPush,
            );
            final publicoRemoveKeys = <String>{
              ...publicoVariationKeysToRemove,
              ..._publicoInternoKeysToStrip,
            };
            final sanitizePublico = sanitizePayloadForFirestore(
              publicoData,
              rootPath: 'produtos/$produtoId',
              forFullDocumentSet: true,
            );
            if (sanitizePublico.adjustedPaths.isNotEmpty) {
              logW(
                '[PRODUTOS-SYNC] payload sanitizado em produtos/$produtoId: '
                '${sanitizePublico.adjustedPaths.join(' | ')}',
              );
            }
            if (inlineDiagContext != null) {
              diagHandle = await CatalogoSyncDiagnosticsService.startOperation(
                context: inlineDiagContext,
                operationName: 'upsert_produtos_live_inline',
                collectionName: 'produtos',
                storeId: storeId,
                produtoId: produtoId,
                path: inlinePath,
                firestoreMethod: 'set',
                mutationIntent: CatalogoSyncMutationIntent.set,
                documentStateHint: publicoSnap.exists
                    ? CatalogoSyncDocumentStateHint.knownPresentFromExistingState
                    : CatalogoSyncDocumentStateHint.knownAbsentFromExistingState,
                sourceMethod: 'ProdutosFirestoreService.syncProdutoComStatus',
              );
            }
            debugInlineUpsertCallCount++;
            await _upsertProdutoDocument(
              publicoRef,
              sanitizePublico.payload,
              existingData: publicoSnap.exists ? publicoSnap.data() : null,
              forceRemoveKeys: publicoRemoveKeys,
            );
            if (diagHandle != null) {
              await CatalogoSyncDiagnosticsService.completeSuccess(diagHandle);
            }
            _dlog('[ProdutoPublico] upsert produtos/$produtoId concluído');
            logD('✅ [PRODUTOS-SYNC] Catálogo público (produtos) atualizado');
          } catch (e, st) {
            if (diagHandle != null) {
              await CatalogoSyncDiagnosticsService.completeFailure(
                diagHandle,
                e,
              );
            }
            registrarFalhaUpsertCatalogo(
              lojaId: storeId,
              produtoId: produtoId,
              path: inlinePath,
              operacao: 'upsert_produtos_live_inline',
              error: e,
              attemptId: inlineDiagContext?.attemptId,
              origin: inlineDiagContext?.origin,
            );
            logE(
              '⚠️ [PRODUTOS-SYNC] Falha ao atualizar produtos/$produtoId '
              '(estoque já salvo) type=${e.runtimeType}',
              tag: 'CATALOGO_UPSERT_FAIL',
              error: e,
              st: st,
            );
          }
        }
      }

      // Atualizar idFirebase no produto local se estava vazio
      if (produto.idFirebase.isEmpty) {
        produto.idFirebase = produtoId;
        await produto.save();
        logD('🔄 [PRODUTOS-SYNC] idFirebase atualizado: $produtoId');
      }

      logD('✅ [PRODUTOS-SYNC] Produto ${produto.nome} sincronizado');
      return ProdutoSyncRemotoStatus.confirmado;
    } catch (e, st) {
      ultimoErroSyncSanitizado = ProdutoSyncErroUtil.sanitizar(e);
      if (e is FirebaseException && e.code == 'invalid-argument') {
        final detalhe = e.message?.trim();
        if (detalhe != null && detalhe.isNotEmpty) {
          ultimoErroSyncSanitizado = 'invalid-argument ($detalhe)';
        }
      }
      if (e is FormatException) {
        ultimoErroSyncSanitizado = e.message;
      }
      logE(
          '❌ [PRODUTOS-SYNC] Erro ao sincronizar produto (type=${e.runtimeType})'
          '${ultimoErroSyncSanitizado != null ? " detalhe=$ultimoErroSyncSanitizado" : ""}',
          error: e,
          st: st);
      if (!enqueueOnFailure) {
        return ProdutoSyncRemotoStatus.falhaRemota;
      }
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      final key = produto.key;
      final boxName = produto.box?.name ??
          (storeId != null ? HiveBoxNames.produtos(storeId) : null);
      if (storeId != null && key != null && boxName != null) {
        final parsedKey = key is int ? key : int.tryParse(key.toString());
        if (parsedKey == null) {
          ultimoErroSyncSanitizado = ProdutoSyncErroUtil.sanitizar(
            null,
            status: ProdutoSyncRemotoStatus.produtoInvalido,
          );
          return ProdutoSyncRemotoStatus.produtoInvalido;
        }
        await SyncQueueService.enqueue(
          type: SyncOperationType.upsertProduto,
          lojaId: storeId,
          boxName: boxName,
          entityKey: parsedKey,
          lastError: ultimoErroSyncSanitizado,
          catalogoPublishPlan:
              catalogoLiveInlinePolicy ==
                      CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico
                  ? CatalogoQueuePublishPlan.canonicoAposEstoque
                  : CatalogoQueuePublishPlan.legadoInline,
          catalogoPublishPhase: CatalogoQueuePublishPhase.aguardandoEstoque,
          catalogoQueueSourceOrigin: CatalogoQueueSourceOrigins.sanitizar(
            writeOrigin,
          ),
        );
        return ProdutoSyncRemotoStatus.pendenteFila;
      }
      return ProdutoSyncRemotoStatus.falhaRemota;
    }
  }

  static bool _isDataImageUrl(String? s) =>
      s != null && s.trim().startsWith('data:image');

  static bool _isBlobUrl(String? s) =>
      s != null && s.trim().toLowerCase().startsWith('blob:');

  static Future<String?> _uploadDataImageUrl(
      String dataUrl, String lojaId) async {
    try {
      final uri = Uri.parse(dataUrl.trim());
      final data = uri.data;
      if (data == null) return null;
      final bytes = Uint8List.fromList(data.contentAsBytes());
      final ext = data.mimeType.split('/').last;
      final path =
          'lojas/$lojaId/produtos/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        bytes,
        SettableMetadata(contentType: data.mimeType),
      );
      return await ref.getDownloadURL();
    } catch (e) {
      logE(
          '[PRODUTOS-SYNC] Erro ao fazer upload de data:image (type=${e.runtimeType})');
      return null;
    }
  }

  /// Sincroniza apenas produtos cujas chaves Hive foram alteradas (ex.: ações em lote na tela de estoque).
  static Future<void> syncProdutosPorChavesHive({
    required Box<Produto> box,
    required String lojaId,
    required Iterable<int> hiveKeys,
  }) async {
    for (final k in hiveKeys) {
      final produto = box.get(k);
      if (produto == null) continue;
      if (produto.lojaId.isNotEmpty && produto.lojaId != lojaId) continue;
      try {
        await syncProduto(produto, lojaId: lojaId);
      } catch (e, st) {
        logE(
            '❌ [PRODUTOS-SYNC] Erro sync item hiveKey=$k (type=${e.runtimeType})',
            error: e,
            st: st);
      }
    }
  }

  /// Sincroniza todos os produtos locais para o Firestore (Hive → Firestore)
  static Future<void> syncTodosProdutos(
      {required String boxName, required String lojaId}) async {
    try {
      logD('🔄 [PRODUTOS-SYNC] Iniciando sync de todos os produtos...');

      final box = await Hive.openBox<Produto>(boxName);
      int synced = 0;
      int errors = 0;

      for (int i = 0; i < box.length; i++) {
        final produto = box.getAt(i);
        if (produto != null && produto.lojaId == lojaId) {
          try {
            await syncProduto(produto, lojaId: lojaId);
            synced++;
          } catch (e, st) {
            errors++;
            logE('❌ [PRODUTOS-SYNC] Erro no produto (type=${e.runtimeType})',
                error: e, st: st);
          }
        }
      }

      logD(
          '✅ [PRODUTOS-SYNC] Sync completo: $synced produtos sincronizados, $errors erros');
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro geral (type=${e.runtimeType})',
          error: e, st: st);
    }
  }

  /// Sincroniza produtos do Firestore para o Hive (Firestore → Hive)
  /// Usa paginação para buscar TODOS os produtos (evita limit 1000 cortar a lista).
  static Future<int> syncFirestoreToHive({
    required String lojaId,
    required Box<Produto> produtosBox,

    /// Quando verdadeiro (ex.: "Baixar da nuvem"), aplica [quantidade] do Firestore mesmo
    /// com sync pendente na fila ou `updatedAt` local mais recente — evita ficar preso
    /// em valor antigo no dispositivo após alterações na web.
    bool preferRemoteQuantity = false,
  }) async {
    ProdutoRemoteSyncGuard.applyingRemoteToHive = true;
    try {
      logD('🔄 [PRODUTOS-SYNC] Sincronizando produtos do Firestore → Hive...');

      const batchSize = 500;
      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      DocumentSnapshot<Map<String, dynamic>>? lastDoc;

      while (true) {
        Query<Map<String, dynamic>> query = _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .orderBy(FieldPath.documentId)
            .limit(batchSize);
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }
        final snapshot = await query.get();
        allDocs.addAll(snapshot.docs);
        if (snapshot.docs.length < batchSize) break;
        lastDoc = snapshot.docs.last;
      }

      logD(
          '📦 [PRODUTOS-SYNC] Encontrados ${allDocs.length} produtos no Firestore');

      int sincronizados = 0;
      int atualizados = 0;

      for (final doc in allDocs) {
        try {
          var data = Map<String, dynamic>.from(doc.data());
          final produtoId = doc.id;

          await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
          if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
            lojaId: lojaId,
            estoqueDocId: produtoId,
          )) {
            for (final k in produtosBox.keys.toList()) {
              final loc = produtosBox.get(k);
              if (loc != null &&
                  loc.lojaId == lojaId &&
                  loc.idFirebase == produtoId) {
                await produtosBox.delete(k);
                logD(
                  '🗑️ [PRODUTOS-SYNC] Hive removido (tombstone p): key=$k doc=$produtoId',
                );
              }
            }
            continue;
          }
          data = ProdutoExclusaoTombstoneService.filtrarDocEstoqueParaPull(
            lojaId,
            produtoId,
            data,
          );

          // Soft delete pendente: doc ainda existe até a exclusão definitiva; não recriar no Hive.
          if (isEstoqueDocPendingSoftDelete(data)) {
            logD(
              '⏭️ [PRODUTOS-SYNC] Doc $produtoId ignorado no pull (pendingSoftDelete)',
            );
            continue;
          }

          if (await ProdutoPullSkipGuard.shouldSkipDoc(
              lojaId: lojaId, docId: produtoId)) {
            for (final k in produtosBox.keys.toList()) {
              final loc = produtosBox.get(k);
              if (loc != null &&
                  loc.lojaId == lojaId &&
                  loc.idFirebase == produtoId) {
                await produtosBox.delete(k);
                logD(
                  '🗑️ [PRODUTOS-SYNC] Hive: removido (pull skip pós-exclusão local) key=$k doc=$produtoId',
                );
              }
            }
            continue;
          }

          // Buscar se já existe no Hive pelo idFirebase OU pelo slug
          final slug = data['slug'] ?? '';
          Produto? produtoExistente;

          // Primeiro tenta por idFirebase
          try {
            produtoExistente = produtosBox.values.firstWhere(
              (p) => p.idFirebase == produtoId && p.lojaId == lojaId,
            );
          } catch (_) {
            // Se não encontrou por idFirebase, tenta por slug (último recurso)
            if (slug.isNotEmpty) {
              try {
                produtoExistente = produtosBox.values.firstWhere(
                  (p) => p.slug == slug && p.lojaId == lojaId,
                );
                logW(
                  '[COMBO_MATCH_GUARD] [PRODUTO_MATCH_GUARD] Hive resolvido por slug (idFirebase local ≠ docId). '
                  'docId=$produtoId slug=$slug',
                  tag: 'PRODUTO_MATCH_GUARD',
                );
              } catch (_) {}
            }
          }

          if (produtoExistente != null) {
            // Atualizar produto existente com dados do Firestore.
            //
            // Regra de quantidade: se [Produto.updatedAt] local for **posterior** ao `updatedAt`
            // remoto, não sobrescrever [quantidade] (evita regressão quando o push ainda não
            // refletiu no snapshot puxado). Demais campos seguem o merge abaixo; custo manual
            // e peso mantêm guards existentes.
            final p = produtoExistente;

            final remoteUpdatedAtForPull = parseFirestoreUpdatedAt(data);
            final localHiveKey = p.key;
            final pendingProdutoSync = localHiveKey is int
                ? await SyncQueueService.hasPendingProdutoSync(
                    lojaId: lojaId,
                    entityKey: localHiveKey,
                    includeDeadLetter: true,
                  )
                : false;
            final preserveLocalQuantidade = !preferRemoteQuantity &&
                (pendingProdutoSync ||
                    shouldPreserveLocalQuantidadeOnFirestorePull(
                      localUpdatedAt: p.updatedAt,
                      remoteUpdatedAt: remoteUpdatedAtForPull,
                    ));
            final preserveStockRegression =
                shouldPreserveLocalStockOnRemoteRegression(
              local: p,
              remoteData: data,
            );
            final preserveLocalEdits =
                preserveLocalQuantidade || preserveStockRegression;

            final custoAntes = p.custoReal;
            final pesoAntes = p.peso;
            final custoManualLocal = p.custoEditadoNoCadastro == true;
            if (preserveLocalEdits) {
              final motivo = pendingProdutoSync
                  ? 'sync pendente na fila'
                  : preserveStockRegression
                      ? 'regressão de grade remota (snapshot stale)'
                      : 'updatedAt local mais recente que remoto';
              logD(
                '[PULL_EDIT_GUARD] doc=$produtoId mantendo edição local ($motivo)',
              );
              if (!custoManualLocal) {
                ProdutoCustoGuard.applyRemoteCustoOnExistingProduct(
                  local: p,
                  remoteData: data,
                  logContext: 'sync_pull_preserve_edits',
                );
              }
            } else {
              p.nome = data['nome'] ?? p.nome;
              p.quantidade =
                  (data['quantidade'] as num?)?.toInt() ?? p.quantidade;
              p.precoFinal =
                  (data['preco'] as num?)?.toDouble() ?? p.precoFinal;
              if (custoManualLocal) {
                logW(
                  '[CUSTO_GUARD] sync pull: mantendo custoReal local '
                  '${custoAntes.toStringAsFixed(2)} (cadastro manual)',
                  tag: 'CUSTO_GUARD',
                );
                p.custoEditadoNoCadastro = true;
              } else {
                ProdutoCustoGuard.applyRemoteCustoOnExistingProduct(
                  local: p,
                  remoteData: data,
                  logContext: 'sync_pull',
                );
              }
              p.frete = (data['frete'] as num?)?.toDouble() ?? p.frete;
              p.gastosFixos =
                  (data['gastosFixos'] as num?)?.toDouble() ?? p.gastosFixos;
              p.gastosVariaveis =
                  (data['gastosVariaveis'] as num?)?.toDouble() ??
                      p.gastosVariaveis;
              p.precoSugerido = (data['precoSugerido'] as num?)?.toDouble() ??
                  p.precoSugerido;
              final pesoDados = data['peso'];
              if (pesoDados is num) {
                final pr = pesoDados.toDouble();
                if (pr == 0.0 && pesoAntes > 0.0) {
                  logW(
                    '[PESO_GUARD] sync pull: ignorando peso remoto 0 (local '
                    '${pesoAntes.toStringAsFixed(1)} g)',
                    tag: 'PESO_GUARD',
                  );
                } else {
                  p.peso = pr;
                }
              }
              p.tipoEmbalagem =
                  (data['tipoEmbalagem'] ?? p.tipoEmbalagem).toString();
              p.categoria = data['categoria'] ?? p.categoria;
              p.subcategoria = data['subcategoria'] ?? p.subcategoria;
              if (data.containsKey('categoriasExtras')) {
                final raw = data['categoriasExtras'];
                p.categoriasExtras = raw is List
                    ? raw.map((e) => e.toString()).toList()
                    : <String>[];
              }
              if (data.containsKey('subcategoriasExtras')) {
                final raw = data['subcategoriasExtras'];
                p.subcategoriasExtras = raw is List
                    ? raw.map((e) => e.toString()).toList()
                    : <String>[];
              }
              p.descricao = data['descricao'] ?? p.descricao;
              p.imagens =
                  (data['imagens'] as List?)?.cast<String>() ?? p.imagens;
              p.slug = data['slug'] ?? p.slug;
              p.codigoBarras =
                  (data['codigoBarras'] ?? p.codigoBarras ?? '').toString();
              p.sku = (data['sku'] ?? p.sku ?? '').toString();
              p.estoqueMinimo = (data['estoqueMinimo'] is num)
                  ? (data['estoqueMinimo'] as num).toInt()
                  : p.estoqueMinimo;
              if (data['dataEntrada'] is Timestamp) {
                p.dataEntrada = (data['dataEntrada'] as Timestamp).toDate();
              }
              if (data.containsKey('ativoNoRascunho')) {
                p.ativoNoRascunho = data['ativoNoRascunho'] == true;
              }
              if (data.containsKey('fornecedor')) {
                p.fornecedor = (data['fornecedor'] ?? '').toString().trim();
              }
              p.publicadoNoCatalogo =
                  data['publicadoNoCatalogo'] ?? p.publicadoNoCatalogo;
              applyRemoteVariationFieldsToExistingOnPull(local: p, data: data);
              p.precoUnitario = (data['precoUnitario'] as num?)?.toDouble() ??
                  (data['preco'] as num?)?.toDouble() ??
                  p.precoUnitario;
              applyComboMetadataPullForExisting(
                data,
                p,
                produtosBox: produtosBox,
                lojaId: lojaId,
                docId: produtoId,
              );
              p.divideSemJuros = data['divideSemJuros'] ?? p.divideSemJuros;
              p.percentualDescontoPix = (data['percentualDescontoPix'] is num)
                  ? (data['percentualDescontoPix'] as num).toDouble()
                  : p.percentualDescontoPix;
              p.maxParcelasSemJuros = (data['maxParcelasSemJuros'] is num)
                  ? (data['maxParcelasSemJuros'] as num).toInt()
                  : p.maxParcelasSemJuros;
              if (data.containsKey('emPromocao')) {
                p.emPromocao = data['emPromocao'] == true;
              }
              if (data.containsKey('percentualPromo')) {
                p.percentualPromo =
                    (data['percentualPromo'] as num?)?.toDouble();
              }
              if (data.containsKey('valorPromo')) {
                p.valorPromo = (data['valorPromo'] as num?)?.toDouble();
              }
              if (data.containsKey('dataInicioPromo')) {
                final dip = data['dataInicioPromo'];
                p.dataInicioPromo = dip is Timestamp ? dip.toDate() : null;
              }
              if (data.containsKey('dataFimPromo')) {
                final dfp = data['dataFimPromo'];
                p.dataFimPromo = dfp is Timestamp ? dfp.toDate() : null;
              }
              final vu = data['videoUrl'];
              if (vu != null && vu.toString().trim().isNotEmpty) {
                p.videoUrl = vu.toString().trim();
              }
              final mk = data['marketplaces'];
              if (mk is List) {
                p.marketplaces = mk.map((e) => e.toString()).toList();
              }
            }
            final updatedAt = data['updatedAt'];
            if (preserveLocalEdits) {
              mergeRemoteCodigoBarrasWhenPreservingLocalEdits(
                local: p,
                remoteData: data,
              );
              if (updatedAt is Timestamp) {
                p.updatedAt = _maxDateTime(p.updatedAt, updatedAt.toDate());
              }
              if (preserveStockRegression) {
                tryConfirmStockFromRemote(p, data);
              }
            } else {
              if (updatedAt != null && updatedAt is Timestamp) {
                p.updatedAt = updatedAt.toDate();
              }
              final stockAt = data[kProdutoStockUpdatedAtField];
              if (stockAt is Timestamp) {
                applyServerStockVersionToProduto(p, stockAt.toDate());
              }
              tryConfirmStockFromRemote(p, data);
            }
            if ((p.custoReal - custoAntes).abs() > 0.0001 ||
                (p.peso - pesoAntes).abs() > 0.0001) {
              logD(
                '[AUDIT_SYNC] Produto $produtoId aplicou REMOTO (mais recente). '
                'custo ${custoAntes.toStringAsFixed(2)} -> ${p.custoReal.toStringAsFixed(2)} | '
                'peso ${pesoAntes.toStringAsFixed(2)} -> ${p.peso.toStringAsFixed(2)}',
              );
            }
            if (p.idFirebase.isEmpty) {
              p.idFirebase = produtoId;
            }
            ProdutoExclusaoTombstoneService
                .filtrarMapasLocaisDoProdutoPeloTombstone(
              lojaId,
              produtoId,
              p,
            );
            p.recalcularQuantidadeTotal();
            await p.save();
            atualizados++;
            logD('🔄 Produto $produtoId atualizado');
          } else {
            final slugNovo = (data['slug'] ?? '').toString().trim();
            if (await ProdutoPullSkipGuard.shouldSkipNewBySlug(
              lojaId: lojaId,
              slug: slugNovo,
            )) {
              logD(
                '⏭️ [PRODUTOS-SYNC] Doc $produtoId ignorado no pull (slug excluído localmente: $slugNovo)',
              );
              continue;
            }
            // Criar novo produto
            final uAt = data['updatedAt'];
            final updatedAtDt =
                uAt != null && uAt is Timestamp ? uAt.toDate() : null;
            final comboNovo = comboFieldsForNewProductPull(
              data,
              produtosBox: produtosBox,
              lojaId: lojaId,
              docId: produtoId,
            );
            final produto = Produto(
              idFirebase: produtoId,
              nome: data['nome'] ?? 'Produto sem nome',
              custoReal: (data['custoReal'] as num?)?.toDouble() ?? 0.0,
              frete: (data['frete'] as num?)?.toDouble() ?? 0.0,
              gastosFixos: (data['gastosFixos'] as num?)?.toDouble() ?? 0.0,
              gastosVariaveis:
                  (data['gastosVariaveis'] as num?)?.toDouble() ?? 0.0,
              precoSugerido: (data['precoSugerido'] as num?)?.toDouble() ??
                  (data['preco'] as num?)?.toDouble() ??
                  0.0,
              precoFinal: (data['preco'] as num?)?.toDouble() ?? 0.0,
              precoUnitario: (data['precoUnitario'] as num?)?.toDouble() ??
                  (data['preco'] as num?)?.toDouble() ??
                  0.0,
              quantidade: (data['quantidade'] as num?)?.toInt() ?? 0,
              categoria: data['categoria'] ?? '',
              categoriasExtras: (data['categoriasExtras'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
              dataEntrada: data['dataEntrada'] is Timestamp
                  ? (data['dataEntrada'] as Timestamp).toDate()
                  : DateTime.now(),
              descricao: data['descricao'] ?? '',
              imagens: (data['imagens'] as List?)?.cast<String>() ?? [],
              slug: data['slug'] ?? '',
              lojaId: lojaId,
              subcategoria: data['subcategoria'] ?? '',
              subcategoriasExtras: (data['subcategoriasExtras'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
              publicadoNoCatalogo: data['publicadoNoCatalogo'] ?? false,
              tamanhos: _dedupeStringListPreserveOrder(
                (data['tamanhos'] as List?)?.map((e) => e.toString()).toList(),
              ),
              estoquePorTamanho:
                  Map<String, int>.from(data['estoquePorTamanho'] ?? {}),
              cores: _dedupeStringListPreserveOrder(
                (data['cores'] as List?)?.map((e) => e.toString()).toList(),
              ),
              variacoes: parseVariacoesFromFirestore(data['variacoes']),
              variacoesExtraTipo: _parseVariacoesExtraTipoFromFirestore(
                  data['variacoesExtraTipo']),
              precoPorTamanho:
                  parsePrecoPorTamanhoFromFirestore(data['precoPorTamanho']),
              tipoProduto: comboNovo.$1,
              itensCombo: comboNovo.$2,
              comboConfig: comboNovo.$3,
              divideSemJuros: data['divideSemJuros'] == true,
              percentualDescontoPix: (data['percentualDescontoPix'] is num)
                  ? (data['percentualDescontoPix'] as num).toDouble()
                  : 0.0,
              maxParcelasSemJuros: (data['maxParcelasSemJuros'] is num)
                  ? (data['maxParcelasSemJuros'] as num).toInt()
                  : 12,
              codigoBarras: (data['codigoBarras'] ?? '').toString(),
          sku: (data['sku'] ?? '').toString(),
              estoqueMinimo: (data['estoqueMinimo'] is num)
                  ? (data['estoqueMinimo'] as num).toInt()
                  : 0,
              fornecedor: (data['fornecedor'] ?? '').toString().trim(),
              peso: (data['peso'] as num?)?.toDouble() ?? 0.0,
              tipoEmbalagem: (data['tipoEmbalagem'] ?? 'padrao').toString(),
              updatedAt: updatedAtDt,
              custoEditadoNoCadastro:
                  (data['custoEditadoNoCadastro'] as bool?) ?? false,
              emPromocao: data['emPromocao'] == true,
              percentualPromo: (data['percentualPromo'] as num?)?.toDouble(),
              valorPromo: (data['valorPromo'] as num?)?.toDouble(),
              dataInicioPromo: data['dataInicioPromo'] is Timestamp
                  ? (data['dataInicioPromo'] as Timestamp).toDate()
                  : null,
              dataFimPromo: data['dataFimPromo'] is Timestamp
                  ? (data['dataFimPromo'] as Timestamp).toDate()
                  : null,
              videoUrl: (data['videoUrl'] ?? '').toString(),
              marketplaces: (data['marketplaces'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
              ativoNoRascunho: data['ativoNoRascunho'] == true,
            );

            produto.recalcularQuantidadeTotal();
            await produtosBox.add(produto);
            sincronizados++;
            logD('✅ Produto $produtoId sincronizado');
          }
        } catch (e, st) {
          logE(
              '❌ [PRODUTOS-SYNC] Erro ao sincronizar produto (type=${e.runtimeType})',
              error: e,
              st: st);
        }
      }

      await ProdutoPullSkipGuard.pruneAfterPull(
        lojaId: lojaId,
        remoteDocIds: allDocs.map((d) => d.id).toSet(),
        remoteDocData: allDocs.map((d) => d.data()).toList(),
      );

      // Remover locais que não existem mais no Firestore (excluídos em outro aparelho)
      final firestoreIds = allDocs.map((d) => d.id).toSet();
      final toRemove = <int>[];
      for (final k in produtosBox.keys) {
        final p = produtosBox.get(k);
        if (p != null &&
            p.lojaId == lojaId &&
            p.idFirebase.isNotEmpty &&
            !firestoreIds.contains(p.idFirebase)) {
          toRemove.add(k as int);
        }
      }
      for (final k in toRemove) {
        await produtosBox.delete(k);
        logD(
            '🗑️ [PRODUTOS-SYNC] Produto local removido (excluído no Firestore): $k');
      }

      logD(
          '✅ [PRODUTOS-SYNC] Sync completo: $sincronizados novos, $atualizados atualizados, ${toRemove.length} removidos');
      return sincronizados + atualizados;
    } catch (e, st) {
      logE(
          '❌ [PRODUTOS-SYNC] Erro ao sincronizar do Firestore (type=${e.runtimeType})',
          error: e,
          st: st);
      return 0;
    } finally {
      ProdutoRemoteSyncGuard.applyingRemoteToHive = false;
    }
  }

  /// Receita de combo já persistida no Hive (independente do valor atual de [tipoProduto]).
  static bool _receitaLocalNaoVazia(Produto p) =>
      p.itensCombo != null && p.itensCombo!.isNotEmpty;

  static bool _comboConfigLocalEfetivo(Produto p) =>
      ComboConfigCanonical.isEffective(p.comboConfig);

  /// Pull Firestore → Hive: [tipoProduto] + [itensCombo] para produto **já existente** na box.
  ///
  /// Semântica:
  /// - **itensCombo ausente** na mapa remota → não altera receita local (legado / doc incompleto).
  /// - **itensCombo: null** (chave presente) → só apaga se não houver receita local a preservar.
  /// - **itensCombo: []** → limpeza explícita da receita.
  /// - **lista** → parse + aplicar; parse vazio com receita local válida → preservar local.
  /// - **tipoProduto ausente** → não altera tipo local.
  /// - **tipoProduto: simples** com receita local ainda preenchida após merge de itens → força `combo`.
  ///
  /// [comboConfig] (mapa):
  /// - **ausente** → não altera local.
  /// - **null** (chave presente) → só zera se local já não for efetivo; senão preserva local.
  /// - **{}** → limpa config no Hive.
  /// - **mapa** → normaliza; parse inválido preserva local se efetivo.
  static void applyComboMetadataPullForExisting(
    Map<String, dynamic> data,
    Produto p, {
    required Box<Produto> produtosBox,
    required String lojaId,
    required String docId,
  }) {
    // --- itensCombo primeiro (depois ajustamos tipo em função da receita efetiva)
    if (!data.containsKey('itensCombo')) {
      logW(
        '[COMBO_PULL_GUARD] doc=$docId itensCombo ausente no Firestore — mantendo local '
        '(${p.itensCombo?.length ?? 0} itens)',
        tag: 'COMBO_PULL_GUARD',
      );
    } else {
      final itc = data['itensCombo'];
      if (itc == null) {
        if (_receitaLocalNaoVazia(p)) {
          logW(
            '[COMBO_PULL_GUARD] doc=$docId itensCombo remoto=null (chave presente) — '
            'preservando receita local (${p.itensCombo!.length} itens)',
            tag: 'COMBO_PULL_GUARD',
          );
        } else {
          p.itensCombo = null;
          logW(
            '[COMBO_PULL_CLEAR] doc=$docId itensCombo=null explícito sem receita local',
            tag: 'COMBO_PULL_CLEAR',
          );
        }
      } else if (itc is! List) {
        logW(
          '[COMBO_PULL_GUARD] doc=$docId itensCombo tipo inválido (${itc.runtimeType}) — '
          'mantendo receita local',
          tag: 'COMBO_PULL_GUARD',
        );
      } else if (itc.isEmpty) {
        p.itensCombo = null;
        logW(
          '[COMBO_PULL_CLEAR] doc=$docId itensCombo=[] limpeza explícita da receita',
          tag: 'COMBO_PULL_CLEAR',
        );
      } else {
        final parsed = _parseItensComboFromFirestore(
          itc,
          lojaId: lojaId,
          produtosBox: produtosBox,
        );
        if (parsed != null && parsed.isNotEmpty) {
          p.itensCombo = parsed;
          logD(
              '[COMBO_PULL_APPLY] doc=$docId itensCombo aplicados (${parsed.length} itens)');
        } else if (_receitaLocalNaoVazia(p)) {
          logW(
            '[COMBO_PULL_GUARD] doc=$docId parse de itensCombo não produziu lista válida — '
            'preservando receita local (${p.itensCombo!.length} itens)',
            tag: 'COMBO_PULL_GUARD',
          );
        } else {
          p.itensCombo = parsed;
          logW(
            '[COMBO_PULL_APPLY] doc=$docId itensCombo após parse vazio — receita limpa',
            tag: 'COMBO_PULL_APPLY',
          );
        }
      }
    }

    // --- comboConfig (opcional; legado sem chave não altera Hive)
    if (!data.containsKey('comboConfig')) {
      logW(
        '[COMBO_CONFIG_PULL_GUARD] doc=$docId comboConfig ausente no Firestore — mantendo local '
        '(efetivo=${_comboConfigLocalEfetivo(p)})',
        tag: 'COMBO_CONFIG_PULL_GUARD',
      );
    } else {
      final cc = data['comboConfig'];
      if (cc == null) {
        if (_comboConfigLocalEfetivo(p)) {
          logW(
            '[COMBO_CONFIG_PULL_GUARD] doc=$docId comboConfig remoto=null (chave presente) — '
            'preservando local',
            tag: 'COMBO_CONFIG_PULL_GUARD',
          );
        } else {
          p.comboConfig = null;
          logW(
            '[COMBO_CONFIG_PULL_CLEAR] doc=$docId comboConfig=null explícito',
            tag: 'COMBO_CONFIG_PULL_CLEAR',
          );
        }
      } else if (cc is! Map) {
        logW(
          '[COMBO_CONFIG_PULL_GUARD] doc=$docId comboConfig tipo inválido (${cc.runtimeType}) — '
          'mantendo local',
          tag: 'COMBO_CONFIG_PULL_GUARD',
        );
      } else if (cc.isEmpty) {
        p.comboConfig = null;
        logW(
          '[COMBO_CONFIG_PULL_CLEAR] doc=$docId comboConfig={} limpeza explícita',
          tag: 'COMBO_CONFIG_PULL_CLEAR',
        );
      } else {
        final parsed = ComboConfigCanonical.parseFromFirestore(cc);
        if (parsed != null) {
          p.comboConfig = parsed;
          logD('[COMBO_CONFIG_PULL_APPLY] doc=$docId comboConfig aplicado');
        } else if (_comboConfigLocalEfetivo(p)) {
          logW(
            '[COMBO_CONFIG_PULL_GUARD] doc=$docId parse comboConfig inválido — preservando local',
            tag: 'COMBO_CONFIG_PULL_GUARD',
          );
        } else {
          p.comboConfig = null;
          logW(
            '[COMBO_CONFIG_PULL_APPLY] doc=$docId comboConfig após parse inválido — limpo',
            tag: 'COMBO_CONFIG_PULL_APPLY',
          );
        }
      }
    }

    // --- tipoProduto (não rebaixar para simples se ainda há receita)
    if (!data.containsKey('tipoProduto')) {
      logW(
        '[COMBO_PULL_GUARD] doc=$docId tipoProduto ausente — mantendo local tipo=${p.tipoProduto}',
        tag: 'COMBO_PULL_GUARD',
      );
    } else {
      final raw = data['tipoProduto'];
      final remote = (raw ?? 'simples').toString().trim();
      if (remote == 'combo') {
        p.tipoProduto = 'combo';
        logD('[COMBO_PULL_APPLY] doc=$docId tipoProduto=combo');
      } else if (remote == 'simples') {
        if (_receitaLocalNaoVazia(p)) {
          p.tipoProduto = 'combo';
          logW(
            '[COMBO_PULL_GUARD] doc=$docId remoto tipoProduto=simples mas receita presente — '
            'mantendo tipo combo',
            tag: 'COMBO_PULL_GUARD',
          );
        } else {
          p.tipoProduto = 'simples';
          logD('[COMBO_PULL_APPLY] doc=$docId tipoProduto=simples');
        }
      } else if (remote.isNotEmpty) {
        p.tipoProduto = remote;
        logD('[COMBO_PULL_APPLY] doc=$docId tipoProduto=$remote');
      }
    }
  }

  /// Pull para **novo** [Produto] (sem estado local). Ausência de chave → defaults seguros.
  static (
    String tipoProduto,
    List<Map<String, dynamic>>? itensCombo,
    Map<String, dynamic>? comboConfig
  ) comboFieldsForNewProductPull(
    Map<String, dynamic> data, {
    required Box<Produto> produtosBox,
    required String lojaId,
    required String docId,
  }) {
    final tipoProduto = data.containsKey('tipoProduto')
        ? (data['tipoProduto'] ?? 'simples').toString().trim()
        : 'simples';
    if (!data.containsKey('tipoProduto')) {
      logD(
          '[COMBO_PULL_APPLY] novo doc=$docId tipoProduto ausente — default simples');
    }

    List<Map<String, dynamic>>? itensCombo;
    if (!data.containsKey('itensCombo')) {
      itensCombo = null;
      logD('[COMBO_PULL_APPLY] novo doc=$docId itensCombo ausente — null');
    } else {
      final itc = data['itensCombo'];
      if (itc == null) {
        itensCombo = null;
        logD('[COMBO_PULL_APPLY] novo doc=$docId itensCombo=null');
      } else if (itc is! List) {
        itensCombo = null;
        logW(
          '[COMBO_PULL_GUARD] novo doc=$docId itensCombo tipo inválido — null',
          tag: 'COMBO_PULL_GUARD',
        );
      } else if (itc.isEmpty) {
        itensCombo = null;
        logD('[COMBO_PULL_APPLY] novo doc=$docId itensCombo=[]');
      } else {
        itensCombo = _parseItensComboFromFirestore(
          itc,
          lojaId: lojaId,
          produtosBox: produtosBox,
        );
        if (itensCombo == null || itensCombo.isEmpty) {
          logW(
            '[COMBO_PULL_GUARD] novo doc=$docId itensCombo presente mas parse retornou vazio',
            tag: 'COMBO_PULL_GUARD',
          );
        } else {
          logD(
            '[COMBO_PULL_APPLY] novo doc=$docId itensCombo ok (${itensCombo.length} itens)',
          );
        }
      }
    }

    var tipoFinal = tipoProduto.isEmpty ? 'simples' : tipoProduto;
    if (_receitaNaoVazia(itensCombo) && tipoFinal != 'combo') {
      tipoFinal = 'combo';
      logW(
        '[COMBO_PULL_GUARD] novo doc=$docId tipo remoto=$tipoProduto mas há itensCombo — '
        'ajustando para combo',
        tag: 'COMBO_PULL_GUARD',
      );
    }

    Map<String, dynamic>? comboConfig;
    if (!data.containsKey('comboConfig')) {
      comboConfig = null;
      logD(
          '[COMBO_CONFIG_PULL_APPLY] novo doc=$docId comboConfig ausente — null');
    } else {
      final cc = data['comboConfig'];
      if (cc == null) {
        comboConfig = null;
        logD('[COMBO_CONFIG_PULL_APPLY] novo doc=$docId comboConfig=null');
      } else if (cc is! Map) {
        comboConfig = null;
        logW(
          '[COMBO_CONFIG_PULL_GUARD] novo doc=$docId comboConfig tipo inválido — null',
          tag: 'COMBO_CONFIG_PULL_GUARD',
        );
      } else if (cc.isEmpty) {
        comboConfig = null;
        logD('[COMBO_CONFIG_PULL_APPLY] novo doc=$docId comboConfig={}');
      } else {
        comboConfig = ComboConfigCanonical.parseFromFirestore(cc);
        if (comboConfig == null) {
          logW(
            '[COMBO_CONFIG_PULL_GUARD] novo doc=$docId comboConfig presente mas parse inválido',
            tag: 'COMBO_CONFIG_PULL_GUARD',
          );
        } else {
          logD('[COMBO_CONFIG_PULL_APPLY] novo doc=$docId comboConfig ok');
        }
      }
    }
    if (ComboConfigCanonical.isEffective(comboConfig) && tipoFinal != 'combo') {
      tipoFinal = 'combo';
      logW(
        '[COMBO_PULL_GUARD] novo doc=$docId tipo remoto=$tipoProduto mas há comboConfig — '
        'ajustando para combo',
        tag: 'COMBO_PULL_GUARD',
      );
    }
    return (tipoFinal, itensCombo, comboConfig);
  }

  static bool _receitaNaoVazia(List<Map<String, dynamic>>? it) =>
      it != null && it.isNotEmpty;

  static List<Map<String, dynamic>>? _parseItensComboFromFirestore(
    dynamic data, {
    required String lojaId,
    required Box<Produto> produtosBox,
  }) {
    if (data == null || data is! List || data.isEmpty) return null;
    final result = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final e in data) {
      if (e is! Map) {
        skipped++;
        continue;
      }
      final m = Map<String, dynamic>.from(Map.from(e));
      final nome = (m['nome'] ?? '').toString().trim();
      final pid = ComboReceitaNormalizacao.pidFrom(m);
      final slug = (m['slug'] ?? '').toString().trim();
      if (nome.isEmpty && pid.isEmpty && slug.isEmpty) {
        skipped++;
        logW(
          '[COMBO_PARSE_SKIP] item ignorado (sem nome, productId e slug)',
          tag: 'COMBO_PULL_GUARD',
        );
        continue;
      }
      result.add(m);
    }
    if (result.isEmpty) {
      if (skipped > 0) {
        logW(
          '[COMBO_PULL_GUARD] parse itensCombo: $skipped entrada(s) inválida(s), lista vazia',
          tag: 'COMBO_PULL_GUARD',
        );
      }
      return null;
    }
    final loja = produtosBox.values.where((p) => p.lojaId == lojaId);
    return ComboReceitaNormalizacao.normalizeLista(result, loja);
  }

  /// Converte mapa precoPorTamanho vindo do Firestore para Map<String, double>.
  static Map<String, double>? parsePrecoPorTamanhoFromFirestore(dynamic data) {
    if (data == null || data is! Map) return null;
    final result = <String, double>{};
    for (final entry in data.entries) {
      final k = entry.key?.toString().trim() ?? '';
      if (k.isEmpty) continue;
      final v = entry.value is num
          ? (entry.value as num).toDouble()
          : double.tryParse(
                (entry.value?.toString() ?? '').trim().replaceAll(',', '.'),
              ) ??
              0.0;
      if (v > 0) result[k] = v;
    }
    return result.isEmpty ? null : result;
  }

  /// Converte mapa de variações: cor -> int (legado) ou cor -> { extraValor -> qtd }.
  static Map<String, dynamic>? parseVariacoesFromFirestore(dynamic varData) {
    if (varData == null || varData is! Map) return null;
    final result = <String, dynamic>{};
    for (final entry in varData.entries) {
      final tamanho = entry.key?.toString() ?? '';
      if (tamanho.isEmpty) continue;
      final inner = entry.value;
      if (inner is! Map) continue;
      final mapaCor = <String, dynamic>{};
      for (final e in inner.entries) {
        final cor = e.key?.toString() ?? '';
        if (cor.isEmpty) continue;
        final v = e.value;
        if (v is Map) {
          final m = <String, dynamic>{};
          for (final ie in v.entries) {
            final k = ie.key?.toString() ?? '';
            if (ProdutoVariacaoExtra.isMetaKey(k)) {
              final c = ie.value is num
                  ? (ie.value as num).toDouble()
                  : double.tryParse(ie.value?.toString() ?? '');
              if (c != null && c > 0) {
                m[k] = c;
              }
              continue;
            }
            // Mantém a chave vazia ('') usada no legado para qtd sem extra.
            // Sem isso, produtos com custo por variação podem perder a quantidade ao carregar.
            if (k.isEmpty) {
              final q = ie.value is num
                  ? (ie.value as num).toInt()
                  : int.tryParse(ie.value?.toString() ?? '') ?? 0;
              m[ProdutoVariacaoExtra.kSemExtraKey] = q;
              continue;
            }
            if (k == ProdutoVariacaoExtra.kSemExtraKey ||
                k == ProdutoVariacaoExtra.kSemExtraKeyLegacy) {
              final q = ie.value is num
                  ? (ie.value as num).toInt()
                  : int.tryParse(ie.value?.toString() ?? '') ?? 0;
              m[ProdutoVariacaoExtra.kSemExtraKey] = q;
              continue;
            }
            final q = ie.value is num
                ? (ie.value as num).toInt()
                : int.tryParse(ie.value?.toString() ?? '') ?? 0;
            m[k] = q;
          }
          if (m.isNotEmpty) {
            final hasMeta =
                m.containsKey(ProdutoVariacaoExtra.kMetaCustoUnitarioKey);
            if (!hasMeta &&
                m.length == 1 &&
                (m.containsKey(ProdutoVariacaoExtra.kSemExtraKey) ||
                    m.containsKey(ProdutoVariacaoExtra.kSemExtraKeyLegacy) ||
                    m.containsKey(''))) {
              mapaCor[cor] = m[ProdutoVariacaoExtra.kSemExtraKey] ??
                  m[ProdutoVariacaoExtra.kSemExtraKeyLegacy] ??
                  m[''] ??
                  0;
            } else {
              mapaCor[cor] = m;
            }
          }
        } else {
          final qtd =
              v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
          mapaCor[cor] = qtd;
        }
      }
      if (mapaCor.containsKey('sem-cor')) {
        final temCorReal =
            mapaCor.keys.any((k) => k.trim().isNotEmpty && k != 'sem-cor');
        if (temCorReal) {
          mapaCor.remove('sem-cor');
          logD(
            '[VARIACAO_CLEANUP] removendo sem-cor duplicado no tamanho "$tamanho"',
          );
        }
      }
      if (mapaCor.isNotEmpty) result[tamanho] = mapaCor;
    }
    return result.isEmpty ? null : result;
  }

  /// { tamanho: { cor: { extraValor: extraTipo } } }
  static Map<String, dynamic>? _parseVariacoesExtraTipoFromFirestore(
      dynamic d) {
    if (d == null || d is! Map) return null;
    final out = <String, dynamic>{};
    for (final te in d.entries) {
      final t = te.key?.toString() ?? '';
      if (t.isEmpty) continue;
      final inner = te.value;
      if (inner is! Map) continue;
      final mapCor = <String, dynamic>{};
      for (final ce in inner.entries) {
        final c = ce.key?.toString() ?? '';
        if (c.isEmpty) continue;
        final ev = ce.value;
        if (ev is! Map) continue;
        final mapEx = <String, dynamic>{};
        for (final ee in ev.entries) {
          var k = ee.key?.toString() ?? '';
          if (k.trim().isEmpty) {
            k = ProdutoVariacaoExtra.kSemExtraKey;
          } else if (k == ProdutoVariacaoExtra.kSemExtraKeyLegacy) {
            k = ProdutoVariacaoExtra.kSemExtraKey;
          }
          final tipo = (ee.value ?? '').toString();
          mapEx[k] = tipo;
        }
        if (mapEx.isNotEmpty) mapCor[c] = mapEx;
      }
      if (mapCor.isNotEmpty) out[t] = mapCor;
    }
    return out.isEmpty ? null : out;
  }

  static Map<String, dynamic>? parseVariacoesExtraTipoFromFirestoreForPull(
    dynamic d,
  ) =>
      _parseVariacoesExtraTipoFromFirestore(d);

  /// Atualiza apenas a quantidade de um produto no Firestore
  static Future<void> atualizarQuantidade({
    required String lojaId,
    required String produtoId,
    required int novaQuantidade,
    Map<String, dynamic>? variacoes,
    Map<String, int>? estoquePorTamanho,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'quantidade': novaQuantidade,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Adicionar variações se fornecidas
      if (variacoes != null) {
        updateData['variacoes'] = sanitizeVariacoesForFirestore(
          Map<String, dynamic>.from(variacoes),
        );
      }
      if (estoquePorTamanho != null) {
        updateData['estoquePorTamanho'] = estoquePorTamanho;
      }

      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .update(updateData);

      logD(
          '✅ [PRODUTOS-SYNC] Quantidade atualizada: $produtoId = $novaQuantidade');
    } catch (e, st) {
      logE(
          '❌ [PRODUTOS-SYNC] Erro ao atualizar quantidade (type=${e.runtimeType})',
          error: e,
          st: st);
    }
  }

  /// Verifica se há produtos no Firestore que ainda não estão no dispositivo.
  static Future<bool> hasDataToImport({
    required String lojaId,
    required int localCount,
  }) async {
    try {
      final aggregate = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .count();
      final snapshot = await aggregate.get();
      final remoteCount = snapshot.count ?? 0;
      return remoteCount > localCount;
    } catch (e, st) {
      logE(
          '❌ [PRODUTOS-SYNC] Erro ao verificar dados para importar (type=${e.runtimeType})',
          error: e,
          st: st);
      return false;
    }
  }

  /// Remove do Firestore os produtos que NÃO estão no estoque local.
  /// Use quando o estoque local (406) é a fonte da verdade e o Firestore tem produtos a mais (ex: 1000).
  static Future<int> limparProdutosExcedentesNoFirestore({
    required String lojaId,
    required Box<Produto> produtosBox,

    /// Só com `true` permite apagar muitos docs excedentes de uma vez.
    bool allowMassDelete = false,
  }) async {
    try {
      final idsLocais = produtosBox.values
          .where((p) => p.lojaId == lojaId && p.idFirebase.isNotEmpty)
          .map((p) => p.idFirebase)
          .toSet();

      const batchSize = 500;
      final toDelete = <String>[];
      DocumentSnapshot<Map<String, dynamic>>? lastDoc;
      var remoteCount = 0;
      final collectionPath = 'lojas/$lojaId/${FSPaths.estoqueProdutosCol}';

      while (true) {
        Query<Map<String, dynamic>> query = _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .orderBy(FieldPath.documentId)
            .limit(batchSize);
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }
        final snapshot = await query.get();
        remoteCount += snapshot.docs.length;
        for (final doc in snapshot.docs) {
          if (!idsLocais.contains(doc.id)) {
            toDelete.add(doc.id);
          }
        }
        if (snapshot.docs.length < batchSize) break;
        lastDoc = snapshot.docs.last;
      }

      final localIdsCount = idsLocais.length;
      final deleteCandidatesCount = toDelete.length;

      final blockReason = SyncMassDeleteGuard.estoqueExcedentesBlockReason(
        localIdsCount: localIdsCount,
        remoteCount: remoteCount,
        deleteCandidatesCount: deleteCandidatesCount,
        allowMassDelete: allowMassDelete,
      );

      if (blockReason == SyncMassDeleteBlockReason.localIdsEmptyWithRemote) {
        logW(
          '[SYNC-GUARD] Bloqueado limparProdutosExcedentesNoFirestore: conjunto local vazio '
          'lojaId=$lojaId collectionPath=$collectionPath localIdsCount=$localIdsCount '
          'remoteCount=$remoteCount deleteCandidatesCount=$deleteCandidatesCount '
          'allowMassDelete=$allowMassDelete caller=ProdutosFirestoreService.limparProdutosExcedentesNoFirestore',
        );
        return 0;
      }

      if (blockReason != SyncMassDeleteBlockReason.none) {
        logW(
          '[SYNC-GUARD] Bloqueado delete suspeito em estoque_produtos '
          'lojaId=$lojaId collectionPath=$collectionPath localIdsCount=$localIdsCount '
          'remoteCount=$remoteCount deleteCandidatesCount=$deleteCandidatesCount '
          'allowMassDelete=$allowMassDelete reason=$blockReason '
          'caller=ProdutosFirestoreService.limparProdutosExcedentesNoFirestore',
        );
        return 0;
      }

      if (toDelete.isNotEmpty) {
        logW(
          '[SYNC-GUARD] estoque_produtos: removendo ${toDelete.length} doc(s) excedente(s) '
          'lojaId=$lojaId collectionPath=$collectionPath localIdsCount=$localIdsCount '
          'remoteCount=$remoteCount deleteCandidatesCount=$deleteCandidatesCount '
          'allowMassDelete=$allowMassDelete caller=ProdutosFirestoreService.limparProdutosExcedentesNoFirestore',
        );
      }

      for (final id in toDelete) {
        await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(id)
            .delete();
      }

      if (toDelete.isNotEmpty) {
        logD(
            '🗑️ [PRODUTOS-SYNC] ${toDelete.length} produto(s) excedente(s) removido(s) do Firestore');
      }
      return toDelete.length;
    } catch (e, st) {
      logE(
          '❌ [PRODUTOS-SYNC] Erro ao limpar excedentes (type=${e.runtimeType})',
          error: e,
          st: st);
      return 0;
    }
  }

  /// Deleta um produto do Firestore
  static Future<void> deleteProduto(String produtoId, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      final ref = _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId);

      await ref.delete();

      final stillThere = await ref.get();
      if (stillThere.exists) {
        throw StateError(
          'estoque_produtos/$produtoId ainda existe após delete() — verifique permissões/rede.',
        );
      }

      logD('🗑️ [PRODUTOS-SYNC] Produto $produtoId deletado do Firestore');
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro ao deletar produto (type=${e.runtimeType})',
          error: e, st: st);
      rethrow;
    }
  }

  /// Remove de [estoque_produtos] com fallback quando [Produto.idFirebase] está vazio.
  /// Exige confirmação forte: slug (campo ou docId == slug local), ou código de barras.
  /// Não apaga só por nome (evita homônimos / doc errado).
  static Future<void> deleteProdutoRobusto({
    required Produto produto,
    required String lojaId,
  }) async {
    final idFb = produto.idFirebase.trim();
    if (idFb.isNotEmpty) {
      await deleteProduto(idFb, lojaId: lojaId);
      return;
    }

    final col = _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol);
    final tried = <String>{};

    Future<bool> tryDeleteDoc(String docId) async {
      final d = docId.trim();
      if (d.isEmpty || tried.contains(d)) return false;
      tried.add(d);
      final ref = col.doc(d);
      final snap = await ref.get();
      if (!snap.exists) return false;
      final data = snap.data() ?? {};
      final nomeR = (data['nome'] ?? '').toString().trim().toLowerCase();
      final nomeL = produto.nome.trim().toLowerCase();
      final slugR = (data['slug'] ?? '').toString().trim();
      final slugL = produto.slug.trim();
      final barrasR = (data['codigoBarras'] ?? '').toString().trim();
      final barrasL = produto.codigoBarras.trim();

      final matchSlug = slugL.isNotEmpty && slugR == slugL;
      final matchBarras = barrasL.isNotEmpty && barrasR == barrasL;
      final docIdIsLocalSlug = slugL.isNotEmpty && d == slugL;
      final strongMatch = matchSlug || matchBarras || docIdIsLocalSlug;

      if (!strongMatch) {
        final nomeIgual = nomeL.isNotEmpty && nomeR == nomeL;
        if (nomeIgual) {
          logW(
            '[DELETE_FALLBACK] docId=$d: nome igual mas sem slug/barras/docId=slug — abortado (ambiguidade)',
          );
        } else {
          logW(
            '[DELETE_FALLBACK] docId=$d sem match forte (slug/barras/docId=slug) — não apagando',
          );
        }
        return false;
      }
      await ref.delete();
      final verify = await ref.get();
      if (verify.exists) {
        throw StateError(
          '[DELETE_FALLBACK] docId=$d ainda existe após delete — rede/permissão?',
        );
      }
      logD(
          '[DELETE_FALLBACK] estoque removido docId=$d (idFirebase vazio, match forte)');
      return true;
    }

    final slugL = produto.slug.trim();
    if (slugL.isNotEmpty) {
      final remoteId = await findEstoqueProdutoDocIdBySlug(
        lojaId: lojaId,
        slug: slugL,
      );
      if (remoteId == null) {
        logD(
          '[DELETE_FALLBACK] Nenhum estoque_produtos com slug=$slugL — nuvem já sem este item',
        );
        return;
      }
    }

    if (await tryDeleteDoc(produto.slug)) return;
    final fromNome = CatalogoSyncService.slugify(produto.nome);
    if (await tryDeleteDoc(fromNome)) return;

    throw StateError(
      '[DELETE_FALLBACK] Não foi possível remover estoque_produtos com segurança '
      '(idFirebase vazio; sem match forte por slug/barras/docId). '
      'loja=$lojaId nome=${produto.nome}',
    );
  }
}
