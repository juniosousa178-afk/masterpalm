// Preview read-only da recuperação assistida de sincronização de estoque.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/combo_config_canonical.dart';
import '../core/firestore_access_guard.dart';
import '../core/hive_box_names.dart';
import '../core/produto_firestore_doc_id_validator.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'firestore_paths.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produto_import_doc_id_helper.dart';
import 'produto_sync_erro_util.dart';
import 'produto_sync_recovery_access.dart';
import 'produto_sync_recovery_journal_service.dart';
import 'produto_sync_recovery_mask_util.dart';
import 'produto_sync_recovery_models.dart';
import 'store_resolver_service.dart';
import 'sync_queue_service.dart';

class ProdutoSyncRecoveryPreviewService {
  ProdutoSyncRecoveryPreviewService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static Set<String>? debugRemoteDocIdsOverride;

  @visibleForTesting
  static int? debugRemoteCountOverride;

  @visibleForTesting
  static int? debugTombstoneCountOverride;

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: debugFirestoreOverride,
      );

  /// Gera preview sem alterar Hive, fila nem Firestore.
  static Future<RecoveryPreview> gerarPreview() async {
    final user = FirebaseAuth.instance.currentUser;
    final uidMascarado = ProdutoSyncRecoveryMaskUtil.mascararUid(user?.uid);

    final sessaoStoreId =
        await StoreResolverService.readValidatedSessionStoreId();
    String? lojaCanonica;
    var ownerConfirmado = false;
    var offline = false;
    String? erroRemoto;

    try {
      lojaCanonica =
          await StoreResolverService.resolveCanonicalOwnerStoreFromProfile();
      if (lojaCanonica != null && lojaCanonica.isNotEmpty) {
        ownerConfirmado =
            await ProdutoSyncRecoveryAccess.canonicalPertenceAoUsuario(
          lojaCanonica,
        );
      }
    } catch (e) {
      offline = true;
      erroRemoto = ProdutoSyncErroUtil.sanitizar(e);
    }

    final diverge = sessaoStoreId != null &&
        lojaCanonica != null &&
        sessaoStoreId != lojaCanonica;

    final identity = RecoveryStoreIdentity(
      uidMascarado: uidMascarado,
      sessaoStoreId: sessaoStoreId,
      lojaCanonica: lojaCanonica,
      sessaoDivergeDaCanonica: diverge,
      ownerUidConfirmado: ownerConfirmado,
    );

    final podeReparar = diverge &&
        ownerConfirmado &&
        await ProdutoSyncRecoveryAccess.podeAcessarRecuperacao();

    final sessionMismatch = RecoverySessionMismatch(
      sessaoStoreId: sessaoStoreId,
      lojaCanonica: lojaCanonica,
      podeReparar: podeReparar,
      motivoBloqueio: diverge && !podeReparar
          ? 'Reparo indisponível (permissão ou propriedade da loja)'
          : null,
    );

    final lojaAnalise = lojaCanonica ?? sessaoStoreId ?? '';
    final produtosSessao = await _contarProdutosHive(sessaoStoreId);
    final produtosCanonica = await _contarProdutosHive(lojaCanonica);

    Set<String> remoteDocIds = {};
    int? remoteCount;
    int? tombstoneCount;

    if (lojaAnalise.isNotEmpty) {
      if (debugRemoteDocIdsOverride != null) {
        remoteDocIds = Set<String>.from(debugRemoteDocIdsOverride!);
        remoteCount = debugRemoteCountOverride ?? remoteDocIds.length;
        tombstoneCount = debugTombstoneCountOverride ?? 0;
      } else {
        try {
          final snap = await _db
              .collection('lojas')
              .doc(lojaAnalise)
              .collection(FSPaths.estoqueProdutosCol)
              .get();
          remoteDocIds = snap.docs.map((d) => d.id).toSet();
          remoteCount = snap.docs.length;
        } catch (e) {
          offline = true;
          erroRemoto ??= ProdutoSyncErroUtil.sanitizar(e);
        }

        try {
          await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaAnalise);
          if (debugTombstoneCountOverride != null) {
            tombstoneCount = debugTombstoneCountOverride;
          } else {
            final ts = await _db
                .collection('lojas')
                .doc(lojaAnalise)
                .collection(FSPaths.exclusaoProdutoCol)
                .get();
            tombstoneCount = ts.docs.length;
          }
        } catch (e) {
          offline = true;
          erroRemoto ??= ProdutoSyncErroUtil.sanitizar(e);
        }
      }
    }

    final filaItens = <RecoveryQueueItem>[];
    var filaPendentes = 0;
    var filaDead = 0;
    final queueByEntity = <int, SyncQueueDiagnosticEntry>{};

    try {
      final entries = await SyncQueueService.listDiagnosticEntries();
      for (final e in entries) {
        if (e.type != SyncOperationType.upsertProduto) continue;
        final lojaDiv = lojaCanonica != null && e.lojaId != lojaCanonica;
        if (e.lojaId == lojaAnalise || lojaDiv) {
          if (e.deadLetter) {
            filaDead++;
          } else {
            filaPendentes++;
          }
          filaItens.add(
            RecoveryQueueItem(
              entityKey: e.entityKey,
              lojaId: ProdutoSyncRecoveryMaskUtil.mascararLojaId(e.lojaId),
              deadLetter: e.deadLetter,
              erroSanitizado: ProdutoSyncErroUtil.sanitizar(e.lastError),
              lojaDivergente: lojaDiv,
            ),
          );
          queueByEntity[e.entityKey] = e;
        }
      }
    } catch (_) {}

    final produtosClassificados = <RecoveryProdutoItem>[];
    if (lojaAnalise.isNotEmpty) {
      final box = await _abrirProdutosBox(lojaAnalise);
      final vendasBox = await _abrirVendasBox(lojaAnalise);
      final todos = box?.values.toList() ?? <Produto>[];

      if (box != null) {
        for (final p in box.values) {
          final key = p.key;
          if (key is! int) continue;

          final filaEntry = queueByEntity[key];
          final classificacao = await _classificarProduto(
            produto: p,
            lojaCanonica: lojaCanonica ?? lojaAnalise,
            sessaoStoreId: sessaoStoreId,
            remoteDocIds: remoteDocIds,
            todosProdutos: todos,
            vendasBox: vendasBox,
            filaLojaDivergente: filaEntry != null &&
                lojaCanonica != null &&
                filaEntry.lojaId != lojaCanonica,
          );

          produtosClassificados.add(
            RecoveryProdutoItem(
              entityKey: key,
              nomeMascarado: ProdutoSyncRecoveryMaskUtil.mascararNome(p.nome),
              classificacao: classificacao,
              motivoSanitizado: _motivoClassificacao(classificacao),
              temFilaPendente: filaEntry != null && !filaEntry.deadLetter,
              filaDeadLetter: filaEntry?.deadLetter ?? false,
            ),
          );
        }
      }
    }

    final journalIncompleto =
        await ProdutoSyncRecoveryJournalService.resumoIncompletos(
      lojaId: lojaAnalise.isNotEmpty ? lojaAnalise : null,
    );

    return RecoveryPreview(
      identity: identity,
      sessionMismatch: sessionMismatch,
      produtosLocaisSessao: produtosSessao,
      produtosLocaisCanonica: produtosCanonica,
      produtosRemotos: remoteCount,
      tombstones: tombstoneCount,
      filaPendentes: filaPendentes,
      filaDeadLetter: filaDead,
      filaItens: filaItens,
      produtos: produtosClassificados,
      offline: offline,
      erroRemotoSanitizado: erroRemoto,
      remoteDocIdsConhecidos: remoteDocIds,
      journalIncompleto: journalIncompleto,
    );
  }

  static String? _motivoClassificacao(RecoveryProdutoClassificacao c) {
    switch (c) {
      case RecoveryProdutoClassificacao.comVendaOuReferencia:
      case RecoveryProdutoClassificacao.recuperacaoManualNecessaria:
        return 'Produto com vendas ou referências vinculadas';
      case RecoveryProdutoClassificacao.comVinculoCombo:
        return 'Produto é combo ou item de combo';
      case RecoveryProdutoClassificacao.conflitoRemoto:
        return 'Conflito com produto remoto existente';
      case RecoveryProdutoClassificacao.tombstoneLegado:
        return 'Identificador bloqueado por exclusão anterior';
      case RecoveryProdutoClassificacao.lojaDivergente:
        return 'Produto pertence a outra loja';
      case RecoveryProdutoClassificacao.filaLojaDivergente:
        return 'Fila de sync aponta para loja divergente';
      default:
        return null;
    }
  }

  /// Classifica um produto local (sem efeitos colaterais).
  static Future<RecoveryProdutoClassificacao> classificarProdutoLocal({
    required Produto produto,
    required String lojaCanonica,
    required Set<String> remoteDocIds,
    required List<Produto> todosProdutos,
    Box<Venda>? vendasBox,
    String? sessaoStoreId,
    bool filaLojaDivergente = false,
  }) {
    return _classificarProduto(
      produto: produto,
      lojaCanonica: lojaCanonica,
      sessaoStoreId: sessaoStoreId,
      remoteDocIds: remoteDocIds,
      todosProdutos: todosProdutos,
      vendasBox: vendasBox,
      filaLojaDivergente: filaLojaDivergente,
    );
  }

  static Future<RecoveryProdutoClassificacao> _classificarProduto({
    required Produto produto,
    required String lojaCanonica,
    required Set<String> remoteDocIds,
    required List<Produto> todosProdutos,
    required Box<Venda>? vendasBox,
    String? sessaoStoreId,
    bool filaLojaDivergente = false,
  }) async {
    if (produto.nome.trim().isEmpty) {
      return RecoveryProdutoClassificacao.dadosInsuficientes;
    }

    final lojaProd = produto.lojaId.trim();
    if (lojaProd.isNotEmpty && lojaProd != lojaCanonica.trim()) {
      return RecoveryProdutoClassificacao.lojaDivergente;
    }

    if (filaLojaDivergente) {
      return RecoveryProdutoClassificacao.filaLojaDivergente;
    }

    final resolvedId =
        ProdutoFirestoreDocIdValidator.resolveProdutoIdFromProduto(produto);
    final idFb = produto.idFirebase.trim();
    final slug = produto.slug.trim();

    final remotoConfirmado = idFb.isNotEmpty && remoteDocIds.contains(idFb);
    if (remotoConfirmado) {
      return RecoveryProdutoClassificacao.jaSincronizado;
    }

    if (slug.isNotEmpty &&
        remoteDocIds.contains(slug) &&
        (idFb.isEmpty || idFb == slug)) {
      return RecoveryProdutoClassificacao.jaSincronizado;
    }

    final ehCombo = produto.ehCombo ||
        ComboConfigCanonical.isEffective(produto.comboConfig) ||
        (produto.itensCombo != null && produto.itensCombo!.isNotEmpty);
    final referenciadoCombo = _produtoReferenciadoEmCombo(produto, todosProdutos);

    if (ehCombo || referenciadoCombo) {
      return RecoveryProdutoClassificacao.comVinculoCombo;
    }

    if (vendasBox != null &&
        ProdutoImportDocIdHelper.produtoTemVendaOuReferencia(
          produto: produto,
          vendasBox: vendasBox,
          lojaId: lojaCanonica,
        )) {
      return RecoveryProdutoClassificacao.recuperacaoManualNecessaria;
    }

    if (resolvedId != null &&
        slug.isNotEmpty &&
        remoteDocIds.contains(slug) &&
        idFb.isNotEmpty &&
        idFb != slug) {
      return RecoveryProdutoClassificacao.conflitoRemoto;
    }

    var tombstonado = false;
    if (resolvedId != null && lojaCanonica.isNotEmpty) {
      if (ProdutoExclusaoTombstoneService.isProdutoBloqueadoSinc(
        lojaCanonica,
        resolvedId,
      )) {
        tombstonado = true;
      } else {
        try {
          tombstonado =
              await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
            lojaId: lojaCanonica,
            estoqueDocId: resolvedId,
          );
        } catch (_) {}
      }
    }

    if (tombstonado) {
      if (vendasBox != null &&
          ProdutoImportDocIdHelper.produtoTemVendaOuReferencia(
            produto: produto,
            vendasBox: vendasBox,
            lojaId: lojaCanonica,
          )) {
        return RecoveryProdutoClassificacao.recuperacaoManualNecessaria;
      }
      return RecoveryProdutoClassificacao.elegivelParaRecuperacao;
    }

    if (idFb.isEmpty &&
        slug.isNotEmpty &&
        !ProdutoImportDocIdHelper.isDocIdLocalImportacao(slug) &&
        !remoteDocIds.contains(slug)) {
      return RecoveryProdutoClassificacao.elegivelParaRecuperacao;
    }

    if (ProdutoImportDocIdHelper.isDocIdLocalImportacao(slug) &&
        idFb.isEmpty) {
      return RecoveryProdutoClassificacao.elegivelParaRecuperacao;
    }

    if (slug.isNotEmpty && remoteDocIds.contains(slug) && idFb.isEmpty) {
      return RecoveryProdutoClassificacao.conflitoRemoto;
    }

    return RecoveryProdutoClassificacao.dadosInsuficientes;
  }

  static bool _produtoReferenciadoEmCombo(
    Produto alvo,
    List<Produto> todos,
  ) {
    final ids = <String>{
      alvo.idFirebase.trim(),
      alvo.slug.trim(),
      if (alvo.key != null) alvo.key.toString(),
    }..removeWhere((e) => e.isEmpty);

    for (final p in todos) {
      if (p.key == alvo.key) continue;
      final itens = p.itensCombo;
      if (itens == null || itens.isEmpty) continue;
      for (final item in itens) {
        final pid = (item['productId'] ?? item['slug'] ?? item['id'] ?? '')
            .toString()
            .trim();
        if (pid.isNotEmpty && ids.contains(pid)) return true;
      }
    }
    return false;
  }

  static Future<int> _contarProdutosHive(String? lojaId) async {
    if (lojaId == null || lojaId.isEmpty) return 0;
    final box = await _abrirProdutosBox(lojaId);
    return box?.length ?? 0;
  }

  static Future<Box<Produto>?> _abrirProdutosBox(String lojaId) async {
    final name = HiveBoxNames.produtos(lojaId);
    try {
      if (Hive.isBoxOpen(name)) return Hive.box<Produto>(name);
      return await Hive.openBox<Produto>(name);
    } catch (_) {
      return null;
    }
  }

  static Future<Box<Venda>?> _abrirVendasBox(String lojaId) async {
    final name = HiveBoxNames.vendas(lojaId);
    try {
      if (Hive.isBoxOpen(name)) return Hive.box<Venda>(name);
      return await Hive.openBox<Venda>(name);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void resetDebugOverridesForTests() {
    debugFirestoreOverride = null;
    debugRemoteDocIdsOverride = null;
    debugRemoteCountOverride = null;
    debugTombstoneCountOverride = null;
  }
}
