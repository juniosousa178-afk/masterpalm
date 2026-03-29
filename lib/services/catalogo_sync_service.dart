// lib/services/catalogo_sync_service.dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart' show PlatformFile;

import '../core/hive_box_names.dart';
import '../src/blob_fetch_stub.dart' if (dart.library.html) '../src/blob_fetch_web.dart' as blob_fetch;
import '../models/produto.dart';
import 'catalog_cache_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/upload_manager.dart';

/// Alvos de sincronização:
///  - draft → lojas/{lojaId}/draft_produtos   (Public Catalog / rascunho)
///  - live  → lojas/{lojaId}/produtos         (Catalog Web / site)
enum SyncTarget { draft, live }

class CatalogoSyncService {
  CatalogoSyncService._();

  // ===============================================================
  // SDKs
  // ===============================================================
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseStorage get _storage => FirebaseStorage.instance;

  static final UploadManager _uploader = UploadManager(maxConcurrent: 3);

  // ===============================================================
  // Utils
  // ===============================================================
  static String slugify(String texto) {
    return texto
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Id do documento em `draft_produtos` / `produtos`: alinhado a
  /// [ProdutosFirestoreService.syncProduto] (`estoque_produtos`):
  /// `idFirebase` → `slug` → slug do nome. Não altera o conteúdo de [Produto.slug]
  /// nem injeta `lojaId` — só define qual chave de documento usar.
  static String catalogFirestoreDocId(Produto pdt) {
    final idFb = pdt.idFirebase.trim();
    if (idFb.isNotEmpty) return idFb;
    final sl = pdt.slug.trim();
    if (sl.isNotEmpty) return sl;
    return slugify(pdt.nome).trim();
  }

  static String _collectionName(SyncTarget t) =>
      t == SyncTarget.draft ? 'draft_produtos' : 'produtos';

  static String? _extFromMime(String? mime) {
    if (mime == null) return null;
    final m = mime.toLowerCase();
    if (m.contains('png')) return '.png';
    if (m.contains('jpeg') || m.contains('jpg')) return '.jpg';
    if (m.contains('webp')) return '.webp';
    return null;
  }

  static String? _mimeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e.endsWith('.png')) return 'image/png';
    if (e.endsWith('.jpg') || e.endsWith('.jpeg')) return 'image/jpeg';
    if (e.endsWith('.webp')) return 'image/webp';
    return null;
  }

  // ===============================================================
  // LojaId resolver (✅ evita "loja diferente")
  // ===============================================================
static Future<String> _resolveLojaId([String? lojaIdOverride]) async {
  if (lojaIdOverride != null && lojaIdOverride.trim().isNotEmpty) {
    return lojaIdOverride.trim();
  }
  
  final resolved = await StoreResolverFacade.resolveForAdminApp();
  if (resolved == null || resolved.isEmpty) {
    throw StateError('Nenhuma loja ativa para sincronização');
  }
  
  return resolved;
}
  // ===============================================================
  // Upload de imagem (local / base64 / url)
  // ===============================================================
  static Future<String> _uploadIfLocal(
    String pathStr, {
    required String lojaId,
    String? docIdForPath,
  }) async {
    if (pathStr.trim().isEmpty) return '';
    final trimmed = pathStr.trim();

    // URL pública
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    // Data URL (base64)
    if (trimmed.startsWith('data:image')) {
      try {
        final dataUri = Uri.parse(trimmed);
        final data = dataUri.data;
        if (data == null) return '';

        final bytes = Uint8List.fromList(data.contentAsBytes());
        final ext = _extFromMime(data.mimeType) ?? '.jpg';
        final name = '${DateTime.now().millisecondsSinceEpoch}$ext';

        final dest = 'lojas/$lojaId/produtos/${docIdForPath ?? "img"}/$name';

        final ref = _storage.ref(dest);
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: data.mimeType,
            cacheControl: 'public,max-age=31536000,immutable',
          ),
        );
        return await ref.getDownloadURL();
      } catch (_) {
        return '';
      }
    }

    // Web: blob: URL - buscar bytes e fazer upload
    if (kIsWeb && trimmed.toLowerCase().startsWith('blob:')) {
      try {
        final bytes = await blob_fetch.fetchBlobUrlAsBytes(trimmed);
        if (bytes == null || bytes.isEmpty) return '';
        final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final dest = 'lojas/$lojaId/produtos/${docIdForPath ?? "img"}/$name';
        final ref = _storage.ref(dest);
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'public,max-age=31536000,immutable',
          ),
        );
        return await ref.getDownloadURL();
      } catch (_) {
        return '';
      }
    }

    // Web não consegue ler path local (não-http, não-blob, não-data)
    if (kIsWeb) return '';

    // Android / Windows / Desktop
    final name = p.basename(trimmed);
    final ext = p.extension(name);
    final dest =
        'lojas/$lojaId/produtos/${docIdForPath ?? "img"}/${DateTime.now().millisecondsSinceEpoch}_$name';

    final pf = PlatformFile(
      name: name,
      path: trimmed,
      size: 0,
    );

    final result = await _uploader.enqueue(
      UploadRequest(
        platformFile: pf,
        storagePath: dest,
        metadata: SettableMetadata(
          contentType: _mimeFromExt(ext) ?? 'image/jpeg',
          cacheControl: 'public,max-age=31536000,immutable',
        ),
      ),
    );

    return result.downloadUrl;
  }

  // ===============================================================
  // Payload Firestore (catálogo)
  // ===============================================================
  static Future<Map<String, dynamic>> _buildCatalogData(
    Produto pdt,
    String docId, {
    required String lojaId,
  }) async {
    final imgs = <String>[];
    final seen = <String>{};

    for (final img in pdt.imagens) {
      final k = img.trim();
      if (k.isEmpty || seen.contains(k)) continue;
      seen.add(k);

      final url = await _uploadIfLocal(
        k,
        lojaId: lojaId,
        docIdForPath: docId,
      );
      if (url.isNotEmpty) imgs.add(url);
    }

    final slug =
        pdt.slug.trim().isNotEmpty ? pdt.slug.trim() : slugify(pdt.nome);
    final principal = imgs.isNotEmpty ? imgs.first : '';
    final preco = pdt.precoFinal.toDouble();
    // Preço por variação (opcional): se tiver, catálogo exibe faixa "R$ X a R$ Y"
    double priceMin = preco;
    double priceMax = preco;
    if (pdt.precoPorTamanho != null && pdt.precoPorTamanho!.isNotEmpty) {
      final precos = pdt.precoPorTamanho!.values.where((v) => v > 0).toList();
      if (precos.isNotEmpty) {
        priceMin = precos.reduce((a, b) => a < b ? a : b);
        priceMax = precos.reduce((a, b) => a > b ? a : b);
      }
    }

    return {
      'ativo': true,
      'publicar': pdt.publicadoNoCatalogo == true,
      'publicadoNoCatalogo': pdt.publicadoNoCatalogo == true,

      'id': docId,
      'nome': pdt.nome,
      'descricao': pdt.descricao,

      'preco': preco,
      'preco_venda': preco,
      'precoFinal': preco,
      'priceMin': priceMin,
      'priceMax': priceMax,

      'categoria': pdt.categoria,
      'categoriaId': pdt.categoria,
      'subcategoria': pdt.subcategoria,
      'subcategoriaId': pdt.subcategoria,

      'quantidade': pdt.quantidade,
      'estoque_atual': pdt.quantidade,
      'estoque': pdt.quantidade,
      'qtdEstoque': pdt.quantidade,
      'tamanhos': pdt.tamanhos,
      'estoquePorTamanho': pdt.estoquePorTamanho,
      'estoquePorCor': pdt.temVariacaoSoloCor ? pdt.estoquePorCor : null,
      'cores': pdt.cores,
      'variacoes': pdt.variacoes,
      if (pdt.precoPorTamanho != null && pdt.precoPorTamanho!.isNotEmpty)
        'precoPorTamanho': pdt.precoPorTamanho,
      'tipoProduto': pdt.tipoProduto,
      if (pdt.itensCombo != null && pdt.itensCombo!.isNotEmpty)
        'itensCombo': pdt.itensCombo,

      // Campos de promoção
      'emPromocao': pdt.emPromocao,
      'percentualPromo': pdt.percentualPromo,
      'valorPromo': pdt.valorPromo,
      'dataInicioPromo': pdt.dataInicioPromo?.toIso8601String(),
      'dataFimPromo': pdt.dataFimPromo?.toIso8601String(),
      'precoComPromocao': pdt.precoComPromocao,
      'promocaoAtiva': pdt.promocaoAtiva,

      'imagens': imgs,
      'images': imgs,
      'imgs': imgs,
      'fotos': imgs,

      'imagem_principal': principal,
      'imageUrl': principal,
      'thumbnail': principal,
      'cover': principal,

      'slug': slug,

      'divideSemJuros': pdt.divideSemJuros,
      'maxParcelasSemJuros': pdt.maxParcelasSemJuros,
      'percentualDescontoPix': pdt.percentualDescontoPix,

      'peso': pdt.peso,
      'tipoEmbalagem': pdt.tipoEmbalagem,
      'estoqueMinimo': pdt.estoqueMinimo,
      'marketplaces': pdt.marketplaces,
      if (pdt.codigoBarras.isNotEmpty) 'codigoBarras': pdt.codigoBarras,
      if (pdt.videoUrl.isNotEmpty) 'videoUrl': pdt.videoUrl,

      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // ===============================================================
  // Firestore helpers
  // ===============================================================
  static Future<void> _upsert(
    String lojaId,
    SyncTarget target,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await _db
        .collection('lojas')
        .doc(lojaId)
        .collection(_collectionName(target))
        .doc(docId)
        .set(data);  // ✅ Remove merge: true para substituir completamente
  }

  static Future<void> _remove(
    String lojaId,
    SyncTarget target,
    String docId,
  ) async {
    await _db
        .collection('lojas')
        .doc(lojaId)
        .collection(_collectionName(target))
        .doc(docId)
        .delete();
  }

  /// Remove documento legado do catálogo quando o id canônico passou a ser
  /// [Produto.idFirebase] e existia cópia antiga indexada só pelo [Produto.slug].
  static Future<void> _removeLegacySlugCatalogDocIfSameProduto({
    required String lojaId,
    required SyncTarget target,
    required Produto pdt,
    required String canonicalDocId,
  }) async {
    final leg = pdt.slug.trim();
    if (leg.isEmpty || leg == canonicalDocId) return;
    if (pdt.idFirebase.trim().isEmpty) return;
    try {
      final ref = _db
          .collection('lojas')
          .doc(lojaId)
          .collection(_collectionName(target))
          .doc(leg);
      final snap = await ref.get();
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final innerId = (data['id'] ?? '').toString().trim();
      final nome = (data['nome'] ?? '').toString().trim();
      if (innerId == leg &&
          nome.toLowerCase() == pdt.nome.trim().toLowerCase()) {
        await ref.delete();
        if (kDebugMode) {
          debugPrint(
            '🗑️ [PRODUTO SYNC] Removida duplicata legada $leg → canônico $canonicalDocId (${_collectionName(target)})',
          );
        }
      }
    } catch (_) {}
  }

  // ===============================================================
  // Sync de 1 produto
  // ===============================================================
  static Future<void> syncProduto(
    Produto pdt, {
    required SyncTarget target,
    bool removerSeSemEstoque = false,

    // ✅ força loja correta quando você já tem ela (LojaConfig / Admin etc)
    String? lojaIdOverride,
  }) async {
    final lojaId = await _resolveLojaId(lojaIdOverride);

    final docId = catalogFirestoreDocId(pdt);

    final publicado = pdt.publicadoNoCatalogo == true;
    // Combo: quantidade = quantos combos disponíveis; produto simples: quantidade em estoque
    final estoqueOk = !removerSeSemEstoque ||
        pdt.quantidade > 0 ||
        (pdt.ehCombo && publicado && pdt.quantidade >= 0);

    final deveExistir = target == SyncTarget.draft
        ? estoqueOk
        : (publicado && estoqueOk);

    if (kDebugMode) {
      debugPrint('📦 [PRODUTO SYNC] ${pdt.nome} → $docId');
    }

    if (!deveExistir) {
      if (kDebugMode) debugPrint('⚠️ [PRODUTO SYNC] Removendo: $docId');
      await _remove(lojaId, target, docId);
      await _removeLegacySlugCatalogDocIfSameProduto(
        lojaId: lojaId,
        target: target,
        pdt: pdt,
        canonicalDocId: docId,
      );
      return;
    }

    final data = await _buildCatalogData(
      pdt,
      docId,
      lojaId: lojaId,
    );

    await _upsert(lojaId, target, docId, data);
    await _removeLegacySlugCatalogDocIfSameProduto(
      lojaId: lojaId,
      target: target,
      pdt: pdt,
      canonicalDocId: docId,
    );
  }

  // ===============================================================
  // Sync de TODOS (otimizado: processamento em lotes paralelos)
  // ===============================================================
  static const int _batchSize = 6; // Produtos por lote (evita sobrecarga)

  static Future<void> syncAll({
    required SyncTarget target,
    bool removerSeSemEstoque = false,

    // ✅ força loja correta
    String? lojaIdOverride,
  }) async {
    final lojaId = await _resolveLojaId(lojaIdOverride);

    final boxName = HiveBoxNames.produtos(lojaId);
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Produto>(boxName);
    }
    final box = Hive.box<Produto>(boxName);

    final toSync = <Produto>[];
    final allowed = <String>{};

    for (final pdt in box.values) {
      final docId = catalogFirestoreDocId(pdt);

      final publicado = pdt.publicadoNoCatalogo == true;
      final estoqueOk = !removerSeSemEstoque ||
          pdt.quantidade > 0 ||
          (pdt.ehCombo && publicado);

      if (target == SyncTarget.draft) {
        if (estoqueOk) {
          allowed.add(docId);
          toSync.add(pdt);
        }
      } else {
        if (publicado && estoqueOk) {
          allowed.add(docId);
          toSync.add(pdt);
        }
      }
    }

    // Processa em lotes paralelos (mais rápido que sequencial)
    for (var i = 0; i < toSync.length; i += _batchSize) {
      final batch = toSync.skip(i).take(_batchSize).toList();
      await Future.wait(batch.map((pdt) => syncProduto(
        pdt,
        target: target,
        removerSeSemEstoque: removerSeSemEstoque,
        lojaIdOverride: lojaId,
      )));
    }

    // Remove do Firestore os que não estão mais no allowed
    final col = _db
        .collection('lojas')
        .doc(lojaId)
        .collection(_collectionName(target));

    final snap = await col.get();
    final toRemove = snap.docs.where((d) => !allowed.contains(d.id)).toList();
    if (toRemove.isNotEmpty) {
      await Future.wait(toRemove.map((d) => _remove(lojaId, target, d.id)));
    }
  }

  // ===============================================================
  // Atalhos
  // ===============================================================
  static Future<void> pushAllToDraft({String? lojaIdOverride}) =>
      syncAll(target: SyncTarget.draft, lojaIdOverride: lojaIdOverride);

  static Future<void> pushAllToLive({String? lojaIdOverride}) =>
      syncAll(
        target: SyncTarget.live,
        removerSeSemEstoque: true, // ✅ Remove produtos sem estoque do catálogo LIVE
        lojaIdOverride: lojaIdOverride,
      );

  // ---------------------------------------------------------------------------
  // 🔁 ALIASES DE COMPATIBILIDADE (CÓDIGO LEGADO)
  // ---------------------------------------------------------------------------

  /// Compat com telas antigas (ProdutoForm, EstoqueScreen, etc)
  /// Faz UPSERT no DRAFT por padrão
  static Future<void> upsertFromProduto(
    Produto produto, {
    SyncTarget target = SyncTarget.draft,
    bool removerSeSemEstoque = false,
    String? lojaIdOverride,
  }) async {
    await syncProduto(
      produto,
      target: target,
      removerSeSemEstoque: removerSeSemEstoque,
      lojaIdOverride: lojaIdOverride,
    );
  }

  /// Compat com telas antigas
  /// Remove produto pelo slug/nome no catálogo
  static Future<void> removeBySlug(
    String slugOuNome, {
    SyncTarget target = SyncTarget.live,
    String? lojaIdOverride,
  }) async {
    final lojaId = await _resolveLojaId(lojaIdOverride);
    final docId = slugify(slugOuNome);

    final base = _db.collection('lojas').doc(lojaId);
    final ref = base.collection(_collectionName(target)).doc(docId);

    debugPrint('🗑️ Firestore DELETE → ${ref.path}');
    await ref.delete();
  }

  // ---------------------------------------------------------------------------
  // ✅ COMPAT com o LojaConfig: CatalogoSyncService.pushAll(lojaId)
  // ---------------------------------------------------------------------------
  static Future<void> pushAll(
    String lojaId, {
    bool removerSeSemEstoque = false,
  }) =>
      pushAllToLive(lojaIdOverride: lojaId);

  // ===============================================================
  // MÉTODOS AUXILIARES PARA AUTO-SYNC
  // ===============================================================

  /// Remove um produto específico do Firestore (id canônico + duplicata legada por slug).
  static Future<void> removeProdutoFromFirestore(
    Produto pdt, {
    required SyncTarget target,
    String? lojaIdOverride,
  }) async {
    try {
      final lojaId = await _resolveLojaId(lojaIdOverride);
      final colName = _collectionName(target);
      final base = _db.collection('lojas').doc(lojaId).collection(colName);

      final docId = catalogFirestoreDocId(pdt);
      await base.doc(docId).delete();

      final leg = pdt.slug.trim();
      if (leg.isNotEmpty && leg != docId) {
        try {
          await base.doc(leg).delete();
        } catch (_) {}
      }

      debugPrint('🗑️ [PRODUTO SYNC] Removido do Firestore: lojas/$lojaId/$colName/$docId');
    } catch (e) {
      debugPrint('❌ [PRODUTO SYNC] Erro ao remover produto (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Identifica no Firestore (produtos + draft_produtos) os docs que não existem
  /// mais no cadastro de estoque (Hive). Retorna lista de {id, nome} para exibição.
  static Future<List<Map<String, String>>> identificarProdutosOrfaos({
    required String lojaId,
    required Box<Produto> produtosBox,
  }) async {
    final validDocIds = <String>{};
    for (final p in produtosBox.values) {
      final docId = catalogFirestoreDocId(p);
      if (docId.isNotEmpty) validDocIds.add(docId);
    }

    final base = _db.collection('lojas').doc(lojaId);
    final orfaos = <Map<String, String>>[];
    final seenIds = <String>{};

    for (final colName in ['produtos', 'draft_produtos']) {
      final snap = await base.collection(colName).get();
      for (final doc in snap.docs) {
        if (!validDocIds.contains(doc.id) && !seenIds.contains(doc.id)) {
          seenIds.add(doc.id);
          final data = doc.data();
          final nome = (data['nome'] ?? data['name'] ?? doc.id).toString().trim();
          orfaos.add({'id': doc.id, 'nome': nome.isEmpty ? doc.id : nome});
        }
      }
    }

    return orfaos;
  }

  /// Exclui do Firestore os docs órfãos pelos ids retornados em [identificarProdutosOrfaos].
  static Future<int> excluirProdutosOrfaosPorIds({
    required String lojaId,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty) return 0;

    final base = _db.collection('lojas').doc(lojaId);
    var removidos = 0;

    for (final colName in ['produtos', 'draft_produtos']) {
      final col = base.collection(colName);
      for (final id in docIds) {
        try {
          await col.doc(id).delete();
          removidos++;
          if (kDebugMode) {
            debugPrint('🗑️ [ÓRFÃOS] Removido: $colName/$id');
          }
        } catch (_) {}
      }
    }

    if (removidos > 0) {
      CatalogCacheService.invalidate(lojaId, preview: false);
      CatalogCacheService.invalidate(lojaId, preview: true);
    }

    return removidos;
  }

  /// Remove produto por key (quando não temos mais o objeto Produto)
  static Future<void> removeProdutoByKey(
    String productKey, {
    required String lojaId,
  }) async {
    try {
      // Remove de draft e live
      final draftCol = _db.collection('lojas').doc(lojaId).collection('draft_produtos');
      final liveCol = _db.collection('lojas').doc(lojaId).collection('produtos');

      // Tenta localizar e deletar em ambas coleções
      final draftQuery = await draftCol.where('id', isEqualTo: productKey).limit(1).get();
      for (final doc in draftQuery.docs) {
        await doc.reference.delete();
        debugPrint('🗑️ [PRODUTO SYNC] Removido de draft: ${doc.id}');
      }

      final liveQuery = await liveCol.where('id', isEqualTo: productKey).limit(1).get();
      for (final doc in liveQuery.docs) {
        await doc.reference.delete();
        debugPrint('🗑️ [PRODUTO SYNC] Removido de live: ${doc.id}');
      }
    } catch (e) {
      debugPrint('❌ [PRODUTO SYNC] Erro ao remover por key (type=${e.runtimeType})');
    }
  }
}
