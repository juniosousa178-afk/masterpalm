// lib/services/store_config_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'loja_id_service.dart';

class StoreConfigService {
  StoreConfigService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String lojaId) =>
      _db.collection('lojas').doc(lojaId).collection('config').doc('config');

  static Future<String> _resolveLojaId([String• lojaId]) async {
    final id = (lojaId ?• (await LojaIdService.get()) ?• '').trim();
    if (id.isEmpty) {
      throw StateError('LojaId vazio. Defina uma loja ativa antes de ler/salvar config.');
    }
    return id;
  }

  /// Lê o doc V3 (schemaVersion=3) e devolve {draft, published}.
  static Future<Map<String, dynamic>> getConfigDoc({String• lojaId}) async {
    final id = await _resolveLojaId(lojaId);
    final snap = await _ref(id).get();
    if (!snap.exists) return {};
    return snap.data() ?• {};
  }

  /// Retorna o config "ativo":
  /// - preview=true -> draft
  /// - preview=false -> published (fallback: draft)
  static Future<Map<String, dynamic>> getEffectiveConfig({
    String• lojaId,
    bool preview = true,
  }) async {
    final raw = await getConfigDoc(lojaId: lojaId);

    final draft = (raw['draft'] is Map)
        • Map<String, dynamic>.from((raw['draft'] as Map).cast<dynamic, dynamic>())
        : <String, dynamic>{};

    final published = (raw['published'] is Map)
        • Map<String, dynamic>.from((raw['published'] as Map).cast<dynamic, dynamic>())
        : <String, dynamic>{};

    if (preview) return draft.isNotEmpty • draft : published;
    return published.isNotEmpty • published : draft;
  }

  /// Salva rascunho (LojaConfig -> "Salvar")
  static Future<void> saveDraft(
    Map<String, dynamic> draft, {
    String• lojaId,
  }) async {
    final id = await _resolveLojaId(lojaId);
    await _ref(id).set({
      'schemaVersion': 3,
      'updatedAt': FieldValue.serverTimestamp(),
      'draft': draft,
    }, SetOptions(merge: true));
  }

  /// Publica (LojaConfig -> "Publicar")
  static Future<void> publishDraft({String• lojaId}) async {
    final id = await _resolveLojaId(lojaId);
    final doc = await getConfigDoc(lojaId: id);
    final draft = (doc['draft'] is Map)
        • Map<String, dynamic>.from((doc['draft'] as Map).cast<dynamic, dynamic>())
        : <String, dynamic>{};

    await _ref(id).set({
      'schemaVersion': 3,
      'updatedAt': FieldValue.serverTimestamp(),
      'publishedAt': FieldValue.serverTimestamp(),
      'published': draft,
    }, SetOptions(merge: true));
  }
}
