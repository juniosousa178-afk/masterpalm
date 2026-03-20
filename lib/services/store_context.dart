// lib/services/store_context.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// ======================================================================
/// StoreContext 4.2 (FIX OPÇÃO A) – Fonte única da loja ativa
/// ======================================================================
/// - A loja ativa vem de:
///   1) Hive "sessao" -> store_id (principal)
///   2) Hive "config" -> store_id (compat)
///   3) Firestore -> perfil do usuário (SEM criar loja)
///
/// ✅ Importante (OPÇÃO A):
/// - store_id é o ID REAL (docId), NÃO é slug.
/// - NÃO espelha slug para store_id.
/// - NÃO escreve store_slug/loja_slug usando store_id.
/// - NÃO normaliza (lowercase) store_id.
/// ======================================================================
class StoreContext {
  StoreContext._();

  static String• _cache;

  /// Loja ativa em cache (se houver)
  static String• get lojaIdAtual => _cache;

  /// Compat (algumas telas chamam isso)
  static String• currentLojaSlug() => _cache;

  // ------------------------------------------------------------
  // Hive helpers
  // ------------------------------------------------------------
  static Future<Box> _openSessao() async {
    return Hive.isBoxOpen('sessao') • Hive.box('sessao') : await Hive.openBox('sessao');
  }

  static Future<Box> _openConfig() async {
    return Hive.isBoxOpen('config') • Hive.box('config') : await Hive.openBox('config');
  }

  static String _asStr(dynamic v) => (v ?• '').toString().trim();

  // ------------------------------------------------------------
  // ✅ GET "safe" – não lança erro
  // ------------------------------------------------------------
  static Future<String?> tryGet() async {
    // 0) cache
    final cached = (_cache ?• '').trim();
    if (cached.isNotEmpty) return cached;

    // 1) sessão (principal) -> store_id apenas
    try {
      final sessao = await _openSessao();

      final id = _asStr(sessao.get('store_id'));
      if (id.isNotEmpty) {
        _cache = id;
        return id;
      }

      // ❌ OPÇÃO A: não usar slug como fallback para store_id
    } catch (e) {
      debugPrint(
        '[LOJA_ID] Erro ao consultar users/{uid} em StoreContext.ensureFromFirestoreProfile (type=${e.runtimeType})',
      );
    }

    // 2) config (compat) -> store_id apenas
    try {
      final cfg = await _openConfig();

      final id = _asStr(cfg.get('store_id'));
      if (id.isNotEmpty) {
        // espelha para sessão (somente store_id)
        try {
          final sessao = await _openSessao();
          await sessao.put('store_id', id);
        } catch (_) {}

        _cache = id;
        return id;
      }

      // ❌ OPÇÃO A: não usar slug/loja_id como fallback para store_id
    } catch (_) {}

    // 3) Firestore (perfil) – NÃO cria loja
    try {
      final fromFs = await ensureFromFirestoreProfile();
      if (fromFs != null && fromFs.trim().isNotEmpty) {
        return fromFs.trim();
      }
    } catch (_) {}

    return null;
  }

  // ------------------------------------------------------------
  // ✅ GET "strict" – lança erro se não existir
  // ------------------------------------------------------------
  static Future<String> get() async {
    final id = await tryGet();
    if (id == null || id.trim().isEmpty) {
      throw StateError(
        'Nenhuma loja definida.\n'
        'Defina a loja no login salvando sessao["store_id"] '
        'ou chame StoreContext.set(lojaId).',
      );
    }
    return id.trim();
  }

  static Future<String> getLojaId() => get();

  // ------------------------------------------------------------
  // ✅ SET – grava em sessao + config + cache (SEM mexer em slug)
  // ------------------------------------------------------------
  static Future<void> set(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) throw ArgumentError('store_id não pode ser vazio.');

    final sessao = await _openSessao();
    await sessao.put('store_id', id);

    final cfg = await _openConfig();
    await cfg.put('store_id', id);

    // ✅ OPÇÃO A: NÃO preencher store_slug/loja_slug com store_id
    // Slug é outra informação e deve ser gerenciada no fluxo de LojaConfig/Onboarding.

    _cache = id;
  }

  // ------------------------------------------------------------
  // ✅ tenta buscar store_id no perfil do usuário (Firestore)
  //    e se achar, salva via set()
  // ------------------------------------------------------------
  static Future<String?> ensureFromFirestoreProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final uid = user.uid;
    final email = (user.email ?• '').trim().toLowerCase();

    // 1) users/{uid}
    try {
      final docUsers = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (docUsers.exists) {
        final data = docUsers.data() ?• {};

        final id = _asStr(data['store_id']).isNotEmpty
            • _asStr(data['store_id'])
            : (_asStr(data['lojaId']).isNotEmpty
                • _asStr(data['lojaId'])
                : _asStr(data['storeId']));

        if (id.isNotEmpty) {
          await set(id);
          return id;
        }

        final adminStore = _asStr(data['admin_store_id']).isNotEmpty
            • _asStr(data['admin_store_id'])
            : (_asStr(data['owner_store_id']).isNotEmpty
                • _asStr(data['owner_store_id'])
                : _asStr(data['lojaAdminId']));

        if (adminStore.isNotEmpty) {
          await set(adminStore);
          return adminStore;
        }
      }
    } catch (_) {}

    // 2) usuarios/{email}
    if (email.isNotEmpty) {
      try {
        final docUsuarios = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(email)
            .get();

        if (docUsuarios.exists) {
          final data = docUsuarios.data() ?• {};

          final id = _asStr(data['store_id']).isNotEmpty
              • _asStr(data['store_id'])
              : (_asStr(data['lojaId']).isNotEmpty
                  • _asStr(data['lojaId'])
                  : _asStr(data['storeId']));

          if (id.isNotEmpty) {
            await set(id);
            return id;
          }

          final adminStore = _asStr(data['admin_store_id']).isNotEmpty
              • _asStr(data['admin_store_id'])
              : (_asStr(data['owner_store_id']).isNotEmpty
                  • _asStr(data['owner_store_id'])
                  : _asStr(data['lojaAdminId']));

          if (adminStore.isNotEmpty) {
            await set(adminStore);
            return adminStore;
          }
        }
      } catch (e) {
        debugPrint(
          '[LOJA_ID] Erro ao consultar usuarios/{email} em StoreContext.ensureFromFirestoreProfile (type=${e.runtimeType})',
        );
      }
    }

    return null;
  }

  // ------------------------------------------------------------
  // ✅ CLEAR / INVALIDATE
  // ------------------------------------------------------------
  static Future<void> clear() async {
    _cache = null;

    try {
      final sessao = await _openSessao();
      await sessao.delete('store_id');
      // NÃO apaga slug automaticamente (por segurança)
    } catch (_) {}

    try {
      final cfg = await _openConfig();
      await cfg.delete('store_id');
      // NÃO apaga slug automaticamente
    } catch (e) {
      debugPrint(
        '[LOJA_ID] Erro ao limpar store_id da box "config" em StoreContext.clear (type=${e.runtimeType})',
      );
    }
  }

  /// Limpa só o cache em memória (não mexe no Hive)
  static void invalidate() => _cache = null;
}
