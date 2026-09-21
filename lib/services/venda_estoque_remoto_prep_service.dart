// Prepara produtos do Hive para baixa Firestore na venda (sync + validação remota).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/produto_pending_stock_reconciliation.dart';
import '../core/produto_effective_stock.dart';
import '../core/produto_stock_revision.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produtos_firestore_service.dart';
import 'sync_queue_service.dart';

/// Mensagens estáveis para testes e UI.
class VendaEstoqueRemotoPrepMessages {
  static const sincronizando =
      'Este produto ainda está sincronizando com a nuvem. '
      'Aguarde alguns segundos, atualize o estoque e tente novamente.';

  static const identificadorExcluido =
      'Este produto usa um identificador que já foi excluído do estoque na nuvem. '
      'Abra o cadastro, altere o nome para gerar um novo código, sincronize e tente vender novamente.';

  static const removido =
      'Produto removido do estoque. Atualize a lista de produtos e tente novamente.';

  /// Mensagem legado (sem nome) — preferir [formatAlteracaoPendenteParaProdutos].
  static const alteracaoPendente =
      'Há alteração de estoque ainda não sincronizada neste produto. '
      'Sincronize o estoque antes de finalizar a venda.';

  static const estoqueRemotoInsuficiente =
      'Estoque insuficiente na nuvem para um ou mais produtos. '
      'Atualize a tela e tente novamente.';

  static String formatAlteracaoPendenteParaProdutos(List<Produto> produtos) {
    final uniq = <String, Produto>{};
    for (final p in produtos) {
      final key = p.idFirebase.trim().isNotEmpty
          ? p.idFirebase.trim()
          : '${p.codigoBarras}|${p.nome}';
      uniq.putIfAbsent(key, () => p);
    }
    final list = uniq.values.toList();
    if (list.isEmpty) {
      return 'Há alteração de estoque ainda não confirmada na nuvem. '
          'Abra Estoque, toque em "Tentar novamente" e só então finalize a venda.';
    }
    const maxShow = 3;
    final lines = <String>[];
    for (final p in list.take(maxShow)) {
      final nome = p.nome.trim().isEmpty ? 'Produto' : p.nome.trim();
      final codigo = p.codigoBarras.trim();
      lines.add(codigo.isEmpty ? nome : '$nome — código $codigo');
    }
    final remaining = list.length - maxShow;
    final body = lines.join('\n');
    final extra = remaining > 0 ? '\n… e mais $remaining produto(s).' : '';
    return 'Não foi possível confirmar o estoque na nuvem de:\n$body$extra\n\n'
        'Isso pode ser pendência local, conflito de revisão ou falha de sync — '
        'não indica necessariamente falta de internet. '
        'Abra Estoque, toque em "Tentar novamente" e tente a venda de novo.';
  }
}

/// Erro amigável quando pendência real persiste após auto-sync.
/// Não usar [StateError] — evita "Bad state:" na UI.
class PendingStockSyncRequiredException implements Exception {
  PendingStockSyncRequiredException(this.produtos);

  final List<Produto> produtos;

  String get message =>
      VendaEstoqueRemotoPrepMessages.formatAlteracaoPendenteParaProdutos(
        produtos,
      );

  @override
  String toString() => message;
}

/// Garante que itens da venda existem em `estoque_produtos` antes da baixa.
class VendaEstoqueRemotoPrepService {
  static FirebaseFirestore get _db =>
      ProdutosFirestoreService.debugFirestoreOverride ??
      FirebaseFirestore.instance;

  /// Pipeline oficial de flush (wired por [EstoqueService] / testes).
  /// Retorna true se a pendência foi confirmada ou limpa com segurança.
  @visibleForTesting
  static Future<bool> Function(String lojaId, Produto produto)?
      flushPendingStockMutationImpl;

  /// Hook READ-ONLY de diagnóstico de prep (testes / console). Sem writes.
  @visibleForTesting
  static void Function(Map<String, Object?> event)? debugPrepTraceHook;

  @visibleForTesting
  static String estoqueDocIdCanonico(Produto p) {
    final id = p.idFirebase.trim();
    if (id.isNotEmpty) return id;
    return p.slug.trim();
  }

  /// Verifica existência do documento em `estoque_produtos` (id, slug ou nome).
  @visibleForTesting
  static Future<bool> estoqueDocExisteRemoto({
    required String lojaId,
    required Produto produto,
  }) async {
    return produtoExisteNoEstoqueRemoto(lojaId: lojaId, produto: produto);
  }

  /// API pública — usada por manutenção de combo e prep de venda.
  static Future<bool> produtoExisteNoEstoqueRemoto({
    required String lojaId,
    required Produto produto,
  }) async {
    final col = _db.collection('lojas').doc(lojaId).collection(FSPaths.estoqueProdutosCol);
    final docId = estoqueDocIdCanonico(produto);
    if (docId.isNotEmpty) {
      if ((await col.doc(docId).get()).exists) return true;
    }
    final slug = produto.slug.trim();
    if (slug.isNotEmpty) {
      final q = await col.where('slug', isEqualTo: slug).limit(1).get();
      if (q.docs.isNotEmpty) return true;
    }
    final nome = produto.nome.trim();
    if (nome.isNotEmpty) {
      final q = await col.where('nome', isEqualTo: nome).limit(1).get();
      if (q.docs.isNotEmpty) return true;
    }
    return false;
  }

  /// Produto já existe em `estoque_produtos` e não está tombstonado — dispensa sync na venda.
  @visibleForTesting
  static Future<bool> produtoProntoParaBaixaSemSync({
    required String lojaId,
    required Produto produto,
  }) async {
    final docId = estoqueDocIdCanonico(produto);
    if (docId.isEmpty) return false;
    if (!await estoqueDocExisteRemoto(lojaId: lojaId, produto: produto)) {
      return false;
    }
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
    final bloqueado = await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
      lojaId: lojaId,
      estoqueDocId: docId,
    );
    return !bloqueado;
  }

  /// Diagnóstico temporário (sem PII sensível) imediatamente antes do bloqueio de pendência.
  @visibleForTesting
  static void Function(Map<String, Object?> diag)? debugPendingSaleBlockHook;

  @visibleForTesting
  static Map<String, Object?> buildPendingSaleBlockDiag({
    required Produto produto,
    required Map<String, dynamic>? remoteData,
  }) {
    final remoteQty = (remoteData?['quantidade'] as num?)?.toInt();
    return <String, Object?>{
      'produtoId': produto.idFirebase,
      'codigo': produto.codigoBarras,
      'nome': produto.nome,
      'variacaoId': '',
      'tamanho': '',
      'cor': '',
      'quantidadeSolicitada': null,
      'estoqueLocal': produto.quantidade,
      'estoqueRemotoConhecido': remoteQty,
      'estoqueCanonico': remoteQty,
      'pendingSync': hasPendingStockMutation(produto),
      'dirty': hasPendingStockMutation(produto),
      'pendingStockOperationId': produto.pendingStockOperationId,
      'pendingStockBaseRevision': produto.pendingStockBaseRevision,
      'stockRevisionLocal': produto.stockRevision,
      'stockRevisionRemoto':
          remoteData == null ? null : parseStockRevisionFromRemote(remoteData),
      'stockOperationIdRemoto':
          remoteData == null ? null : parseStockOperationIdFromRemote(remoteData),
      'updatedAt': produto.updatedAt?.toIso8601String(),
      'lastSyncedAt': produto.stockUpdatedAt?.toIso8601String(),
      'stockSyncState': produto.stockSyncState,
    };
  }

  /// Tenta enviar a pendência local via pipeline oficial (idempotente).
  @visibleForTesting
  static Future<bool> tryFlushPendingStockMutation({
    required String lojaId,
    required Produto produto,
  }) async {
    if (!hasPendingStockMutation(produto)) return true;
    final impl = flushPendingStockMutationImpl;
    if (impl == null) {
      debugPrint(
        '[PENDING_STOCK_SYNC_REQUIRED] flushImpl=null '
        'produto=${produto.idFirebase} codigo=${produto.codigoBarras}',
      );
      return false;
    }
    try {
      final ok = await impl(lojaId, produto);
      if (ok && !hasPendingStockMutation(produto)) return true;
      return !hasPendingStockMutation(produto);
    } catch (e, st) {
      debugPrint(
        '[PENDING_STOCK_SYNC_REQUIRED] flush_error type=${e.runtimeType} $e\n$st',
      );
      return false;
    }
  }

  /// Reconcilia pendência obsoleta contra o documento remoto canônico.
  /// Mantém bloqueio se a alteração local ainda não estiver no servidor.
  @visibleForTesting
  static Future<bool> reconcilePendingStockMutationForSale({
    required String lojaId,
    required Produto produto,
  }) async {
    if (!hasPendingStockMutation(produto)) return true;
    final docId = produto.idFirebase.trim();
    if (docId.isEmpty) return false;

    final snapshot = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(docId)
        .get();
    final data = snapshot.data();
    final diag = buildPendingSaleBlockDiag(produto: produto, remoteData: data);
    debugPendingSaleBlockHook?.call(diag);
    debugPrint('[VENDA-PREP-PENDING] $diag');

    if (!snapshot.exists || data == null) return false;

    // Clears seguros ANTES de flush (equivalent / superseded / structural).
    if (reconcileSafeLocalPendingAgainstRemote(produto, remote: data)) {
      if (produto.isInBox) await produto.save();
      return !hasPendingStockMutation(produto);
    }

    final decision = classifyPendingAgainstRemote(
      local: produto,
      remote: data,
    );
    // Nunca flush superseded / structural / manual / equivalent.
    if (decision.classification.mustNeverFlush) {
      return false;
    }

    if (tryConfirmStockFromRemote(produto, data)) {
      if (produto.isInBox) await produto.save();
      return !hasPendingStockMutation(produto);
    }
    if (abandonStalePendingStockMutationIfRemoteAdvanced(
      produto,
      remoteData: data,
    )) {
      if (produto.isInBox) await produto.save();
      return !hasPendingStockMutation(produto);
    }
    return false;
  }

  /// Flush → reconcile → GREEN se pendência sumir.
  @visibleForTesting
  static Future<bool> ensurePendingStockReadyForSale({
    required String lojaId,
    required Produto produto,
  }) async {
    if (!hasPendingStockMutation(produto)) return true;

    // Reconcile-only primeiro (sem stock command).
    final reconciledEarly = await reconcilePendingStockMutationForSale(
      lojaId: lojaId,
      produto: produto,
    );
    if (!hasPendingStockMutation(produto)) return true;
    if (!reconciledEarly) {
      // mustNeverFlush (manual/structural não limpo) — nunca replace.
      final docId = produto.idFirebase.trim();
      if (docId.isNotEmpty) {
        final snap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(docId)
            .get();
        final data = snap.data();
        if (data != null) {
          final decision = classifyPendingAgainstRemote(
            local: produto,
            remote: data,
          );
          if (decision.classification.mustNeverFlush) {
            return false;
          }
        }
      }
    }

    // Só REAL_PENDING pode ir a stockCatalogCommand replace.
    final flushed = await tryFlushPendingStockMutation(
      lojaId: lojaId,
      produto: produto,
    );
    if (flushed && !hasPendingStockMutation(produto)) return true;

    final reconciled = await reconcilePendingStockMutationForSale(
      lojaId: lojaId,
      produto: produto,
    );
    return reconciled && !hasPendingStockMutation(produto);
  }

  /// Após limpar pending / antes da baixa: alinha Hive ao remoto autoritativo.
  /// Não mascara pending real restante.
  @visibleForTesting
  static Future<void> refreshAuthoritativeStockCacheForSale({
    required String lojaId,
    required Produto produto,
  }) async {
    if (hasPendingStockMutation(produto)) return;
    final docId = produto.idFirebase.trim();
    if (docId.isEmpty) return;
    final snap = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(docId)
        .get();
    final data = snap.data();
    if (!snap.exists || data == null) return;
    applyAuthoritativeRemoteStockToProduto(
      produto,
      remote: data,
      updateQuantity: true,
    );
    if (produto.isInBox) await produto.save();
  }

  static Future<void> garantirProdutosProntosParaBaixa({
    required String lojaId,
    required List<Produto> produtos,
  }) async {
    final li = lojaId.trim();
    if (li.isEmpty) return;

    final blocked = <Produto>[];
    for (final produto in produtos) {
      if (produto.lojaId.trim().isNotEmpty && produto.lojaId.trim() != li) {
        continue;
      }
      final pendingBefore = hasPendingStockMutation(produto);
      var reconciliationClass = 'NO_PENDING';
      var mustNeverFlush = false;
      var flushAttempted = false;
      debugPrepTraceHook?.call({
        'event': 'PREP_START',
        'productId': produto.idFirebase,
        'PENDING_BEFORE': pendingBefore,
      });
      debugPrint(
        '[VENDA-PREP-TRACE] PREP_START productId=${produto.idFirebase} '
        'PENDING_BEFORE=$pendingBefore',
      );
      if (hasPendingStockMutation(produto)) {
        // Classificação pré-flush (read remoto) para diagnóstico.
        try {
          final docId = produto.idFirebase.trim();
          if (docId.isNotEmpty) {
            final snap = await _db
                .collection('lojas')
                .doc(li)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(docId)
                .get();
            final data = snap.data();
            if (data != null) {
              final decision = classifyPendingAgainstRemote(
                local: produto,
                remote: data,
              );
              reconciliationClass = decision.classification.wire;
              mustNeverFlush = decision.classification.mustNeverFlush;
            }
          }
        } catch (_) {}
        final ready = await ensurePendingStockReadyForSale(
          lojaId: li,
          produto: produto,
        );
        // Flush só ocorre em ensurePending quando !mustNeverFlush; erros de
        // flush são engolidos (não rethrow). Marca intenção diagnóstica.
        flushAttempted = pendingBefore && !mustNeverFlush;
        if (!ready || hasPendingStockMutation(produto)) {
          blocked.add(produto);
          final diag = buildPendingSaleBlockDiag(
            produto: produto,
            remoteData: null,
          );
          debugPendingSaleBlockHook?.call(diag);
          debugPrint('[PENDING_STOCK_SYNC_REQUIRED] $diag');
          debugPrepTraceHook?.call({
            'event': 'PREP_BLOCKED',
            'productId': produto.idFirebase,
            'RECONCILIATION_CLASS': reconciliationClass,
            'MUST_NEVER_FLUSH': mustNeverFlush,
            'FLUSH_ATTEMPTED': flushAttempted,
            'PENDING_AFTER': hasPendingStockMutation(produto),
          });
          continue;
        }
      }
      final pendingAfter = hasPendingStockMutation(produto);
      // Sempre refrescar revision/op/qty do remoto após reconcile (evita
      // cart/Hive com token stale pós-picker).
      var remoteRefreshSuccess = false;
      var remoteRevAfter = produto.stockRevision;
      try {
        await refreshAuthoritativeStockCacheForSale(
          lojaId: li,
          produto: produto,
        );
        remoteRefreshSuccess = !hasPendingStockMutation(produto);
        remoteRevAfter = produto.stockRevision;
      } catch (e) {
        debugPrint(
          '[VENDA-PREP-REFRESH] falha type=${e.runtimeType} '
          'produto=${produto.idFirebase}',
        );
      }
      debugPrepTraceHook?.call({
        'event': 'PREP_DONE',
        'productId': produto.idFirebase,
        'PENDING_BEFORE': pendingBefore,
        'RECONCILIATION_CLASS': reconciliationClass,
        'MUST_NEVER_FLUSH': mustNeverFlush,
        'FLUSH_ATTEMPTED': flushAttempted,
        'PENDING_AFTER': pendingAfter,
        'REMOTE_REFRESH_SUCCESS': remoteRefreshSuccess,
        'REMOTE_REVISION_AFTER_REFRESH': remoteRevAfter,
      });
      debugPrint(
        '[VENDA-PREP-TRACE] PREP_DONE productId=${produto.idFirebase} '
        'CLASS=$reconciliationClass MUST_NEVER_FLUSH=$mustNeverFlush '
        'FLUSH_ATTEMPTED=$flushAttempted PENDING_AFTER=$pendingAfter '
        'REFRESH=$remoteRefreshSuccess REV=$remoteRevAfter',
      );
    }
    if (blocked.isNotEmpty) {
      throw PendingStockSyncRequiredException(blocked);
    }

    if (ProdutosFirestoreService.debugFirestoreOverride == null) {
      for (final produto in produtos) {
        if (produto.lojaId != li || produto.idFirebase.trim().isEmpty) {
          throw Exception(VendaEstoqueRemotoPrepMessages.sincronizando);
        }
        final snapshot = await _db
            .collection('lojas')
            .doc(li)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(produto.idFirebase)
            .get();
        if (!snapshot.exists) {
          throw Exception(VendaEstoqueRemotoPrepMessages.sincronizando);
        }
        final data = snapshot.data() ?? <String, dynamic>{};
        if (data['pendingSoftDelete'] == true) {
          throw Exception(VendaEstoqueRemotoPrepMessages.removido);
        }
        final remoteQty = (data['quantidade'] as num?)?.toInt() ?? 0;
        // Hive otimista positivo com remoto zerado: não permitir vender saldo não confirmado.
        if (remoteQty <= 0 && produto.quantidade > 0) {
          throw Exception(
            VendaEstoqueRemotoPrepMessages.estoqueRemotoInsuficiente,
          );
        }
      }
      return;
    }

    final vistos = <String>{};
    final unicos = <Produto>[];
    for (final p in produtos) {
      if (p.lojaId.trim().isNotEmpty && p.lojaId.trim() != li) continue;
      final chave = '${p.key ?? ''}|${estoqueDocIdCanonico(p)}|${p.slug}|${p.nome}';
      if (vistos.add(chave)) unicos.add(p);
    }

    for (final p in unicos) {
      if (await produtoProntoParaBaixaSemSync(lojaId: li, produto: p)) {
        continue;
      }
      await _garantirProduto(li, p);
    }
  }

  static Future<void> _garantirProduto(String lojaId, Produto produto) async {
    final nomeExib = produto.nome.trim().isEmpty ? 'Produto' : produto.nome.trim();
    final docIdAntes = estoqueDocIdCanonico(produto);
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);

    if (docIdAntes.isNotEmpty) {
      final tombstoneAntes =
          await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
        lojaId: lojaId,
        estoqueDocId: docIdAntes,
      );
      if (tombstoneAntes) {
        final existeAntes = await estoqueDocExisteRemoto(
          lojaId: lojaId,
          produto: produto,
        );
        throw Exception(
          '"$nomeExib": ${existeAntes ? VendaEstoqueRemotoPrepMessages.removido : VendaEstoqueRemotoPrepMessages.identificadorExcluido}',
        );
      }
    }

    var status = await ProdutosFirestoreService.syncProdutoComStatus(
      produto,
      lojaId: lojaId,
      enqueueOnFailure: true,
      bumpHiveTimestamp: false,
    );

    if (status == ProdutoSyncRemotoStatus.pendenteFila) {
      try {
        await SyncQueueService.processPending();
      } catch (_) {}
      status = await ProdutosFirestoreService.syncProdutoComStatus(
        produto,
        lojaId: lojaId,
        enqueueOnFailure: true,
        bumpHiveTimestamp: false,
      );
    }

    final docId = estoqueDocIdCanonico(produto);
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);

    final existeRemoto = await estoqueDocExisteRemoto(
      lojaId: lojaId,
      produto: produto,
    );

    final tombstone = docId.isNotEmpty &&
        await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
          lojaId: lojaId,
          estoqueDocId: docId,
        );

    if (status == ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone) {
      throw Exception(
        '"$nomeExib": ${VendaEstoqueRemotoPrepMessages.identificadorExcluido}',
      );
    }

    if (!existeRemoto) {
      if (status == ProdutoSyncRemotoStatus.confirmado) {
        throw Exception(
          '"$nomeExib": ${VendaEstoqueRemotoPrepMessages.sincronizando}',
        );
      }
      throw Exception(
        '"$nomeExib": ${VendaEstoqueRemotoPrepMessages.sincronizando}',
      );
    }

    if (tombstone) {
      if (status == ProdutoSyncRemotoStatus.bloqueadoExclusaoTombstone ||
          status == ProdutoSyncRemotoStatus.pendenteFila ||
          status == ProdutoSyncRemotoStatus.falhaRemota) {
        throw Exception(
          '"$nomeExib": ${VendaEstoqueRemotoPrepMessages.identificadorExcluido}',
        );
      }
      throw Exception(
        '"$nomeExib": ${VendaEstoqueRemotoPrepMessages.removido}',
      );
    }

    if (status != ProdutoSyncRemotoStatus.confirmado &&
        status != ProdutoSyncRemotoStatus.semMudancas) {
      throw Exception(
        '"$nomeExib": ${VendaEstoqueRemotoPrepMessages.sincronizando}',
      );
    }
  }
}
