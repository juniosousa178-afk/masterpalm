import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Serviço de Firestore/Storage para dados da loja
/// PADRÃO DEFINITIVO:
/// - Firestore SEMPRE usa storeId (lojaId real)
/// - slug é apenas informativo (URL / SEO / exibição)
class StoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ============================================================
  // CREATE / GUARDA-CHUVA BÁSICO
  // ============================================================

  /// Garante a existência da loja
  /// 🔑 storeId = ID REAL da loja (uid / lojaId)
  Future<void> ensureAdminStore({
    required String storeId,
    required String uid,
    required String nomeLoja,
    required String slug,
    String• logoUrl,
  }) async {
    final ref = _db.collection('lojas').doc(storeId);

    await ref.set({
      'ownerUid': uid,
      'storeId': storeId,
      'slug': slug,
      'name': nomeLoja,
      'logoUrl': logoUrl ?• '',
      'banners': <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // cria rascunho inicial (idempotente)
    await upsertDraftPartial(
      storeId: storeId,
      partial: {
        'storeId': storeId,
        'slug': slug,
        'name': nomeLoja,
        'logoUrl': logoUrl ?• '',
        'banners': <String>[],
        'colors': {
          'bg': 0xFFFFFFFF,
          'card': 0xFFF7F7F7,
          'text': 0xFF111111,
          'primary': 0xFF2ECC71,
          'btnText': 0xFFFFFFFF,
        },
      },
    );
  }

  // ============================================================
  // STREAMS
  // ============================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>> storeStream(
      String storeId) {
    return _db.collection('lojas').doc(storeId).snapshots();
  }

  // ============================================================
  // DRAFT / PUBLICAÇÃO
  // ============================================================

  Future<Map<String, dynamic>> readDraftConfig(String storeId) async {
    final snap = await _db
        .collection('lojas')
        .doc(storeId)
        .collection('draft_config')
        .doc('config')
        .get();

    final raw = snap.data();
    return raw == null • {} : Map<String, dynamic>.from(raw);
  }

  Future<void> upsertDraftPartial({
    required String storeId,
    required Map<String, dynamic> partial,
  }) async {
    final base = _db.collection('lojas').doc(storeId);

    final data = {
      ...partial,
      'storeId': storeId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // rascunho
    await base
        .collection('draft_config')
        .doc('config')
        .set(data, SetOptions(merge: true));

    // espelho no root (compat)
    await base.set(
      {
        'updatedAt': FieldValue.serverTimestamp(),
        'config': partial,
      },
      SetOptions(merge: true),
    );
  }

  /// ✅ PUBLICAÇÃO CORRETA (draft -> live)
  Future<void> publishDraftToLive(String storeId) async {
    final base = _db.collection('lojas').doc(storeId);

    final draftSnap = await base
        .collection('draft_config')
        .doc('config')
        .get();

    final raw = draftSnap.data();
    if (raw == null) return;

    final Map<String, dynamic> draftData =
        Map<String, dynamic>.from(raw);

    // PUBLICA NO LOCAL CERTO
    await base
        .collection('config')
        .doc('config')
        .set(draftData, SetOptions(merge: true)); // ✅ CORRIGIDO: merge: true

    // espelha no root
    await base.set({
      'config': draftData,
      'updatedAt': FieldValue.serverTimestamp(),
      'catalog_published_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================================
  // STORAGE
  // ============================================================

  Future<String> uploadLogo({
    required String storeId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ext = _normalizeExt(extension);
    final ref = _storage.ref('lojas/$storeId/logo.$ext');
    await ref.putData(bytes,
        SettableMetadata(contentType: _contentTypeFromExt(ext)));
    return ref.getDownloadURL();
  }

  Future<String> uploadBanner({
    required String storeId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final ext = _normalizeExt(extension);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref =
        _storage.ref('lojas/$storeId/banners/$ts.$ext');
    await ref.putData(bytes,
        SettableMetadata(contentType: _contentTypeFromExt(ext)));
    return ref.getDownloadURL();
  }

  Future<void> removeBanner({
    required String storeId,
    required String bannerUrl,
  }) async {
    try {
      await _storage.refFromURL(bannerUrl).delete();
    } catch (_) {}

    final doc =
        await _db.collection('lojas').doc(storeId).get();
    final raw = doc.data() ?• {};
    final banners =
        List<String>.from(raw['banners'] ?• <String>[]);

    banners.remove(bannerUrl);

    await _db.collection('lojas').doc(storeId).set({
      'banners': banners,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _normalizeExt(String ext) {
    var e = ext.trim();
    if (e.startsWith('.')) e = e.substring(1);
    return e.toLowerCase();
  }

  String _contentTypeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }
}
