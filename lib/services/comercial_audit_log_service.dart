// Auditoria de gestão comercial (camada app → Firestore da loja).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

abstract final class ComercialAuditLogService {
  ComercialAuditLogService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _col(String lojaId) =>
      _db.collection('lojas').doc(lojaId.trim()).collection('comercial_auditoria');

  /// Registra evento sem PII sensível (sem senhas / endereços).
  static Future<void> log({
    required String lojaId,
    required String acao,
    required String atorUid,
    String? alvoVendedorUid,
    String? produtoId,
    Map<String, dynamic>? detalhe,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty || acao.trim().isEmpty) return;
    try {
      final id = const Uuid().v4();
      await _col(loja).doc(id).set({
        'id': id,
        'acao': acao.trim(),
        'atorUid': atorUid.trim(),
        if ((alvoVendedorUid ?? '').trim().isNotEmpty)
          'alvoVendedorUid': alvoVendedorUid!.trim(),
        if ((produtoId ?? '').trim().isNotEmpty) 'produtoId': produtoId!.trim(),
        if (detalhe != null && detalhe.isNotEmpty) 'detalhe': detalhe,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[COMERCIAL-AUDIT] fail type=${e.runtimeType} acao=$acao');
    }
  }

  static Future<List<Map<String, dynamic>>> listarRecentes({
    required String lojaId,
    int limit = 50,
    String? vendedorUid,
  }) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return const [];
    try {
      Query<Map<String, dynamic>> q =
          _col(loja).orderBy('createdAt', descending: true).limit(limit);
      final snap = await q.get();
      final out = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final m = Map<String, dynamic>.from(d.data());
        if (vendedorUid != null && vendedorUid.trim().isNotEmpty) {
          final alvo = (m['alvoVendedorUid'] ?? '').toString();
          if (alvo != vendedorUid.trim()) continue;
        }
        out.add(m);
      }
      return out;
    } catch (e) {
      debugPrint('[COMERCIAL-AUDIT] list fail type=${e.runtimeType}');
      return const [];
    }
  }
}
