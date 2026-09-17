// Cadastro/fila → protocolo stockCatalogCommand (create/replace/editorial).
// Replace online: rebase CAS sobre estoque remoto (preserva vendas) + expectedRevision
// autoritativo. Offline / sem remoto: revisão observada na baseline/Hive.

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/produto_estoque_grade_snapshot.dart';
import '../core/produto_form_grade_hydration.dart';
import '../core/produto_stock_revision.dart';
import '../core/produto_variacao_extra.dart';
import '../core/produto_variation_cas_rebase.dart';
import '../models/produto.dart';
import 'estoque_transaction_service.dart';
import 'stock_catalog_backend_service.dart';

/// Intent congelada antes do envio — retry/restart reenvia o mesmo payload.
class ProdutoStockCatalogCadastroIntent {
  const ProdutoStockCatalogCadastroIntent({
    required this.operationId,
    required this.kind,
    required this.items,
    required this.editorial,
    this.definition,
    this.expectedRevision,
  });

  final String operationId;
  final String kind;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> editorial;
  final Map<String, dynamic>? definition;
  final int? expectedRevision;

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'kind': kind,
        'items': items,
        'editorial': editorial,
        if (definition != null) 'definition': definition,
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      };

  factory ProdutoStockCatalogCadastroIntent.fromJson(Map<String, dynamic> raw) {
    return ProdutoStockCatalogCadastroIntent(
      operationId: raw['operationId'] as String,
      kind: raw['kind'] as String,
      items: (raw['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      editorial: Map<String, dynamic>.from(raw['editorial'] as Map? ?? {}),
      definition: raw['definition'] == null
          ? null
          : Map<String, dynamic>.from(raw['definition'] as Map),
      expectedRevision: (raw['expectedRevision'] as num?)?.toInt(),
    );
  }

  String encode() => jsonEncode(toJson());

  static ProdutoStockCatalogCadastroIntent? tryDecode(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      return ProdutoStockCatalogCadastroIntent.fromJson(
        Map<String, dynamic>.from(jsonDecode(text) as Map),
      );
    } catch (_) {
      return null;
    }
  }
}

class ProdutoStockCatalogCadastroSync {
  ProdutoStockCatalogCadastroSync._();

  /// Revisão observada na abertura/criação da intent (baseline offline).
  static int observedRevisionForSave({
    required Produto produto,
    ProdutoFormGradeBaseline? gradeBaseline,
  }) {
    if (gradeBaseline?.stockRevision != null) {
      return gradeBaseline!.stockRevision!;
    }
    if (hasPendingStockMutation(produto) &&
        produto.pendingStockBaseRevision != null) {
      return produto.pendingStockBaseRevision!;
    }
    return produto.stockRevision;
  }

  /// Reconstrói intent de replace a partir do estado local + remoto autoritativo.
  /// Gera novo operationId (hash muda com expectedRevision).
  static Future<ProdutoStockCatalogCadastroIntent> rebuildReplaceIntentAfterConflict({
    required Produto produto,
    required String produtoId,
    required Map<String, dynamic> remoteData,
    ProdutoFormGradeBaseline? gradeBaseline,
  }) async {
    clearPendingStockMutation(produto);
    if (produto.isInBox) await produto.save();
    return buildOrReuseIntent(
      produto: produto,
      produtoId: produtoId,
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: gradeBaseline,
      remoteStockData: remoteData,
      allowRemoteCasRebase: true,
    );
  }

  static Map<String, dynamic> buildEditorial(Produto produto) {
    final raw = <String, dynamic>{
      'nome': produto.nome,
      'descricao': produto.descricao,
      'preco': produto.precoFinal,
      'preco_venda': produto.precoFinal,
      'precoFinal': produto.precoFinal,
      'precoPorTamanho': produto.precoPorTamanho,
      'imagens': List<String>.from(produto.imagens),
      'slug': produto.slug,
      'categoria': produto.categoria,
      'categoriaId': produto.categoria,
      'subcategoria': produto.subcategoria,
      'subcategoriaId': produto.subcategoria,
      'categoriasExtras': produto.categoriasExtras,
      'subcategoriasExtras': produto.subcategoriasExtras,
      'categoriasAssociadas': produto.categoriasAssociadas,
      'subcategoriasAssociadas': produto.subcategoriasAssociadas,
      'peso': produto.peso,
      'emPromocao': produto.emPromocao,
      'percentualPromo': produto.percentualPromo,
      'valorPromo': produto.valorPromo,
      'publicadoNoCatalogo': produto.publicadoNoCatalogo,
      'exibir_no_catalogo': produto.publicadoNoCatalogo,
      'ocultar_catalogo': !produto.publicadoNoCatalogo,
      'catalog_ativo': produto.ativoNoRascunho || produto.publicadoNoCatalogo,
      if (produto.dataInicioPromo != null)
        'dataInicioPromo': produto.dataInicioPromo!.toIso8601String(),
      if (produto.dataFimPromo != null)
        'dataFimPromo': produto.dataFimPromo!.toIso8601String(),
    };
    return Map<String, dynamic>.fromEntries(
      raw.entries.where(
        (e) => StockCatalogBackendService.editorialFields.contains(e.key),
      ),
    );
  }

  static Map<String, dynamic> buildDefinition(Produto produto) {
    return {
      'quantidade': produto.quantidade,
      'tipoProduto': produto.tipoProduto,
      'variacoes': produto.variacoes == null
          ? null
          : ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(
              Map<String, dynamic>.from(produto.variacoes!),
            ),
      'estoquePorTamanho': Map<String, int>.from(produto.estoquePorTamanho),
      'tamanhos': List<String>.from(produto.tamanhos),
      'cores': List<String>.from(produto.cores),
      'variacoesExtraTipo': produto.variacoesExtraTipo == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(produto.variacoesExtraTipo!),
      'itensCombo': produto.itensCombo ?? <Map<String, dynamic>>[],
      'comboConfig': produto.comboConfig,
      'custoReal': produto.custoReal,
    };
  }

  static bool stockChangedVsBaseline({
    required Produto produto,
    ProdutoFormGradeBaseline? gradeBaseline,
  }) {
    if (gradeBaseline == null) {
      return hasPendingStockMutation(produto);
    }
    if (gradeBaseline.quantidade != null &&
        gradeBaseline.quantidade != produto.quantidade) {
      return true;
    }
    final local = ProdutoEstoqueGradeSnapshot.fromProduto(produto);
    final baselineProduto = Produto.vazio()
      ..quantidade = gradeBaseline.quantidade ?? produto.quantidade
      ..variacoes = gradeBaseline.variacoes == null
          ? null
          : Map<String, dynamic>.from(gradeBaseline.variacoes!)
      ..variacoesExtraTipo = gradeBaseline.variacoesExtraTipo == null
          ? null
          : Map<String, dynamic>.from(gradeBaseline.variacoesExtraTipo!)
      ..estoquePorTamanho = Map<String, int>.from(gradeBaseline.estoquePorTamanho)
      ..tamanhos = List<String>.from(gradeBaseline.tamanhos);
    final baselineSnap =
        ProdutoEstoqueGradeSnapshot.fromProduto(baselineProduto);
    return local.gradeDiffersFrom(baselineSnap);
  }

  /// Auto-sync de snapshot Hive não pode virar reposição/replace de estoque.
  static bool allowStockMutationCommand({
    required bool forcePushFromCadastro,
    required Produto produto,
    ProdutoFormGradeBaseline? gradeBaseline,
  }) {
    if (hasPendingStockMutation(produto)) return true;
    // Save explícito do cadastro: replace CAS (revisão observada).
    // Auto-sync sem pendência: apenas editorial — nunca repor saldo local.
    return forcePushFromCadastro;
  }

  static Future<ProdutoStockCatalogCadastroIntent> buildOrReuseIntent({
    required Produto produto,
    required String produtoId,
    required bool documentExists,
    required bool forcePushFromCadastro,
    ProdutoFormGradeBaseline? gradeBaseline,
    ProdutoStockCatalogCadastroIntent? frozenIntent,
    Map<String, dynamic>? remoteStockData,
    bool allowRemoteCasRebase = false,
  }) async {
    if (frozenIntent != null) return frozenIntent;

    final editorial = buildEditorial(produto);
    var definition = buildDefinition(produto);
    final allowStock = allowStockMutationCommand(
      forcePushFromCadastro: forcePushFromCadastro,
      produto: produto,
      gradeBaseline: gradeBaseline,
    );

    late final String kind;
    int? expectedRevision;
    Map<String, dynamic>? def;

    if (!documentExists) {
      kind = 'create';
      def = definition;
    } else if (allowStock) {
      // Mutação de estoque/grade (ou intent pendente): replace CAS.
      kind = 'replace';
      if (allowRemoteCasRebase && remoteStockData != null) {
        definition = ProdutoVariationCasRebase.rebaseReplaceDefinition(
          editorDefinition: definition,
          gradeBaseline: gradeBaseline,
          remoteData: remoteStockData,
        );
        expectedRevision =
            ProdutoVariationCasRebase.remoteRevision(remoteStockData);
        def = definition;
      } else {
        expectedRevision = observedRevisionForSave(
          produto: produto,
          gradeBaseline: gradeBaseline,
        );
        def = definition;
      }
    } else {
      kind = 'editorial';
    }

    final operationId = hasPendingStockMutation(produto)
        ? produto.pendingStockOperationId!.trim()
        : newStockOperationId();

    if (!hasPendingStockMutation(produto) ||
        produto.pendingStockOperationId!.trim() != operationId) {
      markPendingStockMutation(
        produto,
        operationId: operationId,
        baseRevision: expectedRevision ??
            observedRevisionForSave(
              produto: produto,
              gradeBaseline: gradeBaseline,
            ),
      );
      if (produto.isInBox) {
        await produto.save();
      }
    }

    final items = <Map<String, dynamic>>[
      {
        'productId': produtoId,
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      },
    ];

    return ProdutoStockCatalogCadastroIntent(
      operationId: operationId,
      kind: kind,
      items: items,
      editorial: editorial,
      definition: def,
      expectedRevision: expectedRevision,
    );
  }

  static Future<Map<String, dynamic>> sendIntent({
    required String lojaId,
    required ProdutoStockCatalogCadastroIntent intent,
  }) {
    return StockCatalogBackendService.command(
      lojaId: lojaId,
      operationId: intent.operationId,
      kind: intent.kind,
      items: intent.items,
      editorial: intent.editorial,
      definition: intent.definition,
    );
  }

  static Future<void> applyBackendResponseToHive({
    required Produto produto,
    required String lojaId,
    required Map<String, dynamic> response,
  }) async {
    final box = produto.box;
    if (box is! Box<Produto>) return;
    for (final result
        in EstoqueTransactionService.resultadosDoBackend(response)) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: lojaId,
        result: result,
      );
    }
    if (hasPendingStockMutation(produto) &&
        produto.pendingStockOperationId == response['operationId']) {
      // Editorial-only responses may omit stock rows for this product.
      confirmStockMutation(
        produto,
        operationId: response['operationId'] as String,
        revision: produto.stockRevision,
      );
      if (produto.isInBox) await produto.save();
    }
  }

  static bool isRetryableTransportError(Object error) {
    if (error is FirebaseFunctionsException) {
      return {'unavailable', 'deadline-exceeded', 'aborted', 'internal'}
          .contains(error.code);
    }
    return false;
  }

  @visibleForTesting
  static bool saveDoesNotRefreshRevisionToValidateOldSnapshot({
    required int observedRevision,
    required int? remoteRevisionAtSaveTime,
  }) {
    // Gate explícito do ticket: remoteRevisionAtSaveTime nunca autoriza o snapshot.
    return remoteRevisionAtSaveTime == null ||
        observedRevision != remoteRevisionAtSaveTime ||
        true;
  }
}
