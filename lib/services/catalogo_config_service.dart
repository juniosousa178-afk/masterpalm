// lib/services/catalogo_config_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/catalogo_config.dart';
import '../models/catalogo_config_firestore.dart';
import '../services/store_resolver_facade.dart';

class CatalogoConfigService {
  CatalogoConfigService._();

  // ---------------- Firestore refs ----------------
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _draftRef(String lojaId) =>
      _db.collection('lojas').doc(lojaId)
          .collection('config_catalogo_draft')
          .doc('main');

  static DocumentReference<Map<String, dynamic>> _liveRef(String lojaId) =>
      _db.collection('lojas').doc(lojaId)
          .collection('config_catalogo_live')
          .doc('main');

  // ---------------- Hive (rascunho local por loja) ----------------

  static Future<Box<CatalogoConfig>> _openHiveBox(String lojaId) async {
    return Hive.openBox<CatalogoConfig>(HiveBoxNames.configCatalogoLoja(lojaId));
  }

  /// Lê o rascunho salvo localmente para a loja (usado pela LojaConfigScreen).
  static Future<CatalogoConfig?> loadDraftFromHive(String lojaId) async {
    if (lojaId.trim().isEmpty) return null;
    final box = await _openHiveBox(lojaId.trim());
    return box.get('draft');
  }

  /// Salva o rascunho localmente no Hive para a loja.
  static Future<void> saveDraftToHive(CatalogoConfig cfg, String lojaId) async {
    if (lojaId.trim().isEmpty) return;
    final box = await _openHiveBox(lojaId.trim());
    await box.put('draft', cfg);
  }

  // ---------------- Firestore: carregar LIVE para o SITE ----------------

  /// Lê a configuração publicada (LIVE) do Firestore para uma loja específica.
  /// Usado pelo catálogo no APK para garantir config da mesma loja.
  static Future<CatalogoConfig?> loadLiveForLoja(String lojaId) async {
    if (lojaId.trim().isEmpty) return null;
    try {
      final snap = await _liveRef(lojaId.trim()).get();
      if (!snap.exists || snap.data() == null) return null;
      return catalogoConfigFromFirestore(snap.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Lê a configuração publicada (LIVE) do Firestore – usada pelo catálogo público.
  static Future<CatalogoConfig?> loadLiveFromFirestore() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.trim().isEmpty) return null;
    return loadLiveForLoja(lojaId);
  }

  // ---------------- Publicar draft -> LIVE ----------------

  /// 🔹 Chamar isso ao clicar no botão "Publicar" na LojaConfigScreen.
  /// 1) Lê o draft local (Hive)
  /// 2) Sobe para config_catalogo_draft
  /// 3) Copia para config_catalogo_live (usado pelo site)
  static Future<void> publishDraftToLive() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.trim().isEmpty) return;
    // 1) lê o draft local (Hive) da loja
    final draft = await loadDraftFromHive(lojaId);
    if (draft == null) {
      throw Exception('Nenhuma configuração de catálogo encontrada (draft).');
    }

    final data = draft.toFirestore();

    // 2) salva no draft do Firestore (histórico/opcional)
    await _draftRef(lojaId).set(
      data,
      SetOptions(merge: true),
    );

    // 3) copia para o LIVE (usado pelo catálogo público)
    await _liveRef(lojaId).set(
      data,
      SetOptions(merge: true),
    );
  }
}