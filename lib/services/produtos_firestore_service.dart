// lib/services/produtos_firestore_service.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';

import '../core/hive_box_names.dart';
import 'firestore_paths.dart';
import '../core/logger.dart';
import 'package:hive/hive.dart';
import '../models/produto.dart';
import 'produto_auto_sync_service.dart';
import 'store_resolver_facade.dart';
import 'catalog_thumbnail_service.dart';
import 'image_upload_service.dart';
import 'sync_queue_service.dart';
import '../src/blob_fetch_stub.dart' if (dart.library.html) '../src/blob_fetch_web.dart' as blob_fetch;

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
class ProdutosFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sincroniza um produto para o Firestore (Hive → Firestore)
  static Future<void> syncProduto(Produto produto, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) {
        logD('❌ [PRODUTOS-SYNC] LojaId vazio, não pode sincronizar');
        return;
      }

      final produtoId = produto.idFirebase.isNotEmpty
          ? produto.idFirebase
          : produto.slug.isNotEmpty
              ? produto.slug
              : DateTime.now().millisecondsSinceEpoch.toString();

      // 📸 Fazer upload das imagens locais para Firebase Storage
      final imagensFinais = <String>[];
      bool imagensAtualizadas = false;

      for (final imagemPath in produto.imagens) {
        if (ImageUploadService.isLocalPath(imagemPath)) {
          logD('📤 [PRODUTOS-SYNC] Fazendo upload da imagem: $imagemPath');
          String? url;
          final thumbBytes = await CatalogThumbnailService.generateFromPath(imagemPath);
          if (thumbBytes != null) {
            url = await ImageUploadService.uploadImageFromBytes(
              bytes: thumbBytes,
              folder: 'produtos',
              lojaId: storeId,
            );
          }
          url ??= await ImageUploadService.uploadImage(
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
              final bytes = await blob_fetch.fetchBlobUrlAsBytes(imagemPath)
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
                  logD('[PRODUTOS-SYNC] blob: URL convertida para Firebase: $url');
                }
              }
            } catch (_) {
              logW('[PRODUTOS-SYNC] blob: falha ao converter: $imagemPath');
            }
          }
          if (!blobConvertido) {
            logW('[PRODUTOS-SYNC] blob: URL ignorada (não persiste fora do browser): $imagemPath');
          }
        } else {
          imagensFinais.add(imagemPath);
        }
      }

      // Se as imagens foram atualizadas, salvar no produto local
      if (imagensAtualizadas) {
        produto.imagens = imagensFinais;
        await produto.save();
        logD('✅ [PRODUTOS-SYNC] Imagens atualizadas no Hive com URLs do Firebase');
      }

      produto.updatedAt = DateTime.now();
      await produto.save();

      final produtoData = {
        'id': produtoId,
        'lojaId': storeId,
        'nome': produto.nome,
        'preco': produto.precoFinal,
        'quantidade': produto.quantidade,
        'categoria': produto.categoria,
        'subcategoria': produto.subcategoria,
        'descricao': produto.descricao,
        'imagens': imagensFinais, // ✅ Usa URLs do Firebase
        'slug': produto.slug,
        'tamanhos': produto.tamanhos,
        'estoquePorTamanho': produto.estoquePorTamanho,
        'publicadoNoCatalogo': produto.publicadoNoCatalogo,
        'custoReal': produto.custoReal,
        'precoUnitario': produto.precoUnitario,
        'frete': produto.frete,
        'gastosFixos': produto.gastosFixos,
        'gastosVariaveis': produto.gastosVariaveis,
        'precoSugerido': produto.precoSugerido,
        'peso': produto.peso,
        'tipoEmbalagem': produto.tipoEmbalagem,

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

        // Variações (tamanho + cor)
        'cores': produto.cores,
        'variacoes': produto.variacoes,
        if (produto.precoPorTamanho != null && produto.precoPorTamanho!.isNotEmpty)
          'precoPorTamanho': produto.precoPorTamanho,
        'tipoProduto': produto.tipoProduto,
        if (produto.itensCombo != null && produto.itensCombo!.isNotEmpty)
          'itensCombo': produto.itensCombo,

        'divideSemJuros': produto.divideSemJuros,
        'percentualDescontoPix': produto.percentualDescontoPix,
        'maxParcelasSemJuros': produto.maxParcelasSemJuros,

        'videoUrl': produto.videoUrl.isNotEmpty ? produto.videoUrl : null,
        'codigoBarras': produto.codigoBarras.isNotEmpty ? produto.codigoBarras : null,
        'estoqueMinimo': produto.estoqueMinimo,

        // Metadata
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .set(produtoData);  // ✅ Remove merge: true para substituir completamente

      // 🔹 TAMBÉM atualizar no catálogo público (produtos) se o produto está publicado
      if (produto.publicadoNoCatalogo) {
        try {
          await _db
              .collection('lojas')
              .doc(storeId)
              .collection('produtos')
              .doc(produtoId)
              .update({
            'quantidade': produto.quantidade,
            'variacoes': produto.variacoes,
            'estoquePorTamanho': produto.estoquePorTamanho,
            'cores': produto.cores,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          logD('✅ [PRODUTOS-SYNC] Estoque atualizado no catálogo público');
        } catch (e) {
          logW('⚠️ [PRODUTOS-SYNC] Produto não encontrado no catálogo público (normal se não publicado) (type=${e.runtimeType})');
        }
      }

      // Atualizar idFirebase no produto local se estava vazio
      if (produto.idFirebase.isEmpty) {
        produto.idFirebase = produtoId;
        await produto.save();
        logD('🔄 [PRODUTOS-SYNC] idFirebase atualizado: $produtoId');
      }

      logD('✅ [PRODUTOS-SYNC] Produto ${produto.nome} sincronizado');
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro ao sincronizar produto (type=${e.runtimeType})', error: e, st: st);
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      final key = produto.key;
      final boxName = produto.box?.name ?? (storeId != null ? HiveBoxNames.produtos(storeId) : null);
      if (storeId != null && key != null && boxName != null) {
        await SyncQueueService.enqueue(
          type: SyncOperationType.upsertProduto,
          lojaId: storeId,
          boxName: boxName,
          entityKey: key is int ? key : int.tryParse(key.toString()) ?? 0,
        );
      }
    }
  }

  static bool _isDataImageUrl(String? s) =>
      s != null && s.trim().startsWith('data:image');

  static bool _isBlobUrl(String? s) =>
      s != null && s.trim().toLowerCase().startsWith('blob:');

  static Future<String?> _uploadDataImageUrl(String dataUrl, String lojaId) async {
    try {
      final uri = Uri.parse(dataUrl.trim());
      final data = uri.data;
      if (data == null) return null;
      final bytes = Uint8List.fromList(data.contentAsBytes());
      final ext = data.mimeType.split('/').last;
      final path = 'lojas/$lojaId/produtos/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(
        bytes,
        SettableMetadata(contentType: data.mimeType),
      );
      return await ref.getDownloadURL();
    } catch (e) {
      logE('[PRODUTOS-SYNC] Erro ao fazer upload de data:image (type=${e.runtimeType})');
      return null;
    }
  }

  /// Sincroniza todos os produtos locais para o Firestore (Hive → Firestore)
  static Future<void> syncTodosProdutos({required String boxName, required String lojaId}) async {
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
            logE('❌ [PRODUTOS-SYNC] Erro no produto (type=${e.runtimeType})', error: e, st: st);
          }
        }
      }

      logD('✅ [PRODUTOS-SYNC] Sync completo: $synced produtos sincronizados, $errors erros');
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro geral (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Sincroniza produtos do Firestore para o Hive (Firestore → Hive)
  /// Usa paginação para buscar TODOS os produtos (evita limit 1000 cortar a lista).
  static Future<int> syncFirestoreToHive({
    required String lojaId,
    required Box<Produto> produtosBox,
  }) async {
    ProdutoAutoSyncService.setApplyingRemoteSync(true);
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

      logD('📦 [PRODUTOS-SYNC] Encontrados ${allDocs.length} produtos no Firestore');

      int sincronizados = 0;
      int atualizados = 0;

      for (final doc in allDocs) {
        try {
          final data = doc.data();
          final produtoId = doc.id;

          // Buscar se já existe no Hive pelo idFirebase OU pelo slug
          final slug = data['slug'] ?? '';
          Produto? produtoExistente;

          // Primeiro tenta por idFirebase
          try {
            produtoExistente = produtosBox.values.firstWhere(
              (p) => p.idFirebase == produtoId && p.lojaId == lojaId,
            );
          } catch (_) {
            // Se não encontrou por idFirebase, tenta por slug
            if (slug.isNotEmpty) {
              try {
                produtoExistente = produtosBox.values.firstWhere(
                  (p) => p.slug == slug && p.lojaId == lojaId,
                );
              } catch (_) {}
            }
          }

          if (produtoExistente != null) {
            // Atualizar produto existente com todos os dados do Firestore,
            // para que alterações feitas em outro aparelho (custo, peso, etc.) apareçam aqui.
            final p = produtoExistente;
            p.nome = data['nome'] ?? p.nome;
            p.precoFinal = (data['preco'] as num?)?.toDouble() ?? p.precoFinal;
            p.quantidade = (data['quantidade'] as num?)?.toInt() ?? p.quantidade;
            p.custoReal = (data['custoReal'] as num?)?.toDouble() ?? p.custoReal;
            p.frete = (data['frete'] as num?)?.toDouble() ?? p.frete;
            p.gastosFixos = (data['gastosFixos'] as num?)?.toDouble() ?? p.gastosFixos;
            p.gastosVariaveis = (data['gastosVariaveis'] as num?)?.toDouble() ?? p.gastosVariaveis;
            p.precoSugerido = (data['precoSugerido'] as num?)?.toDouble() ?? p.precoSugerido;
            p.peso = (data['peso'] as num?)?.toDouble() ?? p.peso;
            p.tipoEmbalagem = (data['tipoEmbalagem'] ?? p.tipoEmbalagem).toString();
            p.categoria = data['categoria'] ?? p.categoria;
            p.subcategoria = data['subcategoria'] ?? p.subcategoria;
            p.descricao = data['descricao'] ?? p.descricao;
            p.imagens = (data['imagens'] as List?)?.cast<String>() ?? p.imagens;
            p.slug = data['slug'] ?? p.slug;
            p.codigoBarras = (data['codigoBarras'] ?? p.codigoBarras ?? '').toString();
            p.estoqueMinimo = (data['estoqueMinimo'] is num) ? (data['estoqueMinimo'] as num).toInt() : p.estoqueMinimo;
            p.publicadoNoCatalogo = data['publicadoNoCatalogo'] ?? p.publicadoNoCatalogo;
            p.tamanhos = (data['tamanhos'] as List?)?.cast<String>() ?? p.tamanhos;
            p.estoquePorTamanho = Map<String, int>.from(data['estoquePorTamanho'] ?? p.estoquePorTamanho);
            p.cores = (data['cores'] as List?)?.cast<String>() ?? p.cores;
            final varData = data['variacoes'];
            if (varData != null && varData is Map) {
              p.variacoes = _parseVariacoesFromFirestore(varData);
            }
            final ppt = data['precoPorTamanho'];
            if (ppt != null && ppt is Map) {
              p.precoPorTamanho = Map<String, double>.from(
                ppt.map((k, v) => MapEntry(k.toString(), (v is num) ? v.toDouble() : 0.0)),
              );
            } else if (ppt == null) {
              p.precoPorTamanho = null;
            }
            p.precoUnitario = (data['precoUnitario'] as num?)?.toDouble() ?? (data['preco'] as num?)?.toDouble() ?? p.precoUnitario;
            p.tipoProduto = (data['tipoProduto'] ?? p.tipoProduto).toString();
            final itc = data['itensCombo'];
            if (itc != null && itc is List && itc.isNotEmpty) {
              p.itensCombo = itc.map((e) {
                if (e is Map) {
                  return Map<String, dynamic>.from(Map.from(e));
                }
                return <String, dynamic>{};
              }).where((m) => (m['nome'] ?? '').toString().isNotEmpty).toList();
            } else if (itc == null) {
              p.itensCombo = null;
            }
            p.divideSemJuros = data['divideSemJuros'] ?? p.divideSemJuros;
            p.percentualDescontoPix = (data['percentualDescontoPix'] is num)
                ? (data['percentualDescontoPix'] as num).toDouble()
                : p.percentualDescontoPix;
            p.maxParcelasSemJuros = (data['maxParcelasSemJuros'] is num)
                ? (data['maxParcelasSemJuros'] as num).toInt()
                : p.maxParcelasSemJuros;
            final updatedAt = data['updatedAt'];
            if (updatedAt != null && updatedAt is Timestamp) {
              p.updatedAt = updatedAt.toDate();
            }
            if (p.idFirebase.isEmpty) {
              p.idFirebase = produtoId;
            }
            await p.save();
            atualizados++;
            logD('🔄 Produto $produtoId atualizado');
          } else {
            // Criar novo produto
            final uAt = data['updatedAt'];
            final updatedAtDt = uAt != null && uAt is Timestamp ? uAt.toDate() : null;
            final produto = Produto(
              idFirebase: produtoId,
              nome: data['nome'] ?? 'Produto sem nome',
              custoReal: (data['custoReal'] as num?)?.toDouble() ?? 0.0,
              frete: (data['frete'] as num?)?.toDouble() ?? 0.0,
              gastosFixos: (data['gastosFixos'] as num?)?.toDouble() ?? 0.0,
              gastosVariaveis: (data['gastosVariaveis'] as num?)?.toDouble() ?? 0.0,
              precoSugerido: (data['precoSugerido'] as num?)?.toDouble() ?? (data['preco'] as num?)?.toDouble() ?? 0.0,
              precoFinal: (data['preco'] as num?)?.toDouble() ?? 0.0,
              precoUnitario: (data['precoUnitario'] as num?)?.toDouble() ?? (data['preco'] as num?)?.toDouble() ?? 0.0,
              quantidade: (data['quantidade'] as num?)?.toInt() ?? 0,
              categoria: data['categoria'] ?? '',
              dataEntrada: DateTime.now(),
              descricao: data['descricao'] ?? '',
              imagens: (data['imagens'] as List?)?.cast<String>() ?? [],
              slug: data['slug'] ?? '',
              lojaId: lojaId,
              subcategoria: data['subcategoria'] ?? '',
              publicadoNoCatalogo: data['publicadoNoCatalogo'] ?? false,
              tamanhos: (data['tamanhos'] as List?)?.cast<String>() ?? [],
              estoquePorTamanho: Map<String, int>.from(data['estoquePorTamanho'] ?? {}),
              cores: (data['cores'] as List?)?.cast<String>() ?? [],
              variacoes: _parseVariacoesFromFirestore(data['variacoes']),
              precoPorTamanho: _parsePrecoPorTamanhoFromFirestore(data['precoPorTamanho']),
              tipoProduto: (data['tipoProduto'] ?? 'simples').toString(),
              itensCombo: _parseItensComboFromFirestore(data['itensCombo']),
              divideSemJuros: data['divideSemJuros'] == true,
              percentualDescontoPix: (data['percentualDescontoPix'] is num)
                  ? (data['percentualDescontoPix'] as num).toDouble()
                  : 0.0,
              maxParcelasSemJuros: (data['maxParcelasSemJuros'] is num)
                  ? (data['maxParcelasSemJuros'] as num).toInt()
                  : 12,
              codigoBarras: (data['codigoBarras'] ?? '').toString(),
              estoqueMinimo: (data['estoqueMinimo'] is num) ? (data['estoqueMinimo'] as num).toInt() : 0,
              peso: (data['peso'] as num?)?.toDouble() ?? 0.0,
              tipoEmbalagem: (data['tipoEmbalagem'] ?? 'padrao').toString(),
              updatedAt: updatedAtDt,
            );

            await produtosBox.add(produto);
            sincronizados++;
            logD('✅ Produto $produtoId sincronizado');
          }
        } catch (e, st) {
          logE('❌ [PRODUTOS-SYNC] Erro ao sincronizar produto (type=${e.runtimeType})', error: e, st: st);
        }
      }

      // Remover locais que não existem mais no Firestore (excluídos em outro aparelho)
      final firestoreIds = allDocs.map((d) => d.id).toSet();
      final toRemove = <int>[];
      for (final k in produtosBox.keys) {
        final p = produtosBox.get(k);
        if (p != null && p.lojaId == lojaId && p.idFirebase.isNotEmpty && !firestoreIds.contains(p.idFirebase)) {
          toRemove.add(k as int);
        }
      }
      for (final k in toRemove) {
        await produtosBox.delete(k);
        logD('🗑️ [PRODUTOS-SYNC] Produto local removido (excluído no Firestore): $k');
      }

      logD('✅ [PRODUTOS-SYNC] Sync completo: $sincronizados novos, $atualizados atualizados, ${toRemove.length} removidos');
      return sincronizados + atualizados;
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro ao sincronizar do Firestore (type=${e.runtimeType})', error: e, st: st);
      return 0;
    } finally {
      ProdutoAutoSyncService.setApplyingRemoteSync(false);
    }
  }

  static List<Map<String, dynamic>>? _parseItensComboFromFirestore(dynamic data) {
    if (data == null || data is! List || data.isEmpty) return null;
    final result = <Map<String, dynamic>>[];
    for (final e in data) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(Map.from(e));
      if ((m['nome'] ?? '').toString().trim().isEmpty) continue;
      result.add(m);
    }
    return result.isEmpty ? null : result;
  }

  /// Converte mapa precoPorTamanho vindo do Firestore para Map<String, double>.
  static Map<String, double>? _parsePrecoPorTamanhoFromFirestore(dynamic data) {
    if (data == null || data is! Map) return null;
    final result = <String, double>{};
    for (final entry in data.entries) {
      final k = entry.key?.toString() ?? '';
      if (k.isEmpty) continue;
      final v = entry.value is num ? (entry.value as num).toDouble() : 0.0;
      if (v > 0) result[k] = v;
    }
    return result.isEmpty ? null : result;
  }

  /// Converte mapa de variações vindo do Firestore para Map<String, dynamic> (tamanho -> { cor -> qtd }).
  static Map<String, dynamic>? _parseVariacoesFromFirestore(dynamic varData) {
    if (varData == null || varData is! Map) return null;
    final result = <String, dynamic>{};
    for (final entry in varData.entries) {
      final tamanho = entry.key?.toString() ?? '';
      if (tamanho.isEmpty) continue;
      final inner = entry.value;
      if (inner is! Map) continue;
      final mapaCorQtd = <String, int>{};
      for (final e in inner.entries) {
        final cor = e.key?.toString() ?? '';
        final qtd = e.value is num ? (e.value as num).toInt() : int.tryParse(e.value?.toString() ?? '') ?? 0;
        if (cor.isNotEmpty) mapaCorQtd[cor] = qtd;
      }
      if (mapaCorQtd.isNotEmpty) result[tamanho] = mapaCorQtd;
    }
    return result.isEmpty ? null : result;
  }

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
        updateData['variacoes'] = variacoes;
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

      logD('✅ [PRODUTOS-SYNC] Quantidade atualizada: $produtoId = $novaQuantidade');
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro ao atualizar quantidade (type=${e.runtimeType})', error: e, st: st);
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
      logE('❌ [PRODUTOS-SYNC] Erro ao verificar dados para importar (type=${e.runtimeType})', error: e, st: st);
      return false;
    }
  }

  /// Remove do Firestore os produtos que NÃO estão no estoque local.
  /// Use quando o estoque local (406) é a fonte da verdade e o Firestore tem produtos a mais (ex: 1000).
  static Future<int> limparProdutosExcedentesNoFirestore({
    required String lojaId,
    required Box<Produto> produtosBox,
  }) async {
    try {
      final idsLocais = produtosBox.values
          .where((p) => p.lojaId == lojaId && p.idFirebase.isNotEmpty)
          .map((p) => p.idFirebase)
          .toSet();

      const batchSize = 500;
      final toDelete = <String>[];
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
        for (final doc in snapshot.docs) {
          if (!idsLocais.contains(doc.id)) {
            toDelete.add(doc.id);
          }
        }
        if (snapshot.docs.length < batchSize) break;
        lastDoc = snapshot.docs.last;
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
        logD('🗑️ [PRODUTOS-SYNC] ${toDelete.length} produto(s) excedente(s) removido(s) do Firestore');
      }
      return toDelete.length;
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro ao limpar excedentes (type=${e.runtimeType})', error: e, st: st);
      return 0;
    }
  }

  /// Deleta um produto do Firestore
  static Future<void> deleteProduto(String produtoId, {String? lojaId}) async {
    try {
      final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
      if (storeId == null || storeId.isEmpty) return;

      await _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId)
          .delete();

      logD('🗑️ [PRODUTOS-SYNC] Produto $produtoId deletado do Firestore');
    } catch (e, st) {
      logE('❌ [PRODUTOS-SYNC] Erro ao deletar produto (type=${e.runtimeType})', error: e, st: st);
    }
  }
}
