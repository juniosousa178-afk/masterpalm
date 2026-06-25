// Controle de acesso à recuperação assistida — somente dono/admin.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/firestore_access_guard.dart';
import 'store_resolver_service.dart';

class ProdutoSyncRecoveryAccess {
  ProdutoSyncRecoveryAccess._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static bool? debugForcePodeAcessar;

  @visibleForTesting
  static bool? debugForceCanonicalOwner;

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: debugFirestoreOverride,
      );

  /// Dono da loja ou administrador/programador.
  static Future<bool> podeAcessarRecuperacao() async {
    if (debugForcePodeAcessar != null) return debugForcePodeAcessar!;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final sessao =
          Hive.isBoxOpen('sessao') ? Hive.box('sessao') : await Hive.openBox('sessao');
      final tipo = (sessao.get('tipo_usuario') ?? '').toString().trim().toLowerCase();
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

  /// Verifica se a loja canônica pertence ao mesmo ownerUid do usuário autenticado.
  static Future<bool> canonicalPertenceAoUsuario(String canonicalStoreId) async {
    if (debugForceCanonicalOwner != null) return debugForceCanonicalOwner!;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return _lojaPertenceAoUsuarioAtual(canonicalStoreId, uid);
  }

  @visibleForTesting
  static void resetForTests() {
    debugFirestoreOverride = null;
    debugForcePodeAcessar = null;
    debugForceCanonicalOwner = null;
    FirestoreAccessGuard.resetForTests();
  }
}
