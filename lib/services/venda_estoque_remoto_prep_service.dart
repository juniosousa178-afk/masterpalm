// Prepara produtos do Hive para baixa Firestore na venda (sync + validação remota).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
}

/// Garante que itens da venda existem em `estoque_produtos` antes da baixa.
class VendaEstoqueRemotoPrepService {
  static FirebaseFirestore get _db =>
      ProdutosFirestoreService.debugFirestoreOverride ??
      FirebaseFirestore.instance;

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

  static Future<void> garantirProdutosProntosParaBaixa({
    required String lojaId,
    required List<Produto> produtos,
  }) async {
    final li = lojaId.trim();
    if (li.isEmpty) return;

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
