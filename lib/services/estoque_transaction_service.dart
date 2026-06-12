// lib/services/estoque_transaction_service.dart
//
// Serviço centralizado para baixa de estoque COM transação Firestore.
// Elimina race conditions: read → validate → decrement é atômico.
//
// Uso: chamar baixarEstoqueTransaction() ANTES de qualquer lógica de venda.
// Após sucesso, atualizar Hive local para consistência.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/dart_error_unwrap.dart';
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

  EstoqueTransactionResult({
    required this.produtoId,
    required this.produtoNome,
    this.produtoSlug,
    required this.quantidadeDebitada,
    this.variacoesAtualizadas,
    this.estoquePorTamanhoAtualizado,
    required this.quantidadeTotalAtualizada,
  });
}

/// Serviço de baixa de estoque atômica via Firestore Transaction
class EstoqueTransactionService {
  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

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

      final variacoesRaw = data['variacoes'] as Map<String, dynamic>?;
      final estoquePorTamanhoRaw = data['estoquePorTamanho'];
      final quantidadeTotal = (data['quantidade'] as num?)?.toInt() ?? 0;

      final variacoes = variacoesRaw != null
          ? Map<String, dynamic>.from(variacoesRaw)
          : <String, dynamic>{};
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

      // Propagar para produtos (catálogo web)
      final produtosRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .doc(docId);
      // Coleção de catálogo pode não ter o doc publicado; manter espelho sem falhar.
      transaction.set(produtosRef, updateData, SetOptions(merge: true));

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
        Map<String, dynamic>.from(variacoesNovas),
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
    final mapa = Map<String, dynamic>.from(mapaCor);
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
    final novasVariacoes = Map<String, dynamic>.from(variacoes);
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
        ? Map<String, dynamic>.from(mapaCor)
        : <String, dynamic>{};
    final cell = mapa[corKey];
    mapa[corKey] =
        ProdutoVariacaoExtra.devolverCelula(cell, extraTrim, quantidade);
    final novasVariacoes = Map<String, dynamic>.from(variacoes);
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

    Future<List<EstoqueTransactionResult>> executarTransacao() {
      return _db.runTransaction<List<EstoqueTransactionResult>>((transaction) async {
      // FASE 1: Todas as leituras antes de qualquer escrita (regra do Firestore)
      final updates = <({DocumentReference<Map<String, dynamic>> ref, DocumentReference<Map<String, dynamic>>? estoqueRef, Map<String, dynamic> updateData, EstoqueTransactionResult result})>[];

      for (final resolved in resolvedItems) {
        final produtoSnap = await transaction.get(resolved.ref);

        if (!produtoSnap.exists) {
          throw Exception(
            'Produto não encontrado no servidor: ${resolved.ref.id}. '
            'Verifique se o produto foi sincronizado ou sua conexão com a internet.',
          );
        }

        final data = produtoSnap.data()!;
        final docId = produtoSnap.reference.id;
        final produtoNome = (data['nome'] ?? '').toString();
        final quantidade = resolved.quantidade;
        final tamanho = resolved.tamanho;
        final cor = resolved.cor;
        final extraTrim = resolved.variacaoExtra;

        final variacoesRaw = data['variacoes'] as Map<String, dynamic>?;
        final estoquePorTamanhoRaw = data['estoquePorTamanho'];

        final variacoes = variacoesRaw != null
            ? Map<String, dynamic>.from(variacoesRaw)
            : <String, dynamic>{};
        final estoquePorTamanho = _parseMapStringInt(estoquePorTamanhoRaw);

        final usaVariacoes = variacoes.isNotEmpty;
        final temEstoquePorTamanho = estoquePorTamanho.isNotEmpty;
        final temVariacaoSoloCor = usaVariacoes && variacoes.containsKey('sem-tamanho') &&
            variacoes['sem-tamanho'] is Map && (variacoes['sem-tamanho'] as Map).isNotEmpty;
        final temVariacaoTamanhoECor = usaVariacoes && _temVariacaoTamanhoECor(variacoes);

        if (usaVariacoes && !temVariacaoSoloCor && tamanho.isEmpty && cor.isEmpty) {
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
        if (usaVariacoes && !temVariacaoSoloCor && tamanho.isEmpty && cor != 'sem-cor') {
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

        if (temVariacaoSoloCor && cor.isNotEmpty) {
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
          final tamResolvidoVar = _resolverChaveNoMapa(variacoes, tamanho);
          final mapaTamVar = tamResolvidoVar != null
              ? variacoes[tamResolvidoVar]
              : null;
          final celulaVarExiste = mapaTamVar is Map && mapaTamVar.isNotEmpty;

          if (!celulaVarExiste && temEstoquePorTamanho) {
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
          final quantidadeTotal = (data['quantidade'] as num?)?.toInt() ?? 0;

          if (quantidadeTotal < quantidade) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome". '
              'Disponível: $quantidadeTotal, solicitado: $quantidade.',
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

        final estoqueRef = _db
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(docId);

        final slugVal = (data['slug'] ?? '').toString().trim();
        updates.add((
          ref: resolved.ref,
          estoqueRef: estoqueRef,
          updateData: updateData,
          result: EstoqueTransactionResult(
            produtoId: docId,
            produtoNome: produtoNome,
            produtoSlug: slugVal.isNotEmpty ? slugVal : null,
            quantidadeDebitada: quantidade,
            variacoesAtualizadas: novasVariacoes,
            estoquePorTamanhoAtualizado:
                estoquePorTamanhoParaVariacao ?? novoEstoquePorTamanho,
            quantidadeTotalAtualizada: novaQuantidadeTotal,
          ),
        ));
      }

      // FASE 2: Todas as escritas (após todas as leituras)
      for (final u in updates) {
        transaction.update(u.ref, u.updateData);
        if (u.estoqueRef != null) {
          transaction.set(u.estoqueRef!, u.updateData, SetOptions(merge: true));
        }
        // Propagar para produtos (catálogo web) — doc pode não existir se não publicado
        final produtosRef = _db
            .collection('lojas')
            .doc(lojaId)
            .collection('produtos')
            .doc(u.result.produtoId);
        transaction.set(produtosRef, u.updateData, SetOptions(merge: true));
      }

      final results = updates.map((u) => u.result).toList();
      return results;
      }).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Transação de estoque demorou muito. Tente novamente.',
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
      debugPrint('[ESTOQUE-TX] 🔁 Retry batch após reparar produtos/$docId');
      return executarTransacao();
    }
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
      final updates = <({DocumentReference<Map<String, dynamic>> ref, DocumentReference<Map<String, dynamic>>? estoqueRef, Map<String, dynamic> updateData, EstoqueTransactionResult result})>[];

      for (final resolved in resolvedItems) {
        final produtoSnap = await transaction.get(resolved.ref);
        if (!produtoSnap.exists) continue;

        final data = produtoSnap.data()!;
        final docId = produtoSnap.reference.id;
        final produtoNome = (data['nome'] ?? '').toString();
        final quantidade = resolved.quantidade;
        final tamanho = resolved.tamanho;
        final cor = resolved.cor;
        final extraTrim = resolved.variacaoExtra;

        final variacoesRaw = data['variacoes'] as Map<String, dynamic>?;
        final estoquePorTamanhoRaw = data['estoquePorTamanho'];
        final variacoes = variacoesRaw != null ? Map<String, dynamic>.from(variacoesRaw) : <String, dynamic>{};
        final estoquePorTamanho = _parseMapStringInt(estoquePorTamanhoRaw);

        final usaVariacoes = variacoes.isNotEmpty;
        final temEstoquePorTamanho = estoquePorTamanho.isNotEmpty;
        final temVariacaoSoloCor = usaVariacoes && variacoes.containsKey('sem-tamanho') && variacoes['sem-tamanho'] is Map;

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
          novoEstoquePorTamanho[tamanho] = (novoEstoquePorTamanho[tamanho] ?? 0) + quantidade;
          novaQuantidadeTotal = novoEstoquePorTamanho.values.fold(0, (a, b) => a + b);
        } else {
          final qtdAtual = (data['quantidade'] as num?)?.toInt() ?? 0;
          novaQuantidadeTotal = qtdAtual + quantidade;
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

        final estoqueRef = _db.collection('lojas').doc(lojaId).collection(FSPaths.estoqueProdutosCol).doc(docId);
        final slugVal = (data['slug'] ?? '').toString().trim();
        updates.add((
          ref: resolved.ref,
          estoqueRef: estoqueRef,
          updateData: updateData,
          result: EstoqueTransactionResult(
            produtoId: docId,
            produtoNome: produtoNome,
            produtoSlug: slugVal.isNotEmpty ? slugVal : null,
            quantidadeDebitada: -quantidade,
            variacoesAtualizadas: novasVariacoes,
            estoquePorTamanhoAtualizado:
                estoquePorTamanhoParaVariacao ?? novoEstoquePorTamanho,
            quantidadeTotalAtualizada: novaQuantidadeTotal,
          ),
        ));
      }

      for (final u in updates) {
        transaction.update(u.ref, u.updateData);
        if (u.estoqueRef != null) {
          transaction.set(u.estoqueRef!, u.updateData, SetOptions(merge: true));
        }
        final produtosRef = _db.collection('lojas').doc(lojaId).collection('produtos').doc(u.result.produtoId);
        transaction.set(produtosRef, u.updateData, SetOptions(merge: true));
      }

      return updates.map((u) => u.result).toList();
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
