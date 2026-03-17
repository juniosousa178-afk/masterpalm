// lib/services/meta_firestore_service.dart
// Sincroniza metas (valor da meta, etc.) com Firestore para persistir ao trocar de celular.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/meta.dart';

class MetaFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ID do documento no Firestore (mesRef_vendedorId; substitui caracteres inválidos)
  static String _docId(Meta meta) {
    final key = meta.hiveKey;
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
  }

  /// Salva ou atualiza uma meta no Firestore
  static Future<void> saveMeta(Meta meta, {required String lojaId}) async {
    try {
      final docId = _docId(meta);
      final data = meta.toMap()
        ..['lojaId'] = lojaId;
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('metas')
          .doc(docId)
          .set(data, SetOptions(merge: true));
      debugPrint('✅ [META-SYNC] Meta $docId sincronizada');
    } catch (e) {
      debugPrint('❌ [META-SYNC] Erro ao salvar meta (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Busca todas as metas da loja no Firestore
  static Future<List<Meta>> getMetas({required String lojaId}) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('metas')
          .get();
      final list = <Meta>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data.isEmpty) continue;
        list.add(Meta.fromMap(data, docId: doc.id));
      }
      return list;
    } catch (e) {
      debugPrint('❌ [META-SYNC] Erro ao buscar metas (type=${e.runtimeType})');
      return [];
    }
  }
}
