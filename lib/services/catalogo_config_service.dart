// lib/services/catalogo_config_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/catalogo_config.dart';
import '../models/catalogo_config_firestore.dart';
import 'catalog_cache_service.dart';
import 'store_resolver_facade.dart';

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

  /// Fonte pública oficial do catálogo web: `lojas/{lojaId}/config/config`
  /// (mesmo caminho usado por [PublicCatalogScreen] / [CatalogCacheService]).
  static DocumentReference<Map<String, dynamic>> _officialPublicConfigRef(String lojaId) =>
      _db.collection('lojas').doc(lojaId).collection('config').doc('config');

  static Color _parsePaletteColor(String raw, {Color fallback = Colors.black}) {
    var v = raw.trim();
    if (v.isEmpty) return fallback;
    if (v.startsWith('0x') || v.startsWith('0X')) v = v.substring(2);
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 6) v = 'FF$v';
    try {
      return Color(int.parse(v, radix: 16));
    } catch (_) {
      return colorFromHex(raw, fallback: fallback);
    }
  }

  /// Mescla paleta legada (CatalogoConfig) no doc público oficial sem apagar
  /// chaves já publicadas pela Loja Config (merge de [theme] em Dart).
  static Future<void> _syncPaletteToOfficialPublicDoc(
    String lojaId,
    CatalogoConfig draft,
    Map<String, dynamic> paletteMap,
  ) async {
    final ref = _officialPublicConfigRef(lojaId);
    final snap = await ref.get();
    final merged = <String, dynamic>{};
    if (snap.exists && snap.data() != null) {
      merged.addAll(Map<String, dynamic>.from(snap.data()!));
    }
    for (final e in paletteMap.entries) {
      merged[e.key] = e.value;
    }
    final bg = _parsePaletteColor(draft.corFundo);
    final tx = _parsePaletteColor(draft.corTexto);
    final pr = _parsePaletteColor(draft.corBotao);
    final cab = draft.corCabecalho.trim().isEmpty
        ? pr
        : _parsePaletteColor(draft.corCabecalho);
    final themeRaw = merged['theme'];
    final theme = themeRaw is Map
        ? Map<String, dynamic>.from(
            themeRaw.map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, dynamic>{};
    int cv(Color c) => c.value;
    theme['fundo'] = cv(bg);
    theme['texto'] = cv(tx);
    theme['primaria'] = cv(pr);
    theme['botaoTexto'] = cv(tx);
    theme['cabecalho'] = cv(cab);
    theme.putIfAbsent('card', () => cv(bg));
    merged['theme'] = theme;
    merged['publishedAt'] = FieldValue.serverTimestamp();
    merged['catalogPalettePublishedFrom'] = 'catalogo_config_service';
    await ref.set(merged, SetOptions(merge: true));
  }

  /// Após publicar em `config/config`, espelha só a paleta em `config_catalogo_live/main`
  /// para leitores legados ([CatalogoScreen]), sem sobrescrever o doc oficial.
  static Future<void> mirrorOfficialThemePaletteToLegacyLive(String lojaId) async {
    if (lojaId.trim().isEmpty) return;
    try {
      final snap = await _officialPublicConfigRef(lojaId).get();
      if (!snap.exists || snap.data() == null) return;
      final m = Map<String, dynamic>.from(snap.data()!);
      final t = m['theme'];
      if (t is! Map) return;

      String? colorIntToHex(dynamic v) {
        if (v == null) return null;
        final n = v is int
            ? v
            : (v is num ? v.toInt() : int.tryParse(v.toString()));
        if (n == null) return null;
        return '0x${n.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      }

      final fc = colorIntToHex(t['fundo']);
      if (fc == null || fc.isEmpty) return;

      await _liveRef(lojaId).set(
        {
          'corFundo': fc,
          'corTexto': colorIntToHex(t['texto']) ?? fc,
          'corBotao': colorIntToHex(t['primaria']) ?? fc,
          'corCabecalho': colorIntToHex(t['cabecalho']) ??
              colorIntToHex(t['primaria']) ??
              fc,
          'fonte': (m['fonte'] ?? 'Roboto').toString(),
          'tamanhoFonte': (m['tamanhoFonte'] is num)
              ? (m['tamanhoFonte'] as num).toDouble()
              : 14.0,
          'legacyMirroredFrom': 'official_config_theme',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  // ---------------- Hive (rascunho local por loja) ----------------

  static Future<Box<CatalogoConfig>> _openHiveBox(String lojaId) async {
    return Hive.openBox<CatalogoConfig>(HiveBoxNames.configCatalogoLoja(lojaId));
  }

  /// Lê o rascunho salvo localmente para a loja (Hive por loja).
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

  /// Lê a configuração publicada em `config_catalogo_live` (fluxo legado).
  static Future<CatalogoConfig?> loadLiveFromFirestore() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.trim().isEmpty) return null;
    return loadLiveForLoja(lojaId);
  }

  // ---------------- Publicar draft -> LIVE ----------------

  /// Publica paleta legada (Hive [CatalogoConfig]) para:
  /// - `config_catalogo_*` (compat leitura [CatalogoScreen] legado)
  /// - **`lojas/{lojaId}/config/config`** (fonte pública oficial do catálogo web)
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

    // 3) copia para o LIVE (compat telas legadas que leem config_catalogo_live)
    await _liveRef(lojaId).set(
      data,
      SetOptions(merge: true),
    );

    // 4) Fonte pública oficial do catálogo web (não depender só do fallback de leitura)
    await _syncPaletteToOfficialPublicDoc(lojaId, draft, data);
    CatalogCacheService.invalidate(lojaId, preview: false);
  }
}