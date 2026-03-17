// lib/services/catalog_visitas_service.dart
// Contagem de visitas na loja online (catálogo público). Sem custo; usa Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CatalogVisitasService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Incrementa contador de visitas do catálogo (chamar uma vez por sessão/página).
  static Future<void> incrementarVisita(String lojaId) async {
    if (lojaId.isEmpty) return;
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('stats')
          .set({
        'visitas': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [VISITAS] Erro ao incrementar (type=${e.runtimeType})');
      }
    }
  }

  /// Retorna o total de visitas do catálogo (para exibir em relatórios/dashboard).
  static Future<int> obterVisitas(String lojaId) async {
    if (lojaId.isEmpty) return 0;
    try {
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('stats')
          .get();
      if (!doc.exists) return 0;
      final data = doc.data();
      final v = data?['visitas'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [VISITAS] Erro ao obter (type=${e.runtimeType})');
      }
      return 0;
    }
  }
}
