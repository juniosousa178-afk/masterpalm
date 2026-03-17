import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class StoreSlugResolver {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Resolve slug OU store_id → store_id REAL
  /// - Se já for store_id, retorna direto
  /// - Se for slug, busca em lojas onde slug == valor
  static Future<String?> resolveToStoreId(String input) async {
    final raw = input.trim();

    if (raw.isEmpty) return null;

    // 1️⃣ Se já parece store_id, retorna direto
    if (_looksLikeStoreId(raw)) {
      debugPrint('🧭 [SLUG-RESOLVER] Já é store_id → $raw');
      return raw;
    }

    debugPrint('🔎 [SLUG-RESOLVER] Resolvendo slug → store_id: "$raw"');

    try {
      final q = await _db
          .collection('lojas')
          .where('slug', isEqualTo: raw)
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        debugPrint('❌ [SLUG-RESOLVER] Nenhuma loja encontrada com slug="$raw"');
        return null;
      }

      final doc = q.docs.first;
      debugPrint(
        '✅ [SLUG-RESOLVER] slug="$raw" → store_id="${doc.id}"',
      );

      return doc.id;
    } catch (e) {
      debugPrint('🟥 [SLUG-RESOLVER] Erro ao resolver slug="$raw" (type=${e.runtimeType})');
      return null;
    }
  }

  static bool _looksLikeStoreId(String v) {
    return v.startsWith('loja_uid_') || v.startsWith('loja_email_');
  }
}
