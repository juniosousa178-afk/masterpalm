// Resolução remota de docId para produtos importados — somente na sincronização.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/produto_firestore_doc_id_validator.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'produto_estoque_doc_id_service.dart';
import 'produto_exclusao_tombstone_service.dart';
import 'produto_import_doc_id_helper.dart';

/// Resultado da preparação remota antes do push.
class ProdutoImportSyncPrepResult {
  const ProdutoImportSyncPrepResult._({
    required this.ok,
    this.recuperacaoManual = false,
    this.tentativasEsgotadas = false,
    this.mensagem,
  });

  final bool ok;
  final bool recuperacaoManual;
  final bool tentativasEsgotadas;
  final String? mensagem;

  static const sucesso = ProdutoImportSyncPrepResult._(ok: true);

  static ProdutoImportSyncPrepResult manual(String msg) =>
      ProdutoImportSyncPrepResult._(
        ok: false,
        recuperacaoManual: true,
        mensagem: msg,
      );

  static ProdutoImportSyncPrepResult esgotado(String msg) =>
      ProdutoImportSyncPrepResult._(
        ok: false,
        tentativasEsgotadas: true,
        mensagem: msg,
      );
}

class ProdutoImportSyncPrepService {
  ProdutoImportSyncPrepService._();

  @visibleForTesting
  static const int maxTentativasColisao = 5;

  static Future<Box<Venda>?> _abrirVendasBox(String lojaId) async {
    final name = HiveBoxNames.vendas(lojaId);
    try {
      if (Hive.isBoxOpen(name)) {
        return Hive.box<Venda>(name);
      }
      return await Hive.openBox<Venda>(name);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _docIdRemotoIndisponivel({
    required String lojaId,
    required String docId,
  }) async {
    return ProdutoEstoqueDocIdService.docIdIndisponivelParaNovoProduto(
      lojaId: lojaId,
      docId: docId,
    );
  }

  static Future<String?> _resolverIdRemotoComLimite({
    required String lojaId,
    required String nome,
    int maxTentativas = maxTentativasColisao,
  }) async {
    final base = ProdutoEstoqueDocIdService.slugCanonicoParaLoja(
      lojaId: lojaId,
      nome: nome,
    );
    final candidatos = <String>[
      base,
      for (var n = 2; n <= maxTentativas; n++) '$base-$n',
    ];
    for (final c in candidatos) {
      if (!ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(c)) continue;
      if (!await _docIdRemotoIndisponivel(lojaId: lojaId, docId: c)) {
        return c;
      }
    }
    return null;
  }

  static Future<void> _aplicarNovoDocIdLocal({
    required Produto produto,
    required String novoDocId,
  }) async {
    produto.slug = novoDocId;
    produto.idFirebase = '';
    await produto.save();
  }

  /// Antes do push remoto: resolve colisão/tombstone para importados e reidentifica se seguro.
  static Future<ProdutoImportSyncPrepResult> prepareBeforeRemotePush({
    required Produto produto,
    required String lojaId,
  }) async {
    final storeId = lojaId.trim();
    if (storeId.isEmpty) {
      return ProdutoImportSyncPrepResult.esgotado(
        'Contexto de loja inválido para sincronização.',
      );
    }

    final atual = ProdutoFirestoreDocIdValidator.resolveProdutoIdFromProduto(
      produto,
    );
    if (atual == null) {
      return ProdutoImportSyncPrepResult.esgotado(
        'Identificador do produto ausente para sincronização.',
      );
    }

    final vendasBox = await _abrirVendasBox(storeId);
    final temVenda = vendasBox != null &&
        ProdutoImportDocIdHelper.produtoTemVendaOuReferencia(
          produto: produto,
          vendasBox: vendasBox,
          lojaId: storeId,
        );

    if (ProdutoImportDocIdHelper.isDocIdLocalImportacao(atual)) {
      final remoto = await _resolverIdRemotoComLimite(
        lojaId: storeId,
        nome: produto.nome,
      );
      if (remoto == null) {
        return ProdutoImportSyncPrepResult.esgotado(
          'Não foi possível obter identificador remoto livre para este produto.',
        );
      }
      await _aplicarNovoDocIdLocal(produto: produto, novoDocId: remoto);
      return ProdutoImportSyncPrepResult.sucesso;
    }

    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(storeId);
    final tombstonado =
        await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
      lojaId: storeId,
      estoqueDocId: atual,
    );

    if (!tombstonado) {
      return ProdutoImportSyncPrepResult.sucesso;
    }

    if (temVenda) {
      return ProdutoImportSyncPrepResult.manual(
        'Produto com vendas ou referências vinculadas requer recuperação manual.',
      );
    }

    final remoto = await _resolverIdRemotoComLimite(
      lojaId: storeId,
      nome: produto.nome,
    );
    if (remoto == null) {
      return ProdutoImportSyncPrepResult.esgotado(
        'Não foi possível obter identificador remoto livre após colisão.',
      );
    }
    await _aplicarNovoDocIdLocal(produto: produto, novoDocId: remoto);
    return ProdutoImportSyncPrepResult.sucesso;
  }
}
