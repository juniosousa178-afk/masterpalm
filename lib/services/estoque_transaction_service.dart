// lib/services/estoque_transaction_service.dart
//
// Serviço centralizado para baixa de estoque COM transação Firestore.
// Elimina race conditions: read → validate → decrement é atômico.
//
// Uso: chamar baixarEstoqueTransaction() ANTES de qualquer lógica de venda.
// Após sucesso, atualizar Hive local para consistência.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/dart_error_unwrap.dart';
import '../core/firestore_dynamic_map.dart';
import '../core/produto_variacao_extra.dart';
import '../core/strict_product_resolution.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';
import 'catalog_cache_service.dart';
import 'produto_exclusao_tombstone_service.dart';

/// Estado do marcador `lojas/{lojaId}/estoque_baixa_pagamento/{vendaId}`.
class EstoqueBaixaPagamentoMarcador {
  final bool existe;
  final bool baixaAplicada;
  final bool estornoAplicado;

  const EstoqueBaixaPagamentoMarcador({
    required this.existe,
    required this.baixaAplicada,
    required this.estornoAplicado,
  });

  static const ausente = EstoqueBaixaPagamentoMarcador(
    existe: false,
    baixaAplicada: false,
    estornoAplicado: false,
  );
}

/// Resultado da baixa de estoque via transação
class EstoqueTransactionResult {
  final String produtoId;
  final String produtoNome;
  final String? produtoSlug;
  final int quantidadeDebitada;
  final Map<String, dynamic>? variacoesAtualizadas;
  final Map<String, int>? estoquePorTamanhoAtualizado;
  final int quantidadeTotalAtualizada;

  /// Ajuste de teto combo feito só no Hive (SKU ausente na nuvem); ver [ComboKitStockService].
  final bool ajusteCapComboSomenteHive;

  /// Quantidade cadastrada antes do recálculo local (rollback pré-Hive).
  final int? quantidadeComboAntesAjusteLocal;

  EstoqueTransactionResult({
    required this.produtoId,
    required this.produtoNome,
    this.produtoSlug,
    required this.quantidadeDebitada,
    this.variacoesAtualizadas,
    this.estoquePorTamanhoAtualizado,
    required this.quantidadeTotalAtualizada,
    this.ajusteCapComboSomenteHive = false,
    this.quantidadeComboAntesAjusteLocal,
  });
}

/// Resultado da baixa idempotente por [operationId] (PDV manual).
enum EstoqueBaixaOperationStatus {
  applied,
  alreadyApplied,
}

class EstoqueBaixaOperationResult {
  const EstoqueBaixaOperationResult({
    required this.status,
    required this.transactionResults,
  });

  final EstoqueBaixaOperationStatus status;
  final List<EstoqueTransactionResult> transactionResults;

  bool get baixaAplicadaNestaExecucao =>
      status == EstoqueBaixaOperationStatus.applied;

  bool get baixaJaAplicadaAnteriormente =>
      status == EstoqueBaixaOperationStatus.alreadyApplied;
}

/// Mesmo [operationId] com efeito de estoque diferente — fail-closed.
class EstoqueBaixaOperationIdentityConflictException implements Exception {
  EstoqueBaixaOperationIdentityConflictException(this.message);

  final String message;

  @override
  String toString() => 'EstoqueBaixaOperationIdentityConflictException: $message';
}

class _PdvBaixaIdempotencyContext {
  const _PdvBaixaIdempotencyContext({
    required this.operationId,
    required this.txItemsHash,
    required this.snapshotHash,
  });

  final String operationId;
  final String txItemsHash;
  final String snapshotHash;
}

class _TransacaoBaixaBatchOutcome {
  const _TransacaoBaixaBatchOutcome({
    required this.alreadyApplied,
    required this.results,
  });

  final bool alreadyApplied;
  final List<EstoqueTransactionResult> results;
}

/// Estado acumulado de um documento na mesma TX batch (várias variações do mesmo produto).
class _DocStockWorkingState {
  _DocStockWorkingState({
    required this.produtoNome,
    required this.produtoSlug,
    required this.variacoesOriginais,
    required this.estoquePorTamanhoOriginal,
    required this.variacoes,
    required this.estoquePorTamanho,
    required this.quantidadeTotal,
  });

  final String produtoNome;
  final String produtoSlug;
  final Map<String, dynamic> variacoesOriginais;
  final Map<String, int> estoquePorTamanhoOriginal;
  Map<String, dynamic> variacoes;
  Map<String, int> estoquePorTamanho;
  int quantidadeTotal;
  bool touchedVariacoes = false;
  bool touchedEstoquePorTamanho = false;
}

/// Serviço de baixa de estoque atômica via Firestore Transaction
class EstoqueTransactionService {
  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  /// Atraso artificial dentro do callback da transação batch (somente testes).
  @visibleForTesting
  static Duration? debugBatchTransactionDelay;

  @visibleForTesting
  static void debugClearOverrides() {
    debugFirestoreOverride = null;
    debugBatchTransactionDelay = null;
  }

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  /// Idempotência de devolução **só no dispositivo** — evita coleção `estoque_devolucao` no Firestore
  /// (costuma dar permission-denied nas rules sem deploy dedicado).
  static String? _devolucaoLocalPrefsKeyOrNull(String lojaId, String vendaId) {
    final lid = lojaId.trim();
    final vid = vendaId.trim();
    if (lid.isEmpty || vid.isEmpty) return null;
    return 'estoque_devolvido_v1_${lid}_$vid';
  }

  static Future<bool> _devolucaoLocalJaFeita(String lojaId, String vendaId) async {
    final key = _devolucaoLocalPrefsKeyOrNull(lojaId, vendaId);
    if (key == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> _marcarDevolucaoLocalFeita(String lojaId, String vendaId) async {
    final key = _devolucaoLocalPrefsKeyOrNull(lojaId, vendaId);
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }

  /// Hive: atualiza [Produto.updatedAt] ao persistir saldo após transação em [atualizarHiveAposTransacao].
  /// Mesmo critério do +/- na lista e da devolução: evita pull com snapshot remoto velho se Hive e nuvem desalinharem.
  @visibleForTesting
  static void touchProdutoUpdatedAtParaHivePosTransacao(Produto p) {
    p.updatedAt = DateTime.now();
  }

  static Exception _erroProdutoNaoSincronizado({
    required String? produtoId,
    required String? slug,
    required String? nome,
  }) {
    final alvo = (produtoId != null && produtoId.trim().isNotEmpty)
        ? 'ID $produtoId'
        : ((slug != null && slug.trim().isNotEmpty)
            ? 'slug "$slug"'
            : 'nome "$nome"');
    return Exception(
      'Produto não encontrado no estoque da nuvem ($alvo). '
      'Abra o cadastro do produto e sincronize/publice novamente antes de finalizar a venda.',
    );
  }

  static String? _extrairDocIdProdutosNotFound(Object e, String lojaId) {
    final msg = formatDartErrorForUser(e);
    if (!msg.toLowerCase().contains('not-found') ||
        !msg.contains('/produtos/')) {
      return null;
    }
    final escapedLoja = RegExp.escape(lojaId);
    final m = RegExp('lojas\\/$escapedLoja\\/produtos\\/([^\\s,)]+)')
        .firstMatch(msg);
    final docId = m?.group(1)?.trim();
    return (docId == null || docId.isEmpty) ? null : docId;
  }

  static Future<bool> _repararEspelhoProdutosSeAusente({
    required String lojaId,
    required String docId,
  }) async {
    try {
      final base = _db.collection('lojas').doc(lojaId);
      final estoqueRef = base.collection(FSPaths.estoqueProdutosCol).doc(docId);
      final produtosRef = base.collection('produtos').doc(docId);
      final estoqueSnap = await estoqueRef.get();
      if (!estoqueSnap.exists) return false;
      final data = Map<String, dynamic>.from(estoqueSnap.data() ?? {});
      data['updatedAt'] = FieldValue.serverTimestamp();
      await produtosRef.set(data, SetOptions(merge: true));
      debugPrint('[ESTOQUE-TX] 🔧 Espelho produtos reparado: lojas/$lojaId/produtos/$docId');
      return true;
    } catch (e) {
      debugPrint('[ESTOQUE-TX] ⚠️ Falha ao reparar espelho produtos (type=${e.runtimeType})');
      return false;
    }
  }

  /// Baixa estoque de forma atômica usando transação Firestore.
  ///
  /// [lojaId] - ID da loja
  /// [produtoId] - ID do documento do produto (preferencial)
  /// [slug] - Slug do produto (alternativa se produtoId não informado)
  /// [nome] - Nome do produto (fallback se slug não encontrar)
  /// [tamanho] - Tamanho da variação (obrigatório se produto usa variações/tamanhos)
  /// [cor] - Cor da variação (obrigatório se produto usa variações)
  /// [quantidade] - Quantidade a debitar
  ///
  /// Lança [Exception] se estoque insuficiente ou produto não encontrado.
  /// Retorna [EstoqueTransactionResult] com dados atualizados para sincronizar Hive.
  static Future<EstoqueTransactionResult> baixarEstoqueTransaction({
    required String lojaId,
    required int quantidade,
    String? produtoId,
    String? slug,
    String? nome,
    String tamanho = '',
    String cor = '',
    String variacaoExtra = '',
  }) async {
    if (quantidade <= 0) {
      throw Exception('Quantidade deve ser maior que zero');
    }

    final tam = tamanho.trim();
    final corTrim = cor.trim();
    final extraTrim = variacaoExtra.trim();

    final produtoRef = await _resolverProdutoRef(lojaId: lojaId, produtoId: produtoId, slug: slug, nome: nome);
    if (produtoRef == null) {
      throw _erroProdutoNaoSincronizado(
        produtoId: produtoId,
        slug: slug,
        nome: nome,
      );
    }

    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
    if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
        lojaId: lojaId, estoqueDocId: produtoRef.id)) {
      throw Exception(
        'Produto removido do estoque. Atualize a lista de produtos e tente novamente.',
      );
    }
    if (await ProdutoExclusaoTombstoneService.isVendaBloqueadaParaCelula(
      lojaId: lojaId,
      estoqueDocId: produtoRef.id,
      tamanho: tam,
      cor: corTrim,
      variacaoExtra: extraTrim,
    )) {
      throw Exception(
        'Esta variação foi removida do cadastro. Sincronize o app e selecione o produto novamente.',
      );
    }

    Future<EstoqueTransactionResult> executarTransacao() {
      return _db.runTransaction<EstoqueTransactionResult>((transaction) async {
      final produtoSnap = await transaction.get(produtoRef);

      if (!produtoSnap.exists) {
        throw Exception(
          'Produto não encontrado no servidor: ${produtoId ?? slug ?? nome}. '
          'Verifique se o produto foi sincronizado ou sua conexão com a internet.',
        );
      }

      final data = produtoSnap.data()!;
      final docId = produtoSnap.reference.id;
      final produtoNome = (data['nome'] ?? '').toString();

      final variacoesRaw = data['variacoes'];
      final estoquePorTamanhoRaw = data['estoquePorTamanho'];
      final quantidadeTotal = (data['quantidade'] as num?)?.toInt() ?? 0;

      final variacoes = firestoreStringDynamicMapDeepOrEmpty(variacoesRaw);
      final estoquePorTamanho = _parseMapStringInt(estoquePorTamanhoRaw);

        final usaVariacoes = variacoes.isNotEmpty;
        final temEstoquePorTamanho = estoquePorTamanho.isNotEmpty;
        final temVariacaoSoloCor = usaVariacoes && variacoes.containsKey('sem-tamanho') &&
            variacoes['sem-tamanho'] is Map && (variacoes['sem-tamanho'] as Map).isNotEmpty;
        final temVariacaoTamanhoECor = usaVariacoes && _temVariacaoTamanhoECor(variacoes);

        if (usaVariacoes && !temVariacaoSoloCor && tam.isEmpty && corTrim.isEmpty) {
          throw Exception(
            'O produto "$produtoNome" possui variações. Informe tamanho e/ou cor conforme o cadastro.',
          );
        }
        if (temVariacaoSoloCor && corTrim.isEmpty) {
          throw Exception(
            'O produto "$produtoNome" possui variação de cor. É obrigatório informar a COR.',
          );
        }
        if (temVariacaoTamanhoECor && (tam.isEmpty || corTrim.isEmpty)) {
          throw Exception(
            'O produto "$produtoNome" possui variações de tamanho e cor. '
            'É obrigatório informar TAMANHO e COR.',
          );
        }
        if (usaVariacoes && !temVariacaoSoloCor && tam.isEmpty && corTrim != 'sem-cor') {
          final temSoloTamanho = _temVariacaoSoloTamanho(variacoes);
          if (temSoloTamanho) {
            throw Exception(
              'O produto "$produtoNome" possui variação de tamanho. É obrigatório informar o TAMANHO.',
            );
          }
        }
        if (_temEstoquePorTamanhoReal(estoquePorTamanho) &&
            tam.isEmpty &&
            !temVariacaoSoloCor) {
          throw Exception(
            'O produto "$produtoNome" possui estoque por tamanho. '
            'É obrigatório informar o TAMANHO na venda (ex.: P, M, G).',
          );
        }

        int disponivel = 0;
        Map<String, dynamic>? novasVariacoes;
      Map<String, int>? novoEstoquePorTamanho;
      int novaQuantidadeTotal;

      if (temVariacaoSoloCor && corTrim.isNotEmpty) {
        novasVariacoes = _mapaAposDebitoVariacao(
          variacoes: variacoes,
          chaveTamanho: 'sem-tamanho',
          corKey: corTrim,
          extraTrim: extraTrim,
          quantidade: quantidade,
          produtoNome: produtoNome,
          erroCtx: 'na cor $corTrim',
        );
        novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
      } else if (usaVariacoes && tam.isNotEmpty) {
        final tamResolvidoVar = _resolverChaveNoMapa(variacoes, tam);
        final mapaTamVar = tamResolvidoVar != null
            ? variacoes[tamResolvidoVar]
            : null;
        final celulaVarExiste = mapaTamVar is Map && mapaTamVar.isNotEmpty;

        if (!celulaVarExiste && temEstoquePorTamanho) {
          final tamResolvido =
              _resolverChaveNoMapa(estoquePorTamanho, tam) ?? tam;
          disponivel = estoquePorTamanho[tamResolvido] ?? 0;

          if (disponivel < quantidade) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome" no tamanho $tam. '
              'Disponível: $disponivel, solicitado: $quantidade.',
            );
          }

          novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
          novoEstoquePorTamanho[tamResolvido] = disponivel - quantidade;
          if (novoEstoquePorTamanho[tamResolvido]! <= 0) {
            novoEstoquePorTamanho.remove(tamResolvido);
          }

          novaQuantidadeTotal =
              novoEstoquePorTamanho.values.fold(0, (a, b) => a + b);
        } else {
          final chaveCor = _resolverCorKeyParaTamanho(
            variacoes: variacoes,
            tamanho: tam,
            corInformada: corTrim,
          );
          novasVariacoes = _mapaAposDebitoVariacao(
            variacoes: variacoes,
            chaveTamanho: tam,
            corKey: chaveCor,
            extraTrim: extraTrim,
            quantidade: quantidade,
            produtoNome: produtoNome,
            erroCtx:
                'no tamanho $tam${corTrim.isEmpty ? '' : ' - cor $corTrim'}',
          );
          novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
        }
      } else if (temEstoquePorTamanho && tam.isNotEmpty) {
        final tamResolvido =
            _resolverChaveNoMapa(estoquePorTamanho, tam) ?? tam;
        disponivel = estoquePorTamanho[tamResolvido] ?? 0;

        if (disponivel < quantidade) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome" no tamanho $tam. '
            'Disponível: $disponivel, solicitado: $quantidade.',
          );
        }

        novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
        novoEstoquePorTamanho[tamResolvido] = disponivel - quantidade;
        if (novoEstoquePorTamanho[tamResolvido]! <= 0) {
          novoEstoquePorTamanho.remove(tamResolvido);
        }

        novaQuantidadeTotal =
            novoEstoquePorTamanho.values.fold(0, (a, b) => a + b);
      } else {
        disponivel = quantidadeTotal;

        if (disponivel < quantidade) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome". '
            'Disponível: $disponivel, solicitado: $quantidade.',
          );
        }

        novaQuantidadeTotal = quantidadeTotal - quantidade;
      }

      Map<String, int>? estoquePorTamanhoParaVariacao;
      if (novasVariacoes != null) {
        estoquePorTamanhoParaVariacao =
            _estoquePorTamanhoAgregadoDeVariacoes(novasVariacoes);
      }

      final updateData = buildEstoqueUpdateDataComDeletes(
        novaQuantidadeTotal: novaQuantidadeTotal,
        variacoesAnteriores: variacoes,
        variacoesNovas: novasVariacoes,
        estoquePorTamanhoAnterior: estoquePorTamanho,
        estoquePorTamanhoNovo:
            estoquePorTamanhoParaVariacao ?? novoEstoquePorTamanho,
      );

      transaction.update(produtoRef, updateData);

      final estoqueRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId);

      // Em transações, update em doc inexistente pode falhar apenas no commit.
      // Usar set+merge evita abortar a venda quando coleção espelho não existe.
      transaction.set(estoqueRef, updateData, SetOptions(merge: true));

      debugPrint('[ESTOQUE-TX] ✅ Baixa atômica: $produtoNome -$quantidade');

      final slugVal = (data['slug'] ?? '').toString().trim();
      return EstoqueTransactionResult(
        produtoId: docId,
        produtoNome: produtoNome,
        produtoSlug: slugVal.isNotEmpty ? slugVal : null,
        quantidadeDebitada: quantidade,
        variacoesAtualizadas: novasVariacoes,
        estoquePorTamanhoAtualizado:
            estoquePorTamanhoParaVariacao ?? novoEstoquePorTamanho,
        quantidadeTotalAtualizada: novaQuantidadeTotal,
      );
      }).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Conexão demorou muito. Verifique sua internet e tente novamente.',
        ),
      );
    }

    try {
      return await executarTransacao();
    } catch (e) {
      final docId = _extrairDocIdProdutosNotFound(e, lojaId);
      if (docId == null) rethrow;
      final reparado = await _repararEspelhoProdutosSeAusente(
        lojaId: lojaId,
        docId: docId,
      );
      if (!reparado) {
        throw Exception(
          'Produto sem documento válido de estoque na nuvem (ID: $docId). '
          'Sincronize o produto no cadastro e tente finalizar novamente.',
        );
      }
      debugPrint('[ESTOQUE-TX] 🔁 Retry transação após reparar produtos/$docId');
      return executarTransacao();
    }
  }

  static Map<String, int> _parseMapStringInt(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, int>) return data;
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(
          key.toString(),
          ProdutoVariacaoExtra.valorFirestoreComoInt(value),
        ),
      );
    }
    return {};
  }

  /// Firestore faz merge em mapas aninhados — chaves omitidas permanecem.
  /// Após baixa/devolução, remove explicitamente tamanhos/cores zerados.
  @visibleForTesting
  static Map<String, dynamic> buildEstoqueUpdateDataComDeletes({
    required int novaQuantidadeTotal,
    Map<String, dynamic>? variacoesAnteriores,
    Map<String, dynamic>? variacoesNovas,
    Map<String, int>? estoquePorTamanhoAnterior,
    Map<String, int>? estoquePorTamanhoNovo,
  }) {
    final updateData = <String, dynamic>{
      'quantidade': novaQuantidadeTotal,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (variacoesNovas != null) {
      final sanitized = ProdutoVariacaoExtra.sanitizeVariacoesMapForFirestore(
        firestoreStringDynamicMapDeepOrEmpty(variacoesNovas),
      );
      updateData['variacoes'] = sanitized;
      _adicionarDeletesMapaVariacoes(
        updateData,
        variacoesAnteriores ?? const {},
        sanitized,
      );
    }

    if (estoquePorTamanhoNovo != null) {
      updateData['estoquePorTamanho'] = estoquePorTamanhoNovo;
      _adicionarDeletesEstoquePorTamanho(
        updateData,
        estoquePorTamanhoAnterior ?? const {},
        estoquePorTamanhoNovo,
      );
    }

    return updateData;
  }

  /// Dot-notation quebra com chaves que contêm `.` (ex.: tamanho `45.5cm`).
  /// Nesses casos confia no mapa completo já enviado em [variacoes]/[estoquePorTamanho].
  static void _putFieldDelete(
    Map<String, dynamic> updateData,
    List<String> pathSegments,
  ) {
    if (pathSegments.isEmpty) return;
    if (pathSegments.any((s) => s.contains('.'))) {
      if (kDebugMode) {
        debugPrint(
          '[ESTOQUE_TX_DELETE_KEYS] skip delete granular (chave com ponto): '
          '${pathSegments.join("/")}',
        );
      }
      return;
    }
    updateData[pathSegments.join('.')] = FieldValue.delete();
  }

  static void _adicionarDeletesMapaVariacoes(
    Map<String, dynamic> updateData,
    Map<String, dynamic> anterior,
    Map<String, dynamic> novo,
  ) {
    for (final tam in anterior.keys) {
      final tamStr = tam.toString();
      if (!_mapaContemChaveCompativel(novo, tamStr)) {
        _putFieldDelete(updateData, ['variacoes', tamStr]);
        continue;
      }
      final tamNovo = _resolverChaveNoMapa(novo, tamStr) ?? tamStr;
      final am = anterior[tam];
      final nm = novo[tamNovo];
      if (am is! Map || nm is! Map) continue;
      for (final cor in am.keys) {
        final corStr = cor.toString();
        if (!_mapaContemChaveCompativel(nm, corStr)) {
          _putFieldDelete(updateData, ['variacoes', tamStr, corStr]);
        }
      }
    }
  }

  static void _adicionarDeletesEstoquePorTamanho(
    Map<String, dynamic> updateData,
    Map<String, int> anterior,
    Map<String, int> novo,
  ) {
    for (final k in anterior.keys) {
      final ks = k.toString();
      if (!_mapaContemChaveCompativel(novo, ks)) {
        _putFieldDelete(updateData, ['estoquePorTamanho', ks]);
      }
    }
  }

  /// Resolve chave de grade com tolerância (espaços/caixa), alinhado ao catálogo.
  @visibleForTesting
  static String? resolverChaveNoMapaParaTeste(
    Map<dynamic, dynamic> map,
    String informada,
  ) {
    final alvo = informada.trim();
    if (alvo.isEmpty) return null;
    if (map.containsKey(alvo)) return alvo;
    for (final k in map.keys) {
      final ks = k.toString();
      if (ProdutoVariacaoExtra.keysMatch(ks, alvo)) return ks;
    }
    return null;
  }

  static String? _resolverChaveNoMapa(Map<dynamic, dynamic> map, String informada) =>
      resolverChaveNoMapaParaTeste(map, informada);

  static bool _mapaContemChaveCompativel(Map<dynamic, dynamic> map, String informada) {
    return _resolverChaveNoMapa(map, informada) != null;
  }

  /// Resolve produtoId/slug/nome para DocumentReference (Transaction.get não aceita Query).
  /// Ordem: 1) productId, 2) slug, 3) nome. Loga [PRODUTO_ID] ou [PRODUTO_FALLBACK].
  static Future<DocumentReference<Map<String, dynamic>>?> _resolverProdutoRef({
    required String lojaId,
    String? produtoId,
    String? slug,
    String? nome,
  }) async {
    final col = _db.collection('lojas').doc(lojaId).collection(FSPaths.estoqueProdutosCol);

    // 1) productId / idFirebase
    if (produtoId != null && produtoId.isNotEmpty) {
      final ref = col.doc(produtoId);
      final snap = await ref.get();
      if (snap.exists) {
        debugPrint('[PRODUTO_ID] Resolução por productId | lojaId=$lojaId | productId=$produtoId');
        return ref;
      }
      debugPrint(
        '[PRODUTO_FALLBACK] Doc productId não existe no Firestore, tentando slug/nome | lojaId=$lojaId | productId=$produtoId',
      );
    }

    // 2) slug
    if (slug != null && slug.isNotEmpty) {
      final querySnap = await col.where('slug', isEqualTo: slug).limit(1).get();
      if (querySnap.docs.isNotEmpty) {
        final ref = querySnap.docs.first.reference;
        debugPrint(
          '[PRODUTO_FALLBACK] Resolução por slug | lojaId=$lojaId | slug=$slug | docId=${ref.id}',
        );
        return ref;
      }
    }

    // 3) nome
    if (nome != null && nome.isNotEmpty) {
      final nomeSnap = await col.where('nome', isEqualTo: nome).limit(2).get();
      if (nomeSnap.docs.length > 1) {
        debugPrint(
          '[PRODUTO_FALLBACK] Nome ambíguo | lojaId=$lojaId | nome="$nome" | matches=${nomeSnap.docs.length}',
        );
        reportProductResolvedByName(
          lojaId: lojaId,
          fluxo: '_resolverProdutoRef_ambiguo',
          nome: nome,
          slug: slug,
          productIdRecebido: produtoId,
        );
        throw Exception(
          'Mais de um produto com o nome "$nome" foi encontrado. '
          'Configure um identificador único (idFirebase ou slug) para permitir a baixa correta do estoque.',
        );
      }
      if (nomeSnap.docs.length == 1) {
        final ref = nomeSnap.docs.first.reference;
        debugPrint(
          '[PRODUTO_FALLBACK] Resolução por nome | lojaId=$lojaId | nome="$nome" | docId=${ref.id}',
        );
        reportProductResolvedByName(
          lojaId: lojaId,
          fluxo: '_resolverProdutoRef',
          nome: nome,
          slug: slug,
          productIdRecebido: produtoId,
        );
        return ref;
      }
    }

    return null;
  }

  static bool _temEstoquePorTamanhoReal(Map<String, int> map) {
    for (final e in map.entries) {
      if (Produto.ehChaveTamanhoTecnicoLegado(e.key)) continue;
      if (e.value > 0) return true;
    }
    return false;
  }

  static bool _temVariacaoSoloTamanho(Map<String, dynamic> variacoes) {
    for (final e in variacoes.entries) {
      if (Produto.ehChaveTamanhoTecnicoLegado(e.key.toString())) continue;
      if (e.value is Map && (e.value as Map).isNotEmpty) return true;
    }
    return false;
  }

  static bool _temVariacaoTamanhoECor(Map<String, dynamic> variacoes) {
    for (final e in variacoes.entries) {
      if (e.key == 'sem-tamanho') continue;
      final mapa = e.value;
      if (mapa is! Map) continue;
      for (final k in mapa.keys) {
        if (k != null && k.toString() != 'sem-cor') return true;
      }
    }
    return false;
  }

  /// Evita criar `sem-cor` quando o tamanho possui uma única cor real.
  static String _resolverCorKeyParaTamanho({
    required Map<String, dynamic> variacoes,
    required String tamanho,
    required String corInformada,
  }) {
    final cor = corInformada.trim();
    final tamResolvido = _resolverChaveNoMapa(variacoes, tamanho) ?? tamanho;
    final mapaCor = variacoes[tamResolvido];
    if (mapaCor is! Map) return cor.isNotEmpty ? cor : 'sem-cor';

    if (cor.isNotEmpty) {
      return _resolverChaveNoMapa(mapaCor, cor) ?? cor;
    }

    final coresValidas = mapaCor.keys
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && e != 'sem-cor')
        .toSet()
        .toList();

    if (coresValidas.length == 1) return coresValidas.first;
    return 'sem-cor';
  }

  static Map<String, dynamic> _mapaAposDebitoVariacao({
    required Map<String, dynamic> variacoes,
    required String chaveTamanho,
    required String corKey,
    required String extraTrim,
    required int quantidade,
    required String produtoNome,
    required String erroCtx,
  }) {
    final tamResolvido =
        _resolverChaveNoMapa(variacoes, chaveTamanho) ?? chaveTamanho;
    final mapaCor = variacoes[tamResolvido];
    if (mapaCor == null || mapaCor is! Map) {
      throw Exception(
        'Estoque insuficiente para "$produtoNome" $erroCtx. Disponível: 0, solicitado: $quantidade.',
      );
    }
    final mapa = firestoreStringDynamicMapDeepOrEmpty(mapaCor);
    final corResolvida = _resolverChaveNoMapa(mapa, corKey) ?? corKey;
    final cell = mapa[corResolvida];
    if (ProdutoVariacaoExtra.celulaTemExtrasNaoVazios(cell) &&
        extraTrim.isEmpty) {
      throw Exception(
        'O produto "$produtoNome" possui estoque por personalização (opções extras). '
        'Informe a opção selecionada na venda.',
      );
    }
    final r = ProdutoVariacaoExtra.debitarCelula(cell, extraTrim, quantidade);
    if (!r.ok) {
      final disp = ProdutoVariacaoExtra.quantidadeNaCelula(cell, extraTrim);
      throw Exception(
        'Estoque insuficiente para "$produtoNome" $erroCtx. '
        'Disponível: $disp, solicitado: $quantidade.',
      );
    }
    if (r.newCell == ProdutoVariacaoExtra.removeCorCell) {
      mapa.remove(corResolvida);
    } else {
      mapa[corResolvida] = r.newCell;
    }
    final novasVariacoes = firestoreStringDynamicMapDeepOrEmpty(variacoes);
    if (mapa.isEmpty) {
      novasVariacoes.remove(tamResolvido);
    } else {
      novasVariacoes[tamResolvido] = mapa;
    }
    return novasVariacoes;
  }

  static Map<String, dynamic> _mapaAposDevolverVariacao({
    required Map<String, dynamic> variacoes,
    required String chaveTamanho,
    required String corKey,
    required String extraTrim,
    required int quantidade,
  }) {
    final mapaCor = variacoes[chaveTamanho];
    final mapa = mapaCor != null && mapaCor is Map
        ? firestoreStringDynamicMapDeepOrEmpty(mapaCor)
        : <String, dynamic>{};
    final cell = mapa[corKey];
    mapa[corKey] =
        ProdutoVariacaoExtra.devolverCelula(cell, extraTrim, quantidade);
    final novasVariacoes = firestoreStringDynamicMapDeepOrEmpty(variacoes);
    novasVariacoes[chaveTamanho] = mapa;
    return novasVariacoes;
  }

  static int _somarVariacoes(Map<String, dynamic> variacoes) {
    int total = 0;
    for (final mapaTamanho in variacoes.values) {
      if (mapaTamanho is Map) {
        for (final qtd in mapaTamanho.values) {
          total += ProdutoVariacaoExtra.somarCelula(qtd);
        }
      }
    }
    return total;
  }

  /// Soma todas as células (cor/extras) por chave de tamanho — espelha o cadastro e alinha [quantidade].
  static Map<String, int> _estoquePorTamanhoAgregadoDeVariacoes(
    Map<String, dynamic> variacoes,
  ) {
    final out = <String, int>{};
    for (final e in variacoes.entries) {
      final mapaTamanho = e.value;
      if (mapaTamanho is! Map) continue;
      var total = 0;
      for (final v in mapaTamanho.values) {
        total += ProdutoVariacaoExtra.somarCelula(v);
      }
      if (total > 0) {
        out[e.key.toString()] = total;
      }
    }
    return out;
  }

  /// Limite do Firestore: 500 operações por transação (~2 ops/item = 250 itens seguros)
  static const int _maxItensPorTransacao = 150;

  /// Mescla linhas que debitam o mesmo documento + mesma variação (evita leitura/escrita duplicada na mesma TX).
  static Future<List<({
    DocumentReference<Map<String, dynamic>> ref,
    int quantidade,
    String tamanho,
    String cor,
    String variacaoExtra,
  })>> _resolverItensMescladosBaixa(
    String lojaId,
    List<Map<String, dynamic>> itens,
  ) async {
    final acc = <String, int>{};
    final meta = <String, ({
      DocumentReference<Map<String, dynamic>> ref,
      String tamanho,
      String cor,
      String variacaoExtra,
    })>{};

    for (final item in itens) {
      final quantidade = (item['quantidade'] as num?)?.toInt() ??
          (item['qty'] as num?)?.toInt() ??
          1;
      final produtoId = item['productId']?.toString() ??
          item['produtosId']?.toString() ??
          item['id']?.toString();
      final slug = item['slug']?.toString();
      final nome = (item['nome'] ?? item['name'] ?? '').toString();
      final tamanho = (item['tamanho'] ?? item['size'] ?? '').toString().trim();
      final cor = (item['cor'] ?? item['color'] ?? '').toString().trim();
      final variacaoExtra =
          (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim();

      if (quantidade <= 0) continue;

      final ref = await _resolverProdutoRef(
        lojaId: lojaId,
        produtoId: produtoId,
        slug: slug,
        nome: nome,
      );
      if (ref == null) {
        throw _erroProdutoNaoSincronizado(
          produtoId: produtoId,
          slug: slug,
          nome: nome,
        );
      }
      final key = [ref.path, tamanho, cor, variacaoExtra].join('|');
      acc[key] = (acc[key] ?? 0) + quantidade;
      meta.putIfAbsent(
        key,
        () => (
          ref: ref,
          tamanho: tamanho,
          cor: cor,
          variacaoExtra: variacaoExtra,
        ),
      );
    }

    return acc.entries.map((e) {
      final m = meta[e.key]!;
      return (
        ref: m.ref,
        quantidade: e.value,
        tamanho: m.tamanho,
        cor: m.cor,
        variacaoExtra: m.variacaoExtra,
      );
    }).toList();
  }

  static Future<List<({
    DocumentReference<Map<String, dynamic>> ref,
    int quantidade,
    String tamanho,
    String cor,
    String variacaoExtra,
  })>> _resolverItensMescladosDevolucao(
    String lojaId,
    List<Map<String, dynamic>> itens,
  ) async {
    final acc = <String, int>{};
    final meta = <String, ({
      DocumentReference<Map<String, dynamic>> ref,
      String tamanho,
      String cor,
      String variacaoExtra,
    })>{};

    for (final item in itens) {
      final quantidade = (item['quantidade'] as num?)?.toInt() ??
          (item['qty'] as num?)?.toInt() ??
          1;
      final produtoId = item['productId']?.toString() ??
          item['produtosId']?.toString() ??
          item['id']?.toString();
      final slug = item['slug']?.toString();
      final nome = (item['nome'] ?? item['name'] ?? '').toString();
      final tamanho = (item['tamanho'] ?? item['size'] ?? '').toString().trim();
      final cor = (item['cor'] ?? item['color'] ?? '').toString().trim();
      final variacaoExtra =
          (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim();

      if (quantidade <= 0) continue;

      final ref = await _resolverProdutoRef(
        lojaId: lojaId,
        produtoId: produtoId,
        slug: slug,
        nome: nome,
      );
      if (ref == null) {
        debugPrint(
          '[ESTOQUE-TX] Produto não encontrado para devolução: ${produtoId ?? slug ?? nome}',
        );
        continue;
      }
      final key = [ref.path, tamanho, cor, variacaoExtra].join('|');
      acc[key] = (acc[key] ?? 0) + quantidade;
      meta.putIfAbsent(
        key,
        () => (
          ref: ref,
          tamanho: tamanho,
          cor: cor,
          variacaoExtra: variacaoExtra,
        ),
      );
    }

    return acc.entries.map((e) {
      final m = meta[e.key]!;
      return (
        ref: m.ref,
        quantidade: e.value,
        tamanho: m.tamanho,
        cor: m.cor,
        variacaoExtra: m.variacaoExtra,
      );
    }).toList();
  }

  static String _sha256HexUtf8(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Chave canônica de identidade de estoque (produto + variação).
  /// Nunca usar só [produtoId] quando houver tamanho/cor/extra.
  static String stockItemKey({
    required String lojaId,
    required String produtoId,
    String tamanho = '',
    String cor = '',
    String variacaoExtra = '',
  }) {
    return [
      lojaId.trim(),
      produtoId.trim(),
      tamanho.trim(),
      cor.trim(),
      variacaoExtra.trim(),
    ].join('|');
  }

  static void _traceEstoqueVariacao({
    required String stage,
    required String lojaId,
    required String produtoId,
    required String tamanho,
    required String cor,
    required String variacaoExtra,
    required int qtdVendida,
    required int qtdAntes,
    required int qtdDepois,
    String? operationId,
    bool? alreadyApplied,
  }) {
    final key = stockItemKey(
      lojaId: lojaId,
      produtoId: produtoId,
      tamanho: tamanho,
      cor: cor,
      variacaoExtra: variacaoExtra,
    );
    debugPrint(
      '[M39-ESTOQUE-VARIACAO] stage=$stage '
      'lojaId=$lojaId produtoId=$produtoId '
      'variacaoId=${[
        if (tamanho.trim().isNotEmpty) tamanho.trim(),
        if (cor.trim().isNotEmpty) cor.trim(),
        if (variacaoExtra.trim().isNotEmpty) variacaoExtra.trim(),
      ].join('/')} '
      'sku= stockItemKey=$key '
      'qtdVendida=$qtdVendida qtdAntes=$qtdAntes qtdDepois=$qtdDepois '
      'operationId=${operationId ?? ''} '
      'alreadyApplied=${alreadyApplied ?? false}',
    );
  }

  /// Hash determinístico do efeito de estoque solicitado (entrada txItems).
  static String computeTxItemsHashForIdempotencia(
    List<Map<String, dynamic>> itens,
  ) {
    final lines = <Map<String, dynamic>>[];
    for (final item in itens) {
      final quantidade = (item['quantidade'] as num?)?.toInt() ??
          (item['qty'] as num?)?.toInt() ??
          0;
      if (quantidade <= 0) continue;
      lines.add({
        'productId': (item['productId'] ??
                item['produtosId'] ??
                item['id'] ??
                '')
            .toString()
            .trim(),
        'slug': (item['slug'] ?? '').toString().trim(),
        'quantidade': quantidade,
        'tamanho': (item['tamanho'] ?? item['size'] ?? '').toString().trim(),
        'cor': (item['cor'] ?? item['color'] ?? '').toString().trim(),
        'extraValor': (item['extraValor'] ?? item['variacaoExtra'] ?? '')
            .toString()
            .trim(),
      });
    }
    lines.sort((a, b) {
      for (final key in [
        'productId',
        'slug',
        'tamanho',
        'cor',
        'extraValor',
        'quantidade',
      ]) {
        final cmp = a[key].toString().compareTo(b[key].toString());
        if (cmp != 0) return cmp;
      }
      return 0;
    });
    return _sha256HexUtf8(jsonEncode(lines));
  }

  /// Hash do efeito resolvido (documentos Firestore + variação).
  @visibleForTesting
  static String computeSnapshotHashFromResolvedBaixa(
    List<({
      DocumentReference<Map<String, dynamic>> ref,
      int quantidade,
      String tamanho,
      String cor,
      String variacaoExtra,
    })> resolvedItems,
  ) {
    final lines = resolvedItems
        .map(
          (r) => {
            'docId': r.ref.id,
            'quantidade': r.quantidade,
            'tamanho': r.tamanho,
            'cor': r.cor,
            'variacaoExtra': r.variacaoExtra,
          },
        )
        .toList()
      ..sort((a, b) {
        for (final key in [
          'docId',
          'tamanho',
          'cor',
          'variacaoExtra',
          'quantidade',
        ]) {
          final cmp = a[key].toString().compareTo(b[key].toString());
          if (cmp != 0) return cmp;
        }
        return 0;
      });
    return _sha256HexUtf8(jsonEncode(lines));
  }

  static Map<String, dynamic> buildMarkerBaixaPdvPayload({
    required String lojaId,
    required String operationId,
    required String snapshotHash,
    required String txItemsHash,
  }) {
    return <String, dynamic>{
      'protocolVersion': 1,
      'origem': 'pdv',
      'operationId': operationId,
      'saleId': operationId,
      'lojaId': lojaId,
      'baixaAplicada': true,
      'snapshotHash': snapshotHash,
      'txItemsHash': txItemsHash,
    };
  }

  static void _assertMarkerIdentityCompativel({
    required Map<String, dynamic> data,
    required String lojaId,
    required String operationId,
    required String txItemsHash,
    required String snapshotHash,
  }) {
    final op = (data['operationId'] ?? '').toString().trim();
    final sale = (data['saleId'] ?? '').toString().trim();
    final loja = (data['lojaId'] ?? '').toString().trim();
    if (op != operationId || sale != operationId || loja != lojaId) {
      throw EstoqueBaixaOperationIdentityConflictException(
        'Marcador incompatível com operationId=$operationId.',
      );
    }
    final storedTx = (data['txItemsHash'] ?? '').toString().trim();
    final storedSnap = (data['snapshotHash'] ?? '').toString().trim();
    if (storedTx != txItemsHash || storedSnap != snapshotHash) {
      throw EstoqueBaixaOperationIdentityConflictException(
        'operationId=$operationId já aplicado com efeito de estoque diferente.',
      );
    }
  }

  static void _txStageLog(
    String stage, {
    int? index,
    String? productId,
    String? branch,
    String? operationId,
    String? runtimeType,
  }) {
    final op = operationId != null && operationId.length > 8
        ? '${operationId.substring(0, 8)}…'
        : operationId;
    debugPrint(
      '[H1-TX-STAGE] stage=$stage'
      '${index != null ? ' index=$index' : ''}'
      '${productId != null ? ' productId=$productId' : ''}'
      '${branch != null ? ' branch=$branch' : ''}'
      '${op != null ? ' operationId=$op' : ''}'
      '${runtimeType != null ? ' runtimeType=$runtimeType' : ''}',
    );
  }

  static Future<void> _validarTombstonesBaixa({
    required String lojaId,
    required List<({
      DocumentReference<Map<String, dynamic>> ref,
      int quantidade,
      String tamanho,
      String cor,
      String variacaoExtra,
    })> resolvedItems,
  }) async {
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
    for (final r in resolvedItems) {
      if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
          lojaId: lojaId, estoqueDocId: r.ref.id)) {
        throw Exception(
          'Produto removido do estoque. Atualize a lista e tente novamente (id=${r.ref.id}).',
        );
      }
      if (await ProdutoExclusaoTombstoneService.isVendaBloqueadaParaCelula(
        lojaId: lojaId,
        estoqueDocId: r.ref.id,
        tamanho: r.tamanho,
        cor: r.cor,
        variacaoExtra: r.variacaoExtra,
      )) {
        throw Exception(
          'Uma variação desta venda foi removida do cadastro. Sincronize o app.',
        );
      }
    }
  }

  /// Baixa estoque de múltiplos itens em uma única transação (evita rollback parcial)
  static Future<List<EstoqueTransactionResult>> baixarEstoqueTransactionBatch({
    required String lojaId,
    required List<Map<String, dynamic>> itens,
  }) async {
    if (itens.length > _maxItensPorTransacao) {
      throw Exception(
        'Venda com muitos itens (${itens.length}). '
        'Divida em vendas menores (máx. $_maxItensPorTransacao itens por venda).',
      );
    }

    final resolvedItems = await _resolverItensMescladosBaixa(lojaId, itens);

    if (resolvedItems.isEmpty) {
      throw Exception(
        'Nenhum item válido para baixa de estoque (quantidade ou produto inválido).',
      );
    }

    await _validarTombstonesBaixa(lojaId: lojaId, resolvedItems: resolvedItems);

    final outcome = await _executarBaixaBatchInterno(
      lojaId: lojaId,
      resolvedItems: resolvedItems,
    );
    return outcome.results;
  }

  static Future<_TransacaoBaixaBatchOutcome> _executarBaixaBatchInterno({
    required String lojaId,
    required List<({
      DocumentReference<Map<String, dynamic>> ref,
      int quantidade,
      String tamanho,
      String cor,
      String variacaoExtra,
    })> resolvedItems,
    _PdvBaixaIdempotencyContext? idempotency,
  }) async {
    Future<_TransacaoBaixaBatchOutcome> executarTransacao([
      _PdvBaixaIdempotencyContext? idempotency,
    ]) {
      Future<_TransacaoBaixaBatchOutcome> run() {
        return _db.runTransaction<_TransacaoBaixaBatchOutcome>((transaction) async {
      if (idempotency != null) {
        final markerRef =
            _baixaPagamentoRef(lojaId, idempotency.operationId);
        _txStageLog(
          'tx_stage_01_marker_before_get',
          operationId: idempotency.operationId,
        );
        final markerSnap = await transaction.get(markerRef);
        _txStageLog(
          'tx_stage_02_marker_after_get',
          operationId: idempotency.operationId,
          runtimeType: markerSnap.data()?.runtimeType.toString(),
        );
        if (markerSnap.exists) {
          final markerData =
              firestoreStringDynamicMapOrEmpty(markerSnap.data());
          if (markerData['baixaAplicada'] == true) {
            if (markerData['estornoAplicado'] == true) {
              _assertMarkerIdentityCompativel(
                data: markerData,
                lojaId: lojaId,
                operationId: idempotency.operationId,
                txItemsHash: idempotency.txItemsHash,
                snapshotHash: idempotency.snapshotHash,
              );
              debugPrint(
                '[ESTOQUE-TX] Re-baixa pós-estorno operationId=${idempotency.operationId}',
              );
            } else {
              _assertMarkerIdentityCompativel(
                data: markerData,
                lojaId: lojaId,
                operationId: idempotency.operationId,
                txItemsHash: idempotency.txItemsHash,
                snapshotHash: idempotency.snapshotHash,
              );
              debugPrint(
                '[ESTOQUE-TX] Baixa idempotente replay operationId=${idempotency.operationId}',
              );
              return const _TransacaoBaixaBatchOutcome(
                alreadyApplied: true,
                results: [],
              );
            }
          }
        }
      }

      // FASE 1: Leituras + débito acumulado em memória por documento.
      // Várias variações do mesmo produto (P/M/G) NÃO podem cada uma
      // gerar um update completo a partir do snapshot original — a última
      // escrita sobrescreveria as anteriores. Acumulamos no working state.
      final results = <EstoqueTransactionResult>[];
      final writesByPath = <String, ({
        DocumentReference<Map<String, dynamic>> ref,
        DocumentReference<Map<String, dynamic>>? estoqueRef,
        Map<String, dynamic> updateData,
      })>{};
      final workingByPath = <String, _DocStockWorkingState>{};

      for (var itemIndex = 0; itemIndex < resolvedItems.length; itemIndex++) {
        final resolved = resolvedItems[itemIndex];
        try {
          _txStageLog(
            'tx_stage_03_item_begin',
            index: itemIndex,
            productId: resolved.ref.id,
            operationId: idempotency?.operationId,
          );
          final path = resolved.ref.path;
          late final _DocStockWorkingState working;

          if (workingByPath.containsKey(path)) {
            working = workingByPath[path]!;
            _txStageLog(
              'tx_stage_05_product_after_get',
              index: itemIndex,
              productId: resolved.ref.id,
              runtimeType: 'working_state_reuse',
            );
          } else {
            _txStageLog(
              'tx_stage_04_product_before_get',
              index: itemIndex,
              productId: resolved.ref.id,
            );
            final produtoSnap = await transaction.get(resolved.ref);
            _txStageLog(
              'tx_stage_05_product_after_get',
              index: itemIndex,
              productId: resolved.ref.id,
              runtimeType: produtoSnap.data()?.runtimeType.toString(),
            );

            if (!produtoSnap.exists) {
              throw Exception(
                'Produto não encontrado no servidor: ${resolved.ref.id}. '
                'Verifique se o produto foi sincronizado ou sua conexão com a internet.',
              );
            }

            final rawData = produtoSnap.data();
            if (rawData == null) {
              throw Exception(
                'Produto sem dados no servidor: ${resolved.ref.id}.',
              );
            }
            _txStageLog(
              'tx_stage_06_data_normalize_before',
              index: itemIndex,
              productId: resolved.ref.id,
            );
            final data = firestoreStringDynamicMapDeepOrEmpty(rawData);
            _txStageLog(
              'tx_stage_07_data_normalize_after',
              index: itemIndex,
              productId: resolved.ref.id,
              runtimeType: data.runtimeType.toString(),
            );
            final variacoesInit =
                firestoreStringDynamicMapDeepOrEmpty(data['variacoes']);
            final estoqueInit = _parseMapStringInt(data['estoquePorTamanho']);
            final slugVal = (data['slug'] ?? '').toString().trim();
            working = _DocStockWorkingState(
              produtoNome: (data['nome'] ?? '').toString(),
              produtoSlug: slugVal,
              variacoesOriginais:
                  firestoreStringDynamicMapDeepOrEmpty(variacoesInit),
              estoquePorTamanhoOriginal: Map<String, int>.from(estoqueInit),
              variacoes: firestoreStringDynamicMapDeepOrEmpty(variacoesInit),
              estoquePorTamanho: Map<String, int>.from(estoqueInit),
              quantidadeTotal: firestoreIntFieldOrZero(data['quantidade']),
            );
            workingByPath[path] = working;
          }

          final docId = resolved.ref.id;
          final produtoNome = working.produtoNome;
          final quantidade = resolved.quantidade;
          final tamanho = resolved.tamanho;
          final cor = resolved.cor;
          final extraTrim = resolved.variacaoExtra;
          final qtdAntes = working.quantidadeTotal;

          _traceEstoqueVariacao(
            stage: 'start',
            lojaId: lojaId,
            produtoId: docId,
            tamanho: tamanho,
            cor: cor,
            variacaoExtra: extraTrim,
            qtdVendida: quantidade,
            qtdAntes: qtdAntes,
            qtdDepois: qtdAntes,
            operationId: idempotency?.operationId,
            alreadyApplied: false,
          );

          final variacoes =
              firestoreStringDynamicMapDeepOrEmpty(working.variacoes);
          final estoquePorTamanho =
              Map<String, int>.from(working.estoquePorTamanho);

          _txStageLog(
            'tx_stage_09_variacoes_before',
            index: itemIndex,
            productId: docId,
            runtimeType: variacoes.runtimeType.toString(),
          );
          _txStageLog(
            'tx_stage_10_variacoes_after',
            index: itemIndex,
            productId: docId,
            runtimeType: variacoes.runtimeType.toString(),
          );

          final usaVariacoes = variacoes.isNotEmpty;
          final temEstoquePorTamanho = estoquePorTamanho.isNotEmpty;
          final temVariacaoSoloCor = usaVariacoes &&
              variacoes.containsKey('sem-tamanho') &&
              variacoes['sem-tamanho'] is Map &&
              (variacoes['sem-tamanho'] as Map).isNotEmpty;
          final temVariacaoTamanhoECor =
              usaVariacoes && _temVariacaoTamanhoECor(variacoes);

          if (usaVariacoes &&
              !temVariacaoSoloCor &&
              tamanho.isEmpty &&
              cor.isEmpty) {
            throw Exception(
              'O produto "$produtoNome" possui variações. Informe tamanho e/ou cor conforme o cadastro.',
            );
          }
          if (temVariacaoSoloCor && cor.isEmpty) {
            throw Exception(
              'O produto "$produtoNome" possui variação de cor. É obrigatório informar a COR.',
            );
          }
          if (temVariacaoTamanhoECor && (tamanho.isEmpty || cor.isEmpty)) {
            throw Exception(
              'O produto "$produtoNome" possui variações de tamanho e cor. '
              'É obrigatório informar TAMANHO e COR.',
            );
          }
          if (usaVariacoes &&
              !temVariacaoSoloCor &&
              tamanho.isEmpty &&
              cor != 'sem-cor') {
            if (_temVariacaoSoloTamanho(variacoes)) {
              throw Exception(
                'O produto "$produtoNome" possui variação de tamanho. É obrigatório informar o TAMANHO.',
              );
            }
          }
          if (_temEstoquePorTamanhoReal(estoquePorTamanho) &&
              tamanho.isEmpty &&
              !temVariacaoSoloCor) {
            throw Exception(
              'O produto "$produtoNome" possui estoque por tamanho. '
              'É obrigatório informar o TAMANHO na venda (ex.: P, M, G).',
            );
          }

          Map<String, dynamic>? novasVariacoes;
          Map<String, int>? novoEstoquePorTamanho;
          int novaQuantidadeTotal;
          var stockBranch = 'simple';

          if (temVariacaoSoloCor && cor.isNotEmpty) {
            stockBranch = 'variation';
            _txStageLog(
              'tx_stage_11_stock_compute_before',
              index: itemIndex,
              productId: docId,
              branch: stockBranch,
            );
            novasVariacoes = _mapaAposDebitoVariacao(
              variacoes: variacoes,
              chaveTamanho: 'sem-tamanho',
              corKey: cor,
              extraTrim: extraTrim,
              quantidade: quantidade,
              produtoNome: produtoNome,
              erroCtx: 'na cor $cor',
            );
            novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
          } else if (usaVariacoes && tamanho.isNotEmpty) {
            stockBranch = 'variation';
            _txStageLog(
              'tx_stage_11_stock_compute_before',
              index: itemIndex,
              productId: docId,
              branch: stockBranch,
            );
            final tamResolvidoVar = _resolverChaveNoMapa(variacoes, tamanho);
            final mapaTamVar =
                tamResolvidoVar != null ? variacoes[tamResolvidoVar] : null;
            final celulaVarExiste =
                mapaTamVar is Map && mapaTamVar.isNotEmpty;

            if (!celulaVarExiste && temEstoquePorTamanho) {
              stockBranch = 'grade';
              final tamResolvido =
                  _resolverChaveNoMapa(estoquePorTamanho, tamanho) ?? tamanho;
              final disponivel = estoquePorTamanho[tamResolvido] ?? 0;

              if (disponivel < quantidade) {
                throw Exception(
                  'Estoque insuficiente para "$produtoNome" no tamanho $tamanho. '
                  'Disponível: $disponivel, solicitado: $quantidade.',
                );
              }

              novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
              novoEstoquePorTamanho[tamResolvido] = disponivel - quantidade;
              if (novoEstoquePorTamanho[tamResolvido]! <= 0) {
                novoEstoquePorTamanho.remove(tamResolvido);
              }

              novaQuantidadeTotal =
                  novoEstoquePorTamanho.values.fold(0, (a, b) => a + b);
            } else {
              final chaveCor = _resolverCorKeyParaTamanho(
                variacoes: variacoes,
                tamanho: tamanho,
                corInformada: cor,
              );
              novasVariacoes = _mapaAposDebitoVariacao(
                variacoes: variacoes,
                chaveTamanho: tamanho,
                corKey: chaveCor,
                extraTrim: extraTrim,
                quantidade: quantidade,
                produtoNome: produtoNome,
                erroCtx:
                    'no tamanho $tamanho${cor.isEmpty ? '' : ' - cor $cor'}',
              );
              novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
            }
          } else if (temEstoquePorTamanho && tamanho.isNotEmpty) {
            stockBranch = 'grade';
            _txStageLog(
              'tx_stage_11_stock_compute_before',
              index: itemIndex,
              productId: docId,
              branch: stockBranch,
            );
            final tamResolvido =
                _resolverChaveNoMapa(estoquePorTamanho, tamanho) ?? tamanho;
            final disponivel = estoquePorTamanho[tamResolvido] ?? 0;

            if (disponivel < quantidade) {
              throw Exception(
                'Estoque insuficiente para "$produtoNome" no tamanho $tamanho. '
                'Disponível: $disponivel, solicitado: $quantidade.',
              );
            }

            novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
            novoEstoquePorTamanho[tamResolvido] = disponivel - quantidade;
            if (novoEstoquePorTamanho[tamResolvido]! <= 0) {
              novoEstoquePorTamanho.remove(tamResolvido);
            }

            novaQuantidadeTotal =
                novoEstoquePorTamanho.values.fold(0, (a, b) => a + b);
          } else {
            stockBranch = 'simple';
            _txStageLog(
              'tx_stage_11_stock_compute_before',
              index: itemIndex,
              productId: docId,
              branch: stockBranch,
            );
            final quantidadeTotal = working.quantidadeTotal;

            if (quantidadeTotal < quantidade) {
              throw Exception(
                'Estoque insuficiente para "$produtoNome". '
                'Disponível: $quantidadeTotal, solicitado: $quantidade.',
              );
            }

            novaQuantidadeTotal = quantidadeTotal - quantidade;
          }
          _txStageLog(
            'tx_stage_08_branch_resolved',
            index: itemIndex,
            productId: docId,
            branch: stockBranch,
          );
          _txStageLog(
            'tx_stage_12_stock_compute_after',
            index: itemIndex,
            productId: docId,
            branch: stockBranch,
          );

          Map<String, int>? estoquePorTamanhoParaVariacao;
          if (novasVariacoes != null) {
            estoquePorTamanhoParaVariacao =
                _estoquePorTamanhoAgregadoDeVariacoes(novasVariacoes);
            working.variacoes =
                firestoreStringDynamicMapDeepOrEmpty(novasVariacoes);
            working.estoquePorTamanho =
                Map<String, int>.from(estoquePorTamanhoParaVariacao);
            working.touchedVariacoes = true;
            working.touchedEstoquePorTamanho = true;
          } else if (novoEstoquePorTamanho != null) {
            working.estoquePorTamanho =
                Map<String, int>.from(novoEstoquePorTamanho);
            working.touchedEstoquePorTamanho = true;
          }
          working.quantidadeTotal = novaQuantidadeTotal;

          _txStageLog(
            'tx_stage_13_product_write_before',
            index: itemIndex,
            productId: docId,
          );
          // Deletes: original do doc → estado acumulado final deste path.
          final updateData = buildEstoqueUpdateDataComDeletes(
            novaQuantidadeTotal: novaQuantidadeTotal,
            variacoesAnteriores: working.variacoesOriginais,
            variacoesNovas:
                working.touchedVariacoes ? working.variacoes : null,
            estoquePorTamanhoAnterior: working.estoquePorTamanhoOriginal,
            estoquePorTamanhoNovo: working.touchedEstoquePorTamanho
                ? working.estoquePorTamanho
                : null,
          );

          final estoqueRef = _db
              .collection('lojas')
              .doc(lojaId)
              .collection(FSPaths.estoqueProdutosCol)
              .doc(docId);

          writesByPath[path] = (
            ref: resolved.ref,
            estoqueRef: estoqueRef,
            updateData: updateData,
          );

          results.add(
            EstoqueTransactionResult(
              produtoId: docId,
              produtoNome: produtoNome,
              produtoSlug: working.produtoSlug.isNotEmpty
                  ? working.produtoSlug
                  : null,
              quantidadeDebitada: quantidade,
              variacoesAtualizadas:
                  working.touchedVariacoes ? working.variacoes : null,
              estoquePorTamanhoAtualizado: working.touchedEstoquePorTamanho
                  ? Map<String, int>.from(working.estoquePorTamanho)
                  : null,
              quantidadeTotalAtualizada: novaQuantidadeTotal,
            ),
          );

          _traceEstoqueVariacao(
            stage: 'firestore',
            lojaId: lojaId,
            produtoId: docId,
            tamanho: tamanho,
            cor: cor,
            variacaoExtra: extraTrim,
            qtdVendida: quantidade,
            qtdAntes: qtdAntes,
            qtdDepois: novaQuantidadeTotal,
            operationId: idempotency?.operationId,
            alreadyApplied: false,
          );
          _txStageLog(
            'tx_stage_14_product_write_after',
            index: itemIndex,
            productId: docId,
          );
        } catch (e, st) {
          debugPrint(
            '[H1-TX-STAGE] stage=tx_error_stage index=$itemIndex '
            'productId=${resolved.ref.id} errorRuntimeType=${e.runtimeType} '
            'error=$e',
          );
          debugPrint('$st');
          rethrow;
        }
      }

      // FASE 2: Uma escrita por documento (estado acumulado final).
      for (final u in writesByPath.values) {
        transaction.update(u.ref, u.updateData);
        if (u.estoqueRef != null) {
          transaction.set(u.estoqueRef!, u.updateData, SetOptions(merge: true));
        }
      }

      if (idempotency != null) {
        _txStageLog(
          'tx_stage_15_marker_write_before',
          operationId: idempotency.operationId,
        );
        try {
          _txStageLog(
            'tx_stage_15a_marker_payload_before',
            operationId: idempotency.operationId,
          );
          final markerPayload = buildMarkerBaixaPdvPayload(
            lojaId: lojaId,
            operationId: idempotency.operationId,
            snapshotHash: idempotency.snapshotHash,
            txItemsHash: idempotency.txItemsHash,
          );
          _txStageLog(
            'tx_stage_15b_marker_payload_after',
            operationId: idempotency.operationId,
            runtimeType: markerPayload.runtimeType.toString(),
          );
          _txStageLog(
            'tx_stage_15c_marker_set_before',
            operationId: idempotency.operationId,
          );
          transaction.set(
            _baixaPagamentoRef(lojaId, idempotency.operationId),
            markerPayload,
          );
          _txStageLog(
            'tx_stage_15d_marker_set_after',
            operationId: idempotency.operationId,
          );
        } catch (e, st) {
          debugPrint(
            '[H1-TX-STAGE] stage=tx_error_stage marker_write '
            'operationId=${idempotency.operationId.length > 8 ? '${idempotency.operationId.substring(0, 8)}…' : idempotency.operationId} '
            'errorRuntimeType=${e.runtimeType} error=$e',
          );
          debugPrint('$st');
          rethrow;
        }
        _txStageLog(
          'tx_stage_16_marker_write_after',
          operationId: idempotency.operationId,
        );
      }

      final delay = debugBatchTransactionDelay;
      if (delay != null && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      _txStageLog('tx_stage_17_callback_return');
      return _TransacaoBaixaBatchOutcome(alreadyApplied: false, results: results);
        });
      }

      final sw = Stopwatch()..start();
      final itemCount = resolvedItems.length;
      final idempotent = idempotency != null;
      debugPrint(
        '[H1-TRACE] stage=batch_before_runTransaction '
        'lojaId=$lojaId itemCount=$itemCount idempotent=$idempotent',
      );
      return run().whenComplete(() {
        debugPrint(
          '[H1-TRACE] stage=batch_after_runTransaction '
          'lojaId=$lojaId elapsedMs=${sw.elapsedMilliseconds} '
          'stockPath=batch_idempotent',
        );
        debugPrint(
          '[ESTOQUE-TX] batch transaction elapsedMs=${sw.elapsedMilliseconds}',
        );
      });
    }

    try {
      final outcome = await executarTransacao(idempotency);
      return outcome;
    } catch (e) {
      final docId = _extrairDocIdProdutosNotFound(e, lojaId);
      if (docId == null) rethrow;
      final reparado = await _repararEspelhoProdutosSeAusente(
        lojaId: lojaId,
        docId: docId,
      );
      if (!reparado) {
        throw Exception(
          'Produto sem documento válido de estoque na nuvem (ID: $docId). '
          'Sincronize o produto no cadastro e tente finalizar novamente.',
        );
      }
      debugPrint('[ESTOQUE-TX] 🔁 Retry batch após reparar produtos/$docId');
      final retryOutcome = await executarTransacao(idempotency);
      return retryOutcome;
    }
  }

  /// Baixa idempotente por [operationId] — marker V1 + estoque na mesma transação.
  static Future<EstoqueBaixaOperationResult>
      baixarEstoqueTransactionBatchIdempotente({
    required String lojaId,
    required List<Map<String, dynamic>> itens,
    required String operationId,
  }) async {
    final opId = operationId.trim();
    if (opId.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId', 'não pode ser vazio');
    }

    if (itens.length > _maxItensPorTransacao) {
      throw Exception(
        'Venda com muitos itens (${itens.length}). '
        'Divida em vendas menores (máx. $_maxItensPorTransacao itens por venda).',
      );
    }

    final resolvedItems = await _resolverItensMescladosBaixa(lojaId, itens);
    if (resolvedItems.isEmpty) {
      throw Exception(
        'Nenhum item válido para baixa de estoque (quantidade ou produto inválido).',
      );
    }

    await _validarTombstonesBaixa(lojaId: lojaId, resolvedItems: resolvedItems);

    final idempotency = _PdvBaixaIdempotencyContext(
      operationId: opId,
      txItemsHash: computeTxItemsHashForIdempotencia(itens),
      snapshotHash: computeSnapshotHashFromResolvedBaixa(resolvedItems),
    );

    final outcome = await _executarBaixaBatchInterno(
      lojaId: lojaId,
      resolvedItems: resolvedItems,
      idempotency: idempotency,
    );

    return EstoqueBaixaOperationResult(
      status: outcome.alreadyApplied
          ? EstoqueBaixaOperationStatus.alreadyApplied
          : EstoqueBaixaOperationStatus.applied,
      transactionResults: outcome.results,
    );
  }

  /// Key Hive usada no pós-pagamento catálogo (`estoque_baixa_pagamento/{vendaId}`).
  static String? vendaIdMarcadorCatalogoFromKey(dynamic hiveKey) {
    if (hiveKey == null) return null;
    final s = hiveKey.toString().trim();
    return s.isEmpty ? null : s;
  }

  static DocumentReference<Map<String, dynamic>> _baixaPagamentoRef(
    String lojaId,
    String vendaIdMarcador,
  ) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('estoque_baixa_pagamento')
        .doc(vendaIdMarcador);
  }

  static Future<EstoqueBaixaPagamentoMarcador> lerMarcadorBaixaPagamento(
    String lojaId,
    String vendaIdMarcador,
  ) async {
    final vid = vendaIdMarcador.trim();
    if (vid.isEmpty) return EstoqueBaixaPagamentoMarcador.ausente;
    try {
      final snap = await _baixaPagamentoRef(lojaId, vid).get();
      if (!snap.exists) return EstoqueBaixaPagamentoMarcador.ausente;
      final data = snap.data() ?? {};
      return EstoqueBaixaPagamentoMarcador(
        existe: true,
        baixaAplicada: data['baixaAplicada'] == true,
        estornoAplicado: data['estornoAplicado'] == true,
      );
    } catch (e) {
      debugPrint(
        '[ESTOQUE-TX] Falha ao ler estoque_baixa_pagamento/$vid (type=${e.runtimeType})',
      );
      return EstoqueBaixaPagamentoMarcador.ausente;
    }
  }

  static Future<void> marcarEstornoAplicadoCatalogo({
    required String lojaId,
    required String vendaIdMarcador,
    String origem = 'venda_delete',
  }) async {
    final vid = vendaIdMarcador.trim();
    if (vid.isEmpty) return;
    try {
      await _baixaPagamentoRef(lojaId, vid).set({
        'estornoAplicado': true,
        'estornoAplicadoAt': FieldValue.serverTimestamp(),
        'estornoOrigem': origem,
        'lojaId': lojaId,
        'vendaId': vid,
      }, SetOptions(merge: true));
      debugPrint(
        '[ESTOQUE-TX] estornoAplicado=true em estoque_baixa_pagamento/$vid',
      );
    } catch (e) {
      debugPrint(
        '[ESTOQUE-TX] Falha ao marcar estornoAplicado/$vid (type=${e.runtimeType})',
      );
      rethrow;
    }
  }

  static Future<void> limparEstornoAplicadoCatalogo(
    String lojaId,
    String vendaIdMarcador,
  ) async {
    final vid = vendaIdMarcador.trim();
    if (vid.isEmpty) return;
    try {
      await _baixaPagamentoRef(lojaId, vid).set({
        'estornoAplicado': false,
        'estornoAplicadoAt': FieldValue.delete(),
        'estornoOrigem': FieldValue.delete(),
      }, SetOptions(merge: true));
      debugPrint(
        '[ESTOQUE-TX] estornoAplicado limpo em estoque_baixa_pagamento/$vid',
      );
    } catch (e) {
      debugPrint(
        '[ESTOQUE-TX] Falha ao limpar estornoAplicado/$vid (type=${e.runtimeType})',
      );
    }
  }

  /// Resolve id de idempotência da devolução: prioriza key Hive do marcador catálogo.
  static Future<String> resolverVendaIdIdempotenciaDevolucao({
    required String lojaId,
    required String? vendaIdMarcadorCatalogo,
    required String vendaIdFallback,
  }) async {
    final marcadorId = (vendaIdMarcadorCatalogo ?? '').trim();
    if (marcadorId.isNotEmpty) {
      final marcador = await lerMarcadorBaixaPagamento(lojaId, marcadorId);
      if (marcador.existe) return marcadorId;
    }
    return vendaIdFallback.trim();
  }

  /// Indica se a devolução já foi feita (remoto catálogo ou idempotência local).
  static Future<bool> devolucaoVendaJaAplicada(
    String lojaId,
    String vendaId,
  ) async {
    final marcador = await lerMarcadorBaixaPagamento(lojaId, vendaId);
    if (marcador.existe && marcador.estornoAplicado) return true;
    return _devolucaoLocalJaFeita(lojaId, vendaId);
  }

  /// true se qualquer id candidato já tiver estorno/idempotência.
  static Future<bool> devolucaoVendaJaAplicadaEmQualquerId(
    String lojaId,
    Iterable<String> candidatos,
  ) async {
    for (final raw in candidatos) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (await devolucaoVendaJaAplicada(lojaId, id)) return true;
    }
    return false;
  }

  /// Após devolução bem-sucedida, marca todos os IDs conhecidos (anti 2º estorno).
  static Future<void> marcarDevolucaoLocalEmTodosIds(
    String lojaId,
    Iterable<String> candidatos,
  ) async {
    for (final raw in candidatos) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      await _marcarDevolucaoLocalFeita(lojaId, id);
    }
  }

  /// Remove o marcador de idempotência local (ex.: após desfazer exclusão da venda).
  static Future<void> removerMarcadorDevolucaoVenda(
    String lojaId,
    String vendaId,
  ) async {
    final key = _devolucaoLocalPrefsKeyOrNull(lojaId, vendaId);
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      debugPrint('[ESTOQUE-TX] Marcador devolução local removido key=$key');
    } catch (e) {
      debugPrint('[ESTOQUE-TX] Falha ao remover marcador devolução local: $e');
    }
  }

  /// Devolve estoque de múltiplos itens (cancelamento/desfazer venda).
  /// Atualiza estoque_produtos e produtos. Idempotente quando [vendaIdParaIdempotencia] informado.
  static Future<List<EstoqueTransactionResult>> devolverEstoqueTransactionBatch({
    required String lojaId,
    required List<Map<String, dynamic>> itens,
    String? vendaIdParaIdempotencia,
    String estornoOrigemCatalogo = 'venda_delete',
  }) async {
    if (itens.isEmpty) return [];

    final vidTrim = (vendaIdParaIdempotencia ?? '').trim();
    if (vidTrim.isNotEmpty) {
      final marcadorRemoto = await lerMarcadorBaixaPagamento(lojaId, vidTrim);
      if (marcadorRemoto.existe && marcadorRemoto.estornoAplicado) {
        debugPrint(
          '[ESTOQUE-TX] Devolução já aplicada (estornoAplicado remoto): vendaId=$vidTrim',
        );
        debugPrint(
          '[COMBO-DEVOLUCAO-RESULT] vendaId=$vidTrim count=0 ids= motivo=estorno_remoto',
        );
        return [];
      }
      if (await _devolucaoLocalJaFeita(lojaId, vidTrim)) {
        debugPrint(
          '[ESTOQUE-TX] Devolução já aplicada (idempotente local): vendaId=$vidTrim',
        );
        debugPrint(
          '[COMBO-DEVOLUCAO-RESULT] vendaId=$vidTrim count=0 ids= motivo=idempotencia_local',
        );
        return [];
      }
    }

    if (itens.length > _maxItensPorTransacao) {
      throw Exception(
        'Devolução com muitos itens (${itens.length}). '
        'Máx. $_maxItensPorTransacao itens por operação.',
      );
    }

    final resolvedItems = await _resolverItensMescladosDevolucao(lojaId, itens);

    if (resolvedItems.isEmpty) {
      if (itens.isNotEmpty) {
        throw StateError(
          '[ESTOQUE-TX] Devolução: nenhum documento resolvido para ${itens.length} item(ns). '
          'Verifique productId, slug e nome nos logs [COMBO-DEVOLUCAO-ITEM].',
        );
      }
      return [];
    }

    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
    for (final r in resolvedItems) {
      if (await ProdutoExclusaoTombstoneService.isProdutoBloqueadoRemoto(
          lojaId: lojaId, estoqueDocId: r.ref.id)) {
        throw Exception(
          'Devolução indisponível: produto foi excluído (id=${r.ref.id}).',
        );
      }
      if (await ProdutoExclusaoTombstoneService.isVendaBloqueadaParaCelula(
        lojaId: lojaId,
        estoqueDocId: r.ref.id,
        tamanho: r.tamanho,
        cor: r.cor,
        variacaoExtra: r.variacaoExtra,
      )) {
        throw Exception(
          'Devolução indisponível: variação removida do cadastro. Sincronize o app.',
        );
      }
    }

    final resultados =
        await _db.runTransaction<List<EstoqueTransactionResult>>((transaction) async {
      final results = <EstoqueTransactionResult>[];
      final writesByPath = <String, ({
        DocumentReference<Map<String, dynamic>> ref,
        DocumentReference<Map<String, dynamic>>? estoqueRef,
        Map<String, dynamic> updateData,
      })>{};
      final workingByPath = <String, _DocStockWorkingState>{};

      for (final resolved in resolvedItems) {
        final path = resolved.ref.path;
        late final _DocStockWorkingState working;

        if (workingByPath.containsKey(path)) {
          working = workingByPath[path]!;
        } else {
          final produtoSnap = await transaction.get(resolved.ref);
          if (!produtoSnap.exists) continue;

          final data = firestoreStringDynamicMapDeepOrEmpty(produtoSnap.data());
          final variacoesInit =
              firestoreStringDynamicMapDeepOrEmpty(data['variacoes']);
          final estoqueInit = _parseMapStringInt(data['estoquePorTamanho']);
          final slugVal = (data['slug'] ?? '').toString().trim();
          working = _DocStockWorkingState(
            produtoNome: (data['nome'] ?? '').toString(),
            produtoSlug: slugVal,
            variacoesOriginais:
                firestoreStringDynamicMapDeepOrEmpty(variacoesInit),
            estoquePorTamanhoOriginal: Map<String, int>.from(estoqueInit),
            variacoes: firestoreStringDynamicMapDeepOrEmpty(variacoesInit),
            estoquePorTamanho: Map<String, int>.from(estoqueInit),
            quantidadeTotal: firestoreIntFieldOrZero(data['quantidade']),
          );
          workingByPath[path] = working;
        }

        final docId = resolved.ref.id;
        final produtoNome = working.produtoNome;
        final quantidade = resolved.quantidade;
        final tamanho = resolved.tamanho;
        final cor = resolved.cor;
        final extraTrim = resolved.variacaoExtra;
        final qtdAntes = working.quantidadeTotal;

        _traceEstoqueVariacao(
          stage: 'start',
          lojaId: lojaId,
          produtoId: docId,
          tamanho: tamanho,
          cor: cor,
          variacaoExtra: extraTrim,
          qtdVendida: -quantidade,
          qtdAntes: qtdAntes,
          qtdDepois: qtdAntes,
          operationId: vidTrim.isEmpty ? null : vidTrim,
          alreadyApplied: false,
        );

        final variacoes =
            firestoreStringDynamicMapDeepOrEmpty(working.variacoes);
        final estoquePorTamanho =
            Map<String, int>.from(working.estoquePorTamanho);

        final usaVariacoes = variacoes.isNotEmpty;
        final temEstoquePorTamanho = estoquePorTamanho.isNotEmpty;
        final temVariacaoSoloCor = usaVariacoes &&
            variacoes.containsKey('sem-tamanho') &&
            variacoes['sem-tamanho'] is Map;

        Map<String, dynamic>? novasVariacoes;
        Map<String, int>? novoEstoquePorTamanho;
        int novaQuantidadeTotal;

        if (temVariacaoSoloCor && cor.isNotEmpty) {
          novasVariacoes = _mapaAposDevolverVariacao(
            variacoes: variacoes,
            chaveTamanho: 'sem-tamanho',
            corKey: cor,
            extraTrim: extraTrim,
            quantidade: quantidade,
          );
          novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
        } else if (usaVariacoes && tamanho.isNotEmpty) {
          final chaveCor = _resolverCorKeyParaTamanho(
            variacoes: variacoes,
            tamanho: tamanho,
            corInformada: cor,
          );
          novasVariacoes = _mapaAposDevolverVariacao(
            variacoes: variacoes,
            chaveTamanho: tamanho,
            corKey: chaveCor,
            extraTrim: extraTrim,
            quantidade: quantidade,
          );
          novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
        } else if (temEstoquePorTamanho && tamanho.isNotEmpty) {
          novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
          novoEstoquePorTamanho[tamanho] =
              (novoEstoquePorTamanho[tamanho] ?? 0) + quantidade;
          novaQuantidadeTotal =
              novoEstoquePorTamanho.values.fold(0, (a, b) => a + b);
        } else {
          novaQuantidadeTotal = working.quantidadeTotal + quantidade;
        }

        if (novasVariacoes != null) {
          final agregado =
              _estoquePorTamanhoAgregadoDeVariacoes(novasVariacoes);
          working.variacoes =
              firestoreStringDynamicMapDeepOrEmpty(novasVariacoes);
          working.estoquePorTamanho = Map<String, int>.from(agregado);
          working.touchedVariacoes = true;
          working.touchedEstoquePorTamanho = true;
        } else if (novoEstoquePorTamanho != null) {
          working.estoquePorTamanho =
              Map<String, int>.from(novoEstoquePorTamanho);
          working.touchedEstoquePorTamanho = true;
        }
        working.quantidadeTotal = novaQuantidadeTotal;

        final updateData = buildEstoqueUpdateDataComDeletes(
          novaQuantidadeTotal: novaQuantidadeTotal,
          variacoesAnteriores: working.variacoesOriginais,
          variacoesNovas:
              working.touchedVariacoes ? working.variacoes : null,
          estoquePorTamanhoAnterior: working.estoquePorTamanhoOriginal,
          estoquePorTamanhoNovo: working.touchedEstoquePorTamanho
              ? working.estoquePorTamanho
              : null,
        );

        final estoqueRef = _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(docId);
        writesByPath[path] = (
          ref: resolved.ref,
          estoqueRef: estoqueRef,
          updateData: updateData,
        );

        results.add(
          EstoqueTransactionResult(
            produtoId: docId,
            produtoNome: produtoNome,
            produtoSlug:
                working.produtoSlug.isNotEmpty ? working.produtoSlug : null,
            quantidadeDebitada: -quantidade,
            variacoesAtualizadas:
                working.touchedVariacoes ? working.variacoes : null,
            estoquePorTamanhoAtualizado: working.touchedEstoquePorTamanho
                ? Map<String, int>.from(working.estoquePorTamanho)
                : null,
            quantidadeTotalAtualizada: novaQuantidadeTotal,
          ),
        );

        _traceEstoqueVariacao(
          stage: 'done',
          lojaId: lojaId,
          produtoId: docId,
          tamanho: tamanho,
          cor: cor,
          variacaoExtra: extraTrim,
          qtdVendida: -quantidade,
          qtdAntes: qtdAntes,
          qtdDepois: novaQuantidadeTotal,
          operationId: vidTrim.isEmpty ? null : vidTrim,
          alreadyApplied: false,
        );
      }

      for (final u in writesByPath.values) {
        transaction.update(u.ref, u.updateData);
        if (u.estoqueRef != null) {
          transaction.set(u.estoqueRef!, u.updateData, SetOptions(merge: true));
        }
      }

      return results;
    }).timeout(

      const Duration(seconds: 25),
      onTimeout: () => throw TimeoutException('Transação de devolução demorou muito. Tente novamente.'),
    );

    if (resultados.isEmpty && resolvedItems.isNotEmpty) {
      debugPrint(
        '[COMBO-DEVOLUCAO-RESULT] vendaId=$vidTrim count=0 ids= motivo=nenhum_snapshot_atualizado',
      );
      throw StateError(
        '[ESTOQUE-TX] Devolução: nenhum documento atualizado (snapshots inexistentes?). '
        'Itens resolvidos: ${resolvedItems.length}.',
      );
    }

    if (vidTrim.isNotEmpty && resultados.isNotEmpty) {
      await _marcarDevolucaoLocalFeita(lojaId, vidTrim);
      debugPrint(
        '[ESTOQUE-TX] Idempotência devolução gravada localmente vendaId=$vidTrim',
      );
      final marcadorPos = await lerMarcadorBaixaPagamento(lojaId, vidTrim);
      if (marcadorPos.existe && marcadorPos.baixaAplicada) {
        try {
          await marcarEstornoAplicadoCatalogo(
            lojaId: lojaId,
            vendaIdMarcador: vidTrim,
            origem: estornoOrigemCatalogo,
          );
        } catch (e) {
          debugPrint(
            '[ESTOQUE-TX] Devolução OK mas falhou marcar estornoAplicado '
            '(type=${e.runtimeType}) vendaId=$vidTrim',
          );
        }
      }
    }
    return resultados;
  }

  /// Remove produto do catálogo (produtos e draft_produtos) quando estoque zerou.
  /// Chamado após a transação para que o produto saia imediatamente do site.
  static Future<void> removerDoCatalogoSeEstoqueZerado(
    String lojaId,
    List<EstoqueTransactionResult> results,
  ) async {
    for (final r in results) {
      if (r.quantidadeTotalAtualizada > 0) continue;
      final idsToTry = <String>[
        if (r.produtoSlug?.trim().isNotEmpty ?? false) r.produtoSlug!.trim(),
        r.produtoId,
      ].where((s) => s.isNotEmpty).toSet().toList();
      for (final docId in idsToTry) {
        try {
          final base = _db.collection('lojas').doc(lojaId);
          final prodRef = base.collection('produtos').doc(docId);
          final draftRef = base.collection(FSPaths.draftProdutosCol).doc(docId);
          if ((await prodRef.get()).exists) await prodRef.delete();
          if ((await draftRef.get()).exists) await draftRef.delete();
          CatalogCacheService.invalidate(lojaId, preview: false);
          CatalogCacheService.invalidate(lojaId, preview: true);
          debugPrint('[ESTOQUE-TX] 🗑️ Removido do catálogo (estoque zero): $docId');
          break;
        } catch (e) {
          debugPrint('[ESTOQUE-TX] ⚠️ Erro ao remover $docId (type=${e.runtimeType})');
        }
      }
    }
  }

  /// Atualiza o Hive após transação bem-sucedida (para consistência local)
  static Future<void> atualizarHiveAposTransacao({
    required Box<Produto> produtosBox,
    required String lojaId,
    required EstoqueTransactionResult result,
    String tamanho = '',
    String cor = '',
  }) async {
    Produto? produto;
    final idOk = result.produtoId.isNotEmpty;
    final slugOk = result.produtoSlug != null && result.produtoSlug!.trim().isNotEmpty;
    final nomeOk = result.produtoNome.trim().isNotEmpty;
    final nomeLower = result.produtoNome.trim().toLowerCase();

    for (final p in produtosBox.values) {
      if (p.lojaId != lojaId) continue;
      if (idOk && p.idFirebase == result.produtoId) { produto = p; break; }
      if (slugOk && p.slug == result.produtoSlug!.trim()) { produto = p; break; }
      if (nomeOk && p.nome.trim().toLowerCase() == nomeLower) { produto = p; break; }
    }

    if (produto != null) {
      produto.quantidade = result.quantidadeTotalAtualizada;
      if (result.variacoesAtualizadas != null) {
        produto.variacoes = result.variacoesAtualizadas;
      }
      if (result.estoquePorTamanhoAtualizado != null) {
        produto.estoquePorTamanho = result.estoquePorTamanhoAtualizado!;
      }
      touchProdutoUpdatedAtParaHivePosTransacao(produto);
      await produto.save();
      debugPrint('[ESTOQUE-TX] Hive atualizado: ${produto.nome}');
    } else {
      final slug = result.produtoSlug?.trim();
      debugPrint(
        '[ESTOQUE-TX-HIVE-MISS] Baixa Firestore aplicada, mas Hive local não encontrou produto para espelhar | '
        'lojaId=$lojaId | productId=${result.produtoId} | slug=${slug ?? '(vazio)'} | nome=${result.produtoNome} | '
        'tamanho=${tamanho.isEmpty ? '(vazio)' : tamanho} | cor=${cor.isEmpty ? '(vazio)' : cor} | '
        'motivo=sem match por idFirebase/slug/nome na Box<Produto> desta loja',
      );
    }
  }
}
