// lib/services/controle_compras_fornecedor_firestore_service.dart
// Espelho na nuvem do controle operacional de compras por fornecedor.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ControleComprasFornecedorFirestoreService {
  ControleComprasFornecedorFirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(
    String lojaId,
    String id,
  ) {
    return _db
        .collection('lojas')
        .doc(lojaId.trim())
        .collection('controle_compras_fornecedor')
        .doc(id);
  }

  static Future<bool> upsertMap(
    String lojaId,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final id = lojaId.trim();
    if (id.isEmpty || docId.isEmpty) return false;
    try {
      final m = Map<String, dynamic>.from(data);
      m['lojaId'] = id;
      m['updatedAt'] = FieldValue.serverTimestamp();
      await _ref(id, docId).set(m, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint(
        '[CONTROLE_COMPRAS_FS] upsert falhou (type=${e.runtimeType})',
      );
      return false;
    }
  }

  static Future<bool> deleteLinha(String lojaId, String linhaId) async {
    final id = lojaId.trim();
    if (id.isEmpty || linhaId.isEmpty) return false;
    try {
      await _ref(id, linhaId).delete();
      return true;
    } catch (e) {
      debugPrint(
        '[CONTROLE_COMPRAS_FS] delete falhou (type=${e.runtimeType})',
      );
      return false;
    }
  }

  /// Lista documentos remotos (mapas crus) para merge no Hive.
  static Future<List<Map<String, dynamic>>> listarMaps(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return [];
    try {
      final qs = await _db
          .collection('lojas')
          .doc(id)
          .collection('controle_compras_fornecedor')
          .get();
      return qs.docs.map((d) => {...d.data(), 'id': d.id}).toList();
    } catch (e) {
      debugPrint(
        '[CONTROLE_COMPRAS_FS] listar falhou (type=${e.runtimeType})',
      );
      return [];
    }
  }
}
