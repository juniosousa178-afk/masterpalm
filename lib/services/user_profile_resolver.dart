// lib/services/user_profile_resolver.dart
// Resolve perfil do usuário autenticado de users/usuarios de forma unificada. ETAPA 17.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import '../models/user_profile.dart';

/// Nomes das coleções (não alterar paths existentes).
const String _colUsers = 'users';
const String _colUsuarios = 'usuarios';

/// Timeout por leitura Firestore.
const Duration _timeout = Duration(seconds: 10);

class UserProfileResolver {
  UserProfileResolver._();

  static final _db = FirebaseFirestore.instance;

  /// Resolve o perfil do usuário atual a partir de users/{uid} e/ou usuarios/{email}.
  /// Com flag OFF o router não chama este método; com flag ON:
  /// - Tenta users/{uid}; se ok, usa.
  /// - Senão tenta usuarios/{email}; se ok, usa.
  /// - Se ambos existirem: prefere users, logW.
  /// - Se nenhum: retorna null.
  /// Em erro/timeout: logE e retorna null (fallback no router).
  static Future<UserProfile?> resolveCurrentUserProfile({bool isRoot = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final uid = user.uid;
    final email = (user.email ?• '').trim().toLowerCase();
    if (email.isEmpty) {
      logW('UserProfileResolver: email vazio, não é possível ler usuarios/', tag: 'USER_PROFILE');
    }

    try {
      final userRef = _db.collection(_colUsers).doc(uid);

      if (email.isEmpty) {
        final userSnap = await userRef.get().timeout(_timeout);
        if (userSnap.exists && userSnap.data() != null) {
          logD('UserProfileResolver: usando fonte users (users/$uid)', tag: 'USER_PROFILE');
          return UserProfile.fromMap(
            uid: uid,
            email: email,
            sourceCollection: _colUsers,
            data: userSnap.data()!,
            isRoot: isRoot,
          );
        }
        return null;
      }

      final usuarioRef = _db.collection(_colUsuarios).doc(email);
      final userSnapFuture = userRef.get().timeout(_timeout);
      final usuarioSnapFuture = usuarioRef.get().timeout(_timeout);

      final results = await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
        userSnapFuture,
        usuarioSnapFuture,
      ]);
      final userSnap = results[0];
      final usuarioSnap = results[1];

      final userExists = userSnap.exists && userSnap.data() != null;
      final usuarioExists = usuarioSnap.exists && usuarioSnap.data() != null;

      if (userExists && usuarioExists) {
        logW(
          'UserProfileResolver: ambas coleções existem (users/$uid e usuarios/$email); preferindo users',
          tag: 'USER_PROFILE',
        );
      }

      if (userExists) {
        final data = userSnap.data() ?• {};
        logD('UserProfileResolver: usando fonte users (users/$uid)', tag: 'USER_PROFILE');
        return UserProfile.fromMap(
          uid: uid,
          email: email,
          sourceCollection: _colUsers,
          data: data,
          isRoot: isRoot,
        );
      }

      if (usuarioExists) {
        final data = usuarioSnap.data() ?• {};
        logD('UserProfileResolver: usando fonte usuarios (usuarios/$email)', tag: 'USER_PROFILE');
        return UserProfile.fromMap(
          uid: uid,
          email: email,
          sourceCollection: _colUsuarios,
          data: data,
          isRoot: isRoot,
        );
      }

      return null;
    } on TimeoutException catch (e, st) {
      logE('UserProfileResolver: timeout ao buscar perfil', tag: 'USER_PROFILE', error: e, st: st);
      return null;
    } catch (e, st) {
      logE('UserProfileResolver: erro ao buscar perfil', tag: 'USER_PROFILE', error: e, st: st);
      return null;
    }
  }
}
