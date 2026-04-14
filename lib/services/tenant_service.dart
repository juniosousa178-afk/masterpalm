// lib/services/tenant_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../catalog/catalog_layout_config.dart';

/// Serviço responsável por garantir que CADA usuário tenha
/// sua própria loja (documento em lojas/{store_id}) e que
/// o campo users/{uid}.store_id esteja sempre preenchido.
///
/// ✅ PADRONIZADO: Usa a mesma lógica do StoreResolverService
/// - Slug gerado a partir do email (ex: natypolylopes1997 → natypolylopes1997)
/// - Sincroniza users/{uid}.store_id E usuarios/{email}.store_id
///
/// 👇 Regra importante:
/// - Cada admin tem sua LOJA independente.
/// - NENHUM outro usuário (nem root) compartilha esse store_id.
/// - Regras de segurança garantem o isolamento entre lojas.
class TenantService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fluxo principal: garante que existe uma loja para o usuário
  /// e que users/{uid}.store_id está preenchido.
  ///
  /// ✅ PADRONIZADO (igual natypolylopes1997@gmail.com):
  /// - Se já tiver store_id no doc users/{uid}, apenas retorna.
  /// - Se não tiver, cria uma nova loja em lojas/{slug-do-email}.
  /// - Sincroniza também usuarios/{email}.store_id
  Future<String> ensureStoreForUser(
    String uid, {
    String? email,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final userSnap = await userRef.get();

    // 1) já existe store_id associado ao usuário → usa o mesmo
    final existing = userSnap.data()?['store_id'];
    if (existing != null && existing.toString().isNotEmpty) {
      debugPrint('✅ [TENANT] Store existente: ${existing.toString()}');
      return existing.toString();
    }

    // 2) gerar lojaId a partir do e-mail (ou fallback)
    email ??= userSnap.data()?['email']?.toString() ??
        FirebaseAuth.instance.currentUser?.email ??
        'loja-$uid';

    final slug = _makeSlug(email);
    debugPrint('🆕 [TENANT] Gerando slug para $email → $slug');

    final lojaRef = _db.collection('lojas').doc(slug);
    final lojaSnap = await lojaRef.get();

    // 3) se não existir loja com esse slug, cria uma nova
    if (!lojaSnap.exists) {
      debugPrint('📝 [TENANT] Criando loja nova: $slug');
      await lojaRef.set({
        'id': slug,
        'lojaId': slug,
        'slug': slug,
        'ownerUid': uid,
        'ownerEmail': email,
        'nome': 'Minha Loja',
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ✅ Criar config e draft_config (padrão igual natypolylopes1997)
      await lojaRef.collection('config').doc('config').set({
        'lojaId': slug,
        'slug': slug,
        'nome': 'Minha Loja',
        'layoutCatalogo': CatalogLayoutConfig.defaultForNewStoreDocuments,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await lojaRef.collection('draft_config').doc('config').set({
        'lojaId': slug,
        'slug': slug,
        'nome': 'Minha Loja',
        'layoutCatalogo': CatalogLayoutConfig.defaultForNewStoreDocuments,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Criar member admin
      await lojaRef.collection('members').doc(uid).set({
        'role': 'admin',
        'email': email,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ [TENANT] Loja criada: $slug');
    } else {
      // se já existe loja com esse id, garantimos que o ownerUid
      // seja esse usuário (senão, seria loja de outra pessoa)
      final data = lojaSnap.data() as Map<String, dynamic>;
      final ownerUid = (data['ownerUid'] ?? '').toString();
      if (ownerUid.isNotEmpty && ownerUid != uid) {
        // Se isso acontecer, significa que esse slug já é de outra pessoa.
        // Você pode trocar a estratégia aqui (ex.: adicionar sufixo numérico).
        throw StateError('Este ID de loja já pertence a outro usuário.');
      }
    }

    // 4) ✅ Vincula definitivamente a loja no doc users/{uid}
    await userRef.set({
      'store_id': slug,
      'ownerOf': slug,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 5) ✅ NOVO: Sincroniza usuarios/{email}.store_id (padrão igual natypolylopes1997)
    final emailNorm = email.toLowerCase().trim();
    if (emailNorm.isNotEmpty) {
      await _db.collection('usuarios').doc(emailNorm).set({
        'store_id': slug,
        'authUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ [TENANT] Sincronizado usuarios/$emailNorm.store_id = $slug');
    }

    return slug;
  }

  /// Mantido para compatibilidade com código antigo:
  /// LojaPreconfigScreen chama ensureTenantForUser.
  ///
  /// Agora ele apenas delega para ensureStoreForUser.
  Future<String> ensureTenantForUser(String uid) async {
    final email = FirebaseAuth.instance.currentUser?.email;
    return ensureStoreForUser(uid, email: email);
  }

  // ---------- Utils ----------

  String _makeSlug(String s) {
    var t = s.toLowerCase().trim();
    t = t.split('@').first;
    t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    t = t.replaceAll(RegExp(r'-{2,}'), '-');
    t = t.replaceAll(RegExp(r'^-+|-+$'), '');
    return t.isEmpty ? 'loja' : t;
  }
}