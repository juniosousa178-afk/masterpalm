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
import '../core/strict_product_resolution.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';
import 'catalog_cache_service.dart';

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
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

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
  }) async {
    if (quantidade <= 0) {
      throw Exception('Quantidade deve ser maior que zero');
    }

    final tam = tamanho.trim();
    final corTrim = cor.trim();

    final produtoRef = await _resolverProdutoRef(lojaId: lojaId, produtoId: produtoId, slug: slug, nome: nome);
    if (produtoRef == null) {
      throw Exception(
        'Produto não encontrado no servidor: ${produtoId ?? slug ?? nome}. '
        'Verifique se o produto foi sincronizado ou sua conexão com a internet.',
      );
    }

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
        if (temEstoquePorTamanho && tam.isEmpty) {
          throw Exception(
            'O produto "$produtoNome" possui estoque por tamanho. '
            'É obrigatório informar o TAMANHO na venda (ex.: P, M, G).',
          );
        }

        int disponivel;
      Map<String, dynamic>? novasVariacoes;
      Map<String, int>? novoEstoquePorTamanho;
      int novaQuantidadeTotal;

      if (temVariacaoSoloCor && corTrim.isNotEmpty) {
        final mapaCor = variacoes['sem-tamanho'];
        if (mapaCor == null || mapaCor is! Map) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome" na cor $corTrim. Disponível: 0, solicitado: $quantidade.',
          );
        }
        final mapa = Map<String, dynamic>.from(mapaCor);
        disponivel = (mapa[corTrim] as num?)?.toInt() ?? 0;
        if (disponivel < quantidade) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome" na cor $corTrim. '
            'Disponível: $disponivel, solicitado: $quantidade.',
          );
        }
        mapa[corTrim] = disponivel - quantidade;
        if (mapa[corTrim] <= 0) mapa.remove(corTrim);
        novasVariacoes = Map<String, dynamic>.from(variacoes);
        novasVariacoes['sem-tamanho'] = mapa;
        if (mapa.isEmpty) novasVariacoes.remove('sem-tamanho');
        novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
      } else if (usaVariacoes && tam.isNotEmpty) {
        final chaveCor = corTrim.isEmpty ? 'sem-cor' : corTrim;
        final mapaTamanho = variacoes[tam];
        if (mapaTamanho == null || mapaTamanho is! Map) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome" no tamanho $tam${corTrim.isEmpty ? '' : ' - cor $corTrim'}. '
            'Disponível: 0, solicitado: $quantidade.',
          );
        }
        final mapaCor = Map<String, dynamic>.from(mapaTamanho);
        disponivel = (mapaCor[chaveCor] as num?)?.toInt() ?? 0;
        if (disponivel < quantidade) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome" no tamanho $tam${corTrim.isEmpty ? '' : ' - cor $corTrim'}. '
            'Disponível: $disponivel, solicitado: $quantidade.',
          );
        }
        mapaCor[chaveCor] = disponivel - quantidade;
        if (mapaCor[chaveCor] <= 0) mapaCor.remove(chaveCor);
        novasVariacoes = Map<String, dynamic>.from(variacoes);
        novasVariacoes[tam] = mapaCor;
        if (mapaCor.isEmpty) novasVariacoes.remove(tam);
        novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
      } else if (temEstoquePorTamanho && tam.isNotEmpty) {
        disponivel = estoquePorTamanho[tam] ?? 0;

        if (disponivel < quantidade) {
          throw Exception(
            'Estoque insuficiente para "$produtoNome" no tamanho $tam. '
            'Disponível: $disponivel, solicitado: $quantidade.',
          );
        }

        novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
        novoEstoquePorTamanho[tam] = disponivel - quantidade;
        if (novoEstoquePorTamanho[tam]! <= 0) {
          novoEstoquePorTamanho.remove(tam);
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

      final updateData = <String, dynamic>{
        'quantidade': novaQuantidadeTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (novasVariacoes != null) {
        updateData['variacoes'] = novasVariacoes;
      }
      if (novoEstoquePorTamanho != null) {
        updateData['estoquePorTamanho'] = novoEstoquePorTamanho;
      }

      transaction.update(produtoRef, updateData);

      final estoqueRef = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId);

      try {
        transaction.update(estoqueRef, updateData);
      } catch (_) {
        // estoque_produtos pode não existir para todos os produtos
      }

      debugPrint('[ESTOQUE-TX] ✅ Baixa atômica: $produtoNome -$quantidade');

      final slugVal = (data['slug'] ?? '').toString().trim();
      return EstoqueTransactionResult(
        produtoId: docId,
        produtoNome: produtoNome,
        produtoSlug: slugVal.isNotEmpty ? slugVal : null,
        quantidadeDebitada: quantidade,
        variacoesAtualizadas: novasVariacoes,
        estoquePorTamanhoAtualizado: novoEstoquePorTamanho,
        quantidadeTotalAtualizada: novaQuantidadeTotal,
      );
    }).timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'Conexão demorou muito. Verifique sua internet e tente novamente.',
      ),
    );
  }

  static Map<String, int> _parseMapStringInt(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, int>) return data;
    if (data is Map) {
      return data.map(
          (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0));
    }
    return {};
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

  static bool _temVariacaoSoloTamanho(Map<String, dynamic> variacoes) {
    for (final e in variacoes.entries) {
      if (e.key == 'sem-tamanho') continue;
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

  static int _somarVariacoes(Map<String, dynamic> variacoes) {
    int total = 0;
    for (final mapaTamanho in variacoes.values) {
      if (mapaTamanho is Map) {
        for (final qtd in mapaTamanho.values) {
          total += (qtd as num?)?.toInt() ?? 0;
        }
      }
    }
    return total;
  }

  /// Limite do Firestore: 500 operações por transação (~2 ops/item = 250 itens seguros)
  static const int _maxItensPorTransacao = 150;

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

    final resolvedItems = <({DocumentReference<Map<String, dynamic>> ref, int quantidade, String tamanho, String cor})>[];

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

      if (quantidade <= 0) continue;

      final ref = await _resolverProdutoRef(
        lojaId: lojaId,
        produtoId: produtoId,
        slug: slug,
        nome: nome,
      );
      if (ref == null) {
        throw Exception(
          'Produto não encontrado no servidor: ${produtoId ?? slug ?? nome}. '
          'Verifique se o produto foi sincronizado ou sua conexão com a internet.',
        );
      }
      resolvedItems.add((ref: ref, quantidade: quantidade, tamanho: tamanho, cor: cor));
    }

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
        if (temEstoquePorTamanho && tamanho.isEmpty) {
          throw Exception(
            'O produto "$produtoNome" possui estoque por tamanho. '
            'É obrigatório informar o TAMANHO na venda (ex.: P, M, G).',
          );
        }

        Map<String, dynamic>? novasVariacoes;
        Map<String, int>? novoEstoquePorTamanho;
        int novaQuantidadeTotal;

        if (temVariacaoSoloCor && cor.isNotEmpty) {
          final mapaCor = variacoes['sem-tamanho'];
          if (mapaCor == null || mapaCor is! Map) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome" na cor $cor. Disponível: 0, solicitado: $quantidade.',
            );
          }
          final mapa = Map<String, dynamic>.from(mapaCor);
          final disponivel = (mapa[cor] as num?)?.toInt() ?? 0;
          if (disponivel < quantidade) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome" na cor $cor. '
              'Disponível: $disponivel, solicitado: $quantidade.',
            );
          }
          mapa[cor] = disponivel - quantidade;
          if (mapa[cor] <= 0) mapa.remove(cor);
          novasVariacoes = Map<String, dynamic>.from(variacoes);
          novasVariacoes['sem-tamanho'] = mapa;
          if (mapa.isEmpty) novasVariacoes.remove('sem-tamanho');
          novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
        } else if (usaVariacoes && tamanho.isNotEmpty) {
          final chaveCor = cor.isEmpty ? 'sem-cor' : cor;
          final mapaTamanho = variacoes[tamanho];
          if (mapaTamanho == null || mapaTamanho is! Map) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome" no tamanho $tamanho${cor.isEmpty ? '' : ' - cor $cor'}. '
              'Disponível: 0, solicitado: $quantidade.',
            );
          }
          final mapaCor = Map<String, dynamic>.from(mapaTamanho);
          final disponivel = (mapaCor[chaveCor] as num?)?.toInt() ?? 0;
          if (disponivel < quantidade) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome" no tamanho $tamanho${cor.isEmpty ? '' : ' - cor $cor'}. '
              'Disponível: $disponivel, solicitado: $quantidade.',
            );
          }
          mapaCor[chaveCor] = disponivel - quantidade;
          if (mapaCor[chaveCor] <= 0) mapaCor.remove(chaveCor);
          novasVariacoes = Map<String, dynamic>.from(variacoes);
          novasVariacoes[tamanho] = mapaCor;
          if (mapaCor.isEmpty) novasVariacoes.remove(tamanho);
          novaQuantidadeTotal = _somarVariacoes(novasVariacoes);
        } else if (temEstoquePorTamanho && tamanho.isNotEmpty) {
          final disponivel = estoquePorTamanho[tamanho] ?? 0;

          if (disponivel < quantidade) {
            throw Exception(
              'Estoque insuficiente para "$produtoNome" no tamanho $tamanho. '
              'Disponível: $disponivel, solicitado: $quantidade.',
            );
          }

          novoEstoquePorTamanho = Map<String, int>.from(estoquePorTamanho);
          novoEstoquePorTamanho[tamanho] = disponivel - quantidade;
          if (novoEstoquePorTamanho[tamanho]! <= 0) {
            novoEstoquePorTamanho.remove(tamanho);
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

        final updateData = <String, dynamic>{
          'quantidade': novaQuantidadeTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (novasVariacoes != null) {
          updateData['variacoes'] = novasVariacoes;
        }
        if (novoEstoquePorTamanho != null) {
          updateData['estoquePorTamanho'] = novoEstoquePorTamanho;
        }

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
            estoquePorTamanhoAtualizado: novoEstoquePorTamanho,
            quantidadeTotalAtualizada: novaQuantidadeTotal,
          ),
        ));
      }

      // FASE 2: Todas as escritas (após todas as leituras)
      for (final u in updates) {
        transaction.update(u.ref, u.updateData);
        if (u.estoqueRef != null) {
          try {
            transaction.update(u.estoqueRef!, u.updateData);
          } catch (e) {
            debugPrint('[ESTOQUE-TX] ⚠️ Update estoqueRef falhou (doc pode não existir): ${e.runtimeType}');
          }
        }
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
      await produto.save();
      debugPrint('[ESTOQUE-TX] Hive atualizado: ${produto.nome}');
    }
  }
}
