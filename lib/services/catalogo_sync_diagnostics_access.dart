// Acesso à tela de diagnóstico de sync de catálogo — dono/admin/programador.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/firestore_access_guard.dart';
import 'store_resolver_service.dart';

class CatalogoSyncDiagnosticsAccess {
  CatalogoSyncDiagnosticsAccess._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static bool? debugForcePodeAcessar;

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: debugFirestoreOverride,
      );

  static Future<bool> podeAcessar() async {
    if (debugForcePodeAcessar != null) return debugForcePodeAcessar!;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final sessao =
          Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
      final tipo =
          (sessao.get('tipo_usuario') ?? '').toString().trim().toLowerCase();
      if (tipo == 'admin' || tipo == 'programador') return true;
    } catch (_) {}

    final canonical =
        await StoreResolverService.resolveCanonicalOwnerStoreFromProfile();
    if (canonical == null || canonical.isEmpty) return false;

    return _lojaPertenceAoUsuarioAtual(canonical, user.uid);
  }

  static Future<bool> _lojaPertenceAoUsuarioAtual(
    String lojaId,
    String uid,
  ) async {
    try {
      final snap = await _db.collection('lojas').doc(lojaId.trim()).get();
      if (!snap.exists) return false;
      final ownerUid = (snap.data()?['ownerUid'] ?? '').toString().trim();
      return ownerUid.isNotEmpty && ownerUid == uid;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void resetForTests() {
    debugFirestoreOverride = null;
    debugForcePodeAcessar = null;
    FirestoreAccessGuard.resetForTests();
  }
}
