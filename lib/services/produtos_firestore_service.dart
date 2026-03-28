// lib/services/produtos_firestore_service.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';

import '../core/hive_box_names.dart';
import 'firestore_paths.dart';
import '../core/logger.dart';
import 'package:hive/hive.dart';
import '../models/produto.dart';
import 'catalogo_sync_service.dart';
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

  static void _dlog(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(msg);
    }
  }

  /// Sincroniza um produto para o Firestore (Hive → Firestore).
  ///
  /// Chamado após salvar no cadastro (produto/combo/catálogo), import e fluxos que alteram
  /// o registro manualmente — mantém a nuvem alinhada à edição local.
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

      final docRef = _db
          .collection('lojas')
          .doc(storeId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(produtoId);
      final docSnap = await docRef.get();
      final existingData = docSnap.data();
      final dynamic createdAtPersistido = existingData?['createdAt'];

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
        'fornecedor': produto.fornecedor.isNotEmpty ? produto.fornecedor : null,
        'marketplaces': produto.marketplaces,
        // Campos internos úteis para continuidade multi-dispositivo (admin)
        'dataEntrada': Timestamp.fromDate(produto.dataEntrada),
        'ativoNoRascunho': produto.ativoNoRascunho,

        // Metadata
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (docSnap.exists) {
        if (createdAtPersistido != null) {
          produtoData['createdAt'] = createdAtPersistido;
        } else {
          // Fallback conservador para docs legados sem createdAt.
          produtoData['createdAt'] = FieldValue.serverTimestamp();
        }
        _dlog('[ProdutoSync] update estoque_produtos/$produtoId (createdAt preservado)');
      } else {
        produtoData['createdAt'] = FieldValue.serverTimestamp();
        _dlog('[ProdutoSync] create estoque_produtos/$produtoId');
      }

      await docRef.set(produtoData, SetOptions(merge: true));

      // 🔹 TAMBÉM atualizar no catálogo público (produtos) se o produto está publicado
      if (produto.publicadoNoCatalogo) {
        try {
          final publicoRef = _db
              .collection('lojas')
              .doc(storeId)
              .collection('produtos')
              .doc(produtoId);
          await publicoRef.set({
            'nome': produto.nome,
            'descricao': produto.descricao,
            'preco': produto.precoFinal,
            'preco_venda': produto.precoFinal,
            'precoFinal': produto.precoFinal,
            'quantidade': produto.quantidade,
            'estoque': produto.quantidade,
            'imagens': imagensFinais,
            'slug': produto.slug,
            'variacoes': produto.variacoes,
            'estoquePorTamanho': produto.estoquePorTamanho,
            'cores': produto.cores,
            if (produto.precoPorTamanho != null &&
                produto.precoPorTamanho!.isNotEmpty)
              'precoPorTamanho': produto.precoPorTamanho,
            'emPromocao': produto.emPromocao,
            'percentualPromo': produto.percentualPromo,
            'valorPromo': produto.valorPromo,
            'peso': produto.peso,
            'tipoEmbalagem': produto.tipoEmbalagem,
            'codigoBarras': produto.codigoBarras.isNotEmpty
                ? produto.codigoBarras
                : null,
            'estoqueMinimo': produto.estoqueMinimo,
            // Campos internos/admin nunca no documento público
            'fornecedor': FieldValue.delete(),
            'frete': FieldValue.delete(),
            'gastosFixos': FieldValue.delete(),
            'gastosVariaveis': FieldValue.delete(),
            'precoSugerido': FieldValue.delete(),
            'custoEditadoNoCadastro': FieldValue.delete(),
            'dataEntrada': FieldValue.delete(),
            'ativoNoRascunho': FieldValue.delete(),
            'marketplaces': produto.marketplaces,
            'divideSemJuros': produto.divideSemJuros,
            'maxParcelasSemJuros': produto.maxParcelasSemJuros,
            'percentualDescontoPix': produto.percentualDescontoPix,
            if (produto.videoUrl.isNotEmpty) 'videoUrl': produto.videoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          _dlog('[ProdutoPublico] upsert produtos/$produtoId concluído');
          logD('✅ [PRODUTOS-SYNC] Catálogo público (produtos) atualizado');
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
        logE('❌ [PRODUTOS-SYNC] Erro sync item hiveKey=$k (type=${e.runtimeType})', error: e, st: st);
      }
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

  /// Aplica apenas campos de **estoque** do snapshot remoto (vendas catálogo, Nova Venda,
  /// transações em outro aparelho). Não altera nome, preço, descrição, imagens, etc.
  static void _aplicarSomenteEstoqueDoRemoto(Produto p, Map<String, dynamic> data) {
    p.estoquePorTamanho = Map<String, int>.from(
      data['estoquePorTamanho'] ?? p.estoquePorTamanho,
    );
    final varData = data['variacoes'];
    if (varData != null && varData is Map) {
      p.variacoes = _parseVariacoesFromFirestore(varData);
    }
    p.quantidade = (data['quantidade'] as num?)?.toInt() ?? p.quantidade;
  }

  /// Hive com [updatedAt] mais recente que o documento remoto (evita sobrescrever
  /// qualquer campo editado localmente antes do upload terminar).
  static bool _localUpdatedAtNewerThanRemote(Produto p, Map<String, dynamic> data) {
    final local = p.updatedAt;
    final raw = data['updatedAt'];
    if (local == null) return false;
    if (raw == null || raw is! Timestamp) return false;
    final remote = raw.toDate();
    // Margem para diferença relógio aparelho vs servidor
    return local.isAfter(remote.subtract(const Duration(seconds: 15)));
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
            // Atualizar produto existente com dados do Firestore.
            final p = produtoExistente;
            final localMaisRecente = _localUpdatedAtNewerThanRemote(p, data);
            // Regra "última alteração vence": quando o local é mais recente,
            // preserva cadastro local e aplica somente estoque da nuvem.
            // Caso contrário, aplica snapshot remoto completo (inclui custo/peso).
            final skipRemoteMerge = localMaisRecente;

            if (skipRemoteMerge) {
              if ((data['custoReal'] is num) || (data['peso'] is num)) {
                final custoRemoto = (data['custoReal'] as num?)?.toDouble();
                final pesoRemoto = (data['peso'] as num?)?.toDouble();
                logD(
                  '[AUDIT_SYNC] Produto $produtoId preservou LOCAL (mais recente). '
                  'custo local=${p.custoReal.toStringAsFixed(2)} remoto=${(custoRemoto ?? p.custoReal).toStringAsFixed(2)} | '
                  'peso local=${p.peso.toStringAsFixed(2)} remoto=${(pesoRemoto ?? p.peso).toStringAsFixed(2)}',
                );
              }
              if (p.idFirebase.isEmpty) {
                p.idFirebase = produtoId;
              }
              if (p.slug.isEmpty && slug.isNotEmpty) {
                p.slug = slug.toString();
              }
              _aplicarSomenteEstoqueDoRemoto(p, data);
              await p.save();
              atualizados++;
              logD(
                '🔄 Produto $produtoId: cadastro local preservado; estoque aplicado da nuvem',
              );
              continue;
            }

            final custoAntes = p.custoReal;
            final pesoAntes = p.peso;
            p.nome = data['nome'] ?? p.nome;
            p.quantidade = (data['quantidade'] as num?)?.toInt() ?? p.quantidade;
            p.precoFinal = (data['preco'] as num?)?.toDouble() ?? p.precoFinal;
            p.custoReal = (data['custoReal'] as num?)?.toDouble() ?? p.custoReal;
            p.frete = (data['frete'] as num?)?.toDouble() ?? p.frete;
            p.gastosFixos = (data['gastosFixos'] as num?)?.toDouble() ?? p.gastosFixos;
            p.gastosVariaveis = (data['gastosVariaveis'] as num?)?.toDouble() ?? p.gastosVariaveis;
            p.precoSugerido = (data['precoSugerido'] as num?)?.toDouble() ?? p.precoSugerido;
            final ce = data['custoEditadoNoCadastro'];
            p.custoEditadoNoCadastro = ce is bool ? ce : false;
            p.peso = (data['peso'] as num?)?.toDouble() ?? p.peso;
            p.tipoEmbalagem = (data['tipoEmbalagem'] ?? p.tipoEmbalagem).toString();
            p.categoria = data['categoria'] ?? p.categoria;
            p.subcategoria = data['subcategoria'] ?? p.subcategoria;
            p.descricao = data['descricao'] ?? p.descricao;
            p.imagens = (data['imagens'] as List?)?.cast<String>() ?? p.imagens;
            p.slug = data['slug'] ?? p.slug;
            p.codigoBarras = (data['codigoBarras'] ?? p.codigoBarras ?? '').toString();
            p.estoqueMinimo = (data['estoqueMinimo'] is num) ? (data['estoqueMinimo'] as num).toInt() : p.estoqueMinimo;
            if (data['dataEntrada'] is Timestamp) {
              p.dataEntrada = (data['dataEntrada'] as Timestamp).toDate();
            }
            if (data.containsKey('ativoNoRascunho')) {
              p.ativoNoRascunho = data['ativoNoRascunho'] == true;
            }
            if (data.containsKey('fornecedor')) {
              p.fornecedor = (data['fornecedor'] ?? '').toString().trim();
            }
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
            if (data.containsKey('emPromocao')) {
              p.emPromocao = data['emPromocao'] == true;
            }
            if (data.containsKey('percentualPromo')) {
              p.percentualPromo = (data['percentualPromo'] as num?)?.toDouble();
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
            final updatedAt = data['updatedAt'];
            if (updatedAt != null && updatedAt is Timestamp) {
              p.updatedAt = updatedAt.toDate();
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
              dataEntrada: data['dataEntrada'] is Timestamp
                  ? (data['dataEntrada'] as Timestamp).toDate()
                  : DateTime.now(),
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

    final col = _db.collection('lojas').doc(lojaId).collection(FSPaths.estoqueProdutosCol);
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
      logD('[DELETE_FALLBACK] estoque removido docId=$d (idFirebase vazio, match forte)');
      return true;
    }

    if (await tryDeleteDoc(produto.slug)) return;
    final fromNome = CatalogoSyncService.slugify(produto.nome);
    if (await tryDeleteDoc(fromNome)) return;

    logW(
      '[DELETE_FALLBACK] Sem remoção em estoque_produtos (idFirebase vazio e sem match forte slug/barras/docId=slug) loja=$lojaId nome=${produto.nome}',
    );
  }
}
