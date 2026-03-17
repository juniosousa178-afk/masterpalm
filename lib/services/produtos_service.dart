import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/produto_firestore.dart';

/// Serviço de produtos com fluxo RASCUNHO → PUBLICADO.
/// Estrutura:
/// - lojas/{lojaId}/draft_config/config
/// - lojas/{lojaId}/config/config
/// - lojas/{lojaId}/draft_produtos/{produtoId}
/// - lojas/{lojaId}/produtos/{produtoId}
///
/// Campos de controle:
/// - ativo: bool
/// - publicar: bool
class ProdutosService {
  final _db = FirebaseFirestore.instance;

  // ===========================================================================
  // LOJA / IDENTIFICAÇÃO
  // ===========================================================================

  /// Resolve o lojaId a partir do slug.
  ///
  /// Tenta:
  /// 1) lojas/{slug}
  /// 2) lojas WHERE slug == slug
  Future<String?> getLojaIdBySlug(String slug) async {
    final trimmed = slug.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    // 1) tenta pelo ID do documento
    final direct = await _db.collection('lojas').doc(trimmed).get();
    if (direct.exists) {
      return direct.id;
    }

    // 2) tenta pelo campo 'slug'
    final q = await _db
        .collection('lojas')
        .where('slug', isEqualTo: trimmed)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      return q.docs.first.id;
    }

    return null;
  }

  // ===========================================================================
  // CONFIG (rascunho e publicada)
  // ===========================================================================

  /// Config em rascunho:
  /// lojas/{lojaId}/draft_config/config
  Stream<Map<String, dynamic>> streamLojaConfigDraft(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('draft_config')
        .doc('config')
        .snapshots()
        .map((d) => d.data() ?? {});
  }

  /// Config publicada:
  /// lojas/{lojaId}/config/config
  Stream<Map<String, dynamic>> streamLojaConfigLive(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('config')
        .snapshots()
        .map((d) => d.data() ?? {});
  }

  /// Compat: catálogo público hoje usa *prévia*, então aponta pro draft.
  Stream<Map<String, dynamic>> streamLojaConfig(String lojaId) {
    return streamLojaConfigDraft(lojaId);
  }

  // ===========================================================================
  // PRODUTOS (rascunho e publicados)
  // ===========================================================================

  /// Lista crua de produtos em rascunho (draft_produtos).
  Stream<List<Map<String, dynamic>>> streamProdutosDraftRaw(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('draft_produtos')
        .where('ativo', isEqualTo: true)
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Lista crua de produtos publicados (produtos).
  Stream<List<Map<String, dynamic>>> streamProdutosLiveRaw(String lojaId) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('produtos')
        .where('ativo', isEqualTo: true)
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  List<String> _toStringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String && v.trim().isNotEmpty) return [v.trim()];
    return const <String>[];
  }

  ProdutoFirestore _mapToProdutoFS(Map<String, dynamic> m) {
    Map<String, int> estoque(dynamic v) {
      if (v is Map) {
        return v.map((k, val) {
          final parsed = (val is num) ? val.toInt() : 0;
          return MapEntry(k.toString(), parsed);
        });
      }
      return {};
    }

   final dynamic rawPreco = m['preco'] ??
    m['preco_venda'] ?? // compatível com CatalogoSyncService
    m['precoVenda'] ??
    m['price'] ??
    m['precoFinal'] ?? // compatível com CatalogoSyncService
    0;

final num nPreco = (rawPreco is num)
    ? rawPreco
    : num.tryParse(rawPreco.toString()) ?? 0;

    return ProdutoFirestore(
      id: (m['id'] ?? '').toString(),
      nome: (m['nome'] ?? m['name'] ?? '').toString(),
      descricao: (m['descricao'] ?? m['description'] ?? '').toString(),
      imagens: _toStringList(m['imagens'] ?? m['fotos'] ?? m['images']),
      preco: nPreco.toDouble(),
      categoriaId: (m['categoriaId'] ?? m['categoria'] ?? '').toString(),
      subcategoriaId:
          (m['subcategoriaId'] ?? m['subcategoria'] ?? '').toString(),
      estoquePorTamanho: estoque(m['estoquePorTamanho']),
      quantidade:
          (m['quantidade'] is num) ? (m['quantidade'] as num).toInt() : 0,
    );
  }

  Stream<List<ProdutoFirestore>> streamProdutosDraft(String lojaId) {
    return streamProdutosDraftRaw(lojaId)
        .map((list) => list.map(_mapToProdutoFS).toList());
  }

  Stream<List<ProdutoFirestore>> streamProdutosLive(String lojaId) {
    return streamProdutosLiveRaw(lojaId)
        .map((list) => list.map(_mapToProdutoFS).toList());
  }

  /// Compat: catálogo público hoje mostra SOMENTE os rascunhos (prévia).
  Stream<List<ProdutoFirestore>> streamProdutosPublicos({
    required String lojaId,
    String? categoriaId,
    String? subcategoriaId,
  }) {
    return streamProdutosDraft(lojaId).map((items) {
      var out = items;
      if (categoriaId != null && categoriaId.isNotEmpty) {
        out = out.where((p) => p.categoriaId == categoriaId).toList();
      }
      if (subcategoriaId != null && subcategoriaId.isNotEmpty) {
        out = out.where((p) => p.subcategoriaId == subcategoriaId).toList();
      }
      return out;
    });
  }

  // ===========================================================================
  // CRUD – RASCUNHO
  // ===========================================================================

  CollectionReference<Map<String, dynamic>> _colDraft(String lojaId) =>
      _db.collection('lojas').doc(lojaId).collection('draft_produtos');

  CollectionReference<Map<String, dynamic>> _colLive(String lojaId) =>
      _db.collection('lojas').doc(lojaId).collection('produtos');

  Future<String> upsertProdutoDraft({
    required String lojaId,
    String? id,
    required Map<String, dynamic> data,
  }) async {
    final map = Map<String, dynamic>.from(data);
    map['ativo'] = (map['ativo'] is bool) ? map['ativo'] : true;
    map['publicar'] = (map['publicar'] is bool) ? map['publicar'] : false;
    map['updatedAt'] = FieldValue.serverTimestamp();

    if (id == null || id.isEmpty) {
      final ref = await _colDraft(lojaId).add(map);
      await ref.update({'id': ref.id});
      return ref.id;
    } else {
      await _colDraft(lojaId).doc(id).set(map, SetOptions(merge: true));
      return id;
    }
  }

  Future<void> setProdutoPublicar({
    required String lojaId,
    required String produtoId,
    required bool publicar,
  }) async {
    await _colDraft(lojaId).doc(produtoId).set(
      {'publicar': publicar, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> setProdutoAtivoDraft({
    required String lojaId,
    required String produtoId,
    required bool ativo,
  }) async {
    await _colDraft(lojaId).doc(produtoId).set(
      {'ativo': ativo, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteProdutoDraft({
    required String lojaId,
    required String produtoId,
  }) async {
    await _colDraft(lojaId).doc(produtoId).delete();
  }

  Future<Map<String, dynamic>?> getProdutoDraft({
    required String lojaId,
    required String produtoId,
  }) async {
    final d = await _colDraft(lojaId).doc(produtoId).get();
    return d.data();
  }

  // ===========================================================================
  // PUBLICAÇÃO (rascunho → live)
  // ===========================================================================

  /// Garante ownerUid no doc da loja para atender regras.
  Future<void> _ensureOwnerUid(String lojaId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await _db.collection('lojas').doc(lojaId).set(
      {'ownerUid': uid, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> publishConfigDraftToLive(String lojaId) async {
    await _ensureOwnerUid(lojaId);

    final ref = _db.collection('lojas').doc(lojaId);
    final draftCfgRef = ref.collection('draft_config').doc('config');
    final liveCfgRef = ref.collection('config').doc('config');

    final draftCfg = await draftCfgRef.get();
    await liveCfgRef.set(draftCfg.data() ?? {}, SetOptions(merge: true)); // ✅ CORRIGIDO: merge: true

    // espelho/compat no doc raiz
    await ref.set({
      'slug': lojaId,
      'updatedAt': FieldValue.serverTimestamp(),
      'config': draftCfg.data() ?? {},
    }, SetOptions(merge: true));
  }

  /// Commit em chunks (sem usar clamp que retorna num).
  Future<void> _commitInChunks(List<void Function(WriteBatch)> ops) async {
    const maxBatch = 450; // margem de segurança
    for (var i = 0; i < ops.length; i += maxBatch) {
      final end = (i + maxBatch <= ops.length) ? i + maxBatch : ops.length;
      final batch = _db.batch();
      for (final op in ops.sublist(i, end)) {
        op(batch);
      }
      await batch.commit();
    }
  }

  /// Publica PRODUTOS do rascunho para o site.
  /// - somenteMarcados == true: faz UPSERT apenas dos marcados (NÃO apaga o restante do live).
  /// - somenteMarcados == false: limpa live e regrava tudo que estiver ativo no rascunho.
  Future<void> publishDraftProductsToLive(
    String lojaId, {
    bool somenteMarcados = true,
  }) async {
    await _ensureOwnerUid(lojaId);

    final ref = _db.collection('lojas').doc(lojaId);
    final liveCol = ref.collection('produtos');
    final draftCol = ref.collection('draft_produtos');

    final ops = <void Function(WriteBatch)>[];

    if (!somenteMarcados) {
      // Publicação completa: limpa o live antes
      final liveSnap = await liveCol.get();
      for (final d in liveSnap.docs) {
        ops.add((b) => b.delete(liveCol.doc(d.id)));
      }
    }

    // Filtra rascunho
    Query<Map<String, dynamic>> q = draftCol;
    if (somenteMarcados) {
      q = q.where('publicar', isEqualTo: true);
    }
    final draftSnap = await q.get();

    for (final d in draftSnap.docs) {
      final data = Map<String, dynamic>.from(d.data());
      final ativo = (data['ativo'] is bool) ? data['ativo'] as bool : true;
      if (!ativo) continue;

      // Carimbo de data/hora ao publicar
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['publicadoEm'] = FieldValue.serverTimestamp();

      ops.add((b) => b.set(liveCol.doc(d.id), data, SetOptions(merge: true)));
    }

    await _commitInChunks(ops);
  }

  /// Publica TUDO: config + produtos (somente marcados por padrão).
  Future<void> publishDraftToLive(
    String lojaId, {
    bool somenteMarcados = true,
  }) async {
    await publishConfigDraftToLive(lojaId);
    await publishDraftProductsToLive(lojaId, somenteMarcados: somenteMarcados);
  }

  // ===========================================================================
  // CONSULTAS UTILITÁRIAS (uma vez)
  // ===========================================================================

  Future<List<ProdutoFirestore>> listDraftOnce({
    required String lojaId,
    bool? ativo,
    bool? publicar,
  }) async {
    Query<Map<String, dynamic>> q = _colDraft(lojaId);
    if (ativo != null) q = q.where('ativo', isEqualTo: ativo);
    if (publicar != null) q = q.where('publicar', isEqualTo: publicar);

    final snap = await q.get();
    return snap.docs
        .map((d) => _mapToProdutoFS({'id': d.id, ...d.data()}))
        .toList();
  }

  Future<List<ProdutoFirestore>> listLiveOnce({required String lojaId}) async {
    final snap = await _colLive(lojaId).where('ativo', isEqualTo: true).get();
    return snap.docs
        .map((d) => _mapToProdutoFS({'id': d.id, ...d.data()}))
        .toList();
  }
}
