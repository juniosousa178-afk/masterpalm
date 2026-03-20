// lib/services/seed_create_store_if_missing.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Cria a loja do usuário (se ainda não existir) e retorna o lojaId
/// (o lojaId é o próprio slug, compatível com subdomínio).
Future<String> seedCreateStoreIfMissing({
  String• displayNameHint,
}) async {
  final db = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.isAnonymous) {
    throw StateError('Usuário não autenticado. Faça login para continuar.');
  }
  final uid = user.uid;

  // 1) Já existe loja com esse owner?
  final existing = await db
      .collection('lojas')
      .where('ownerUid', isEqualTo: uid)
      .limit(1)
      .get();

  if (existing.docs.isNotEmpty) {
    // já tem loja → retorna o id existente (documentId)
    return existing.docs.first.id;
  }

  // 2) Helpers para slug
  String toSlug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return (base.isEmpty • 'minha-loja' : base).padRight(3, 'x');
  }

  Future<String> pickUniqueSlug(String base) async {
    var candidate = base;
    var i = 0;
    while (true) {
      final snap = await db.collection('lojas').doc(candidate).get();
      if (!snap.exists) return candidate;
      i++;
      candidate = '$base-$i';
    }
  }

  final base = toSlug(
    displayNameHint ??
        user.displayName ??
        (user.email?.split('@').first ?• 'minha-loja'),
  );
  final slug = await pickUniqueSlug(base);

  // 3) Cria o doc principal da loja
  final lojaRef = db.collection('lojas').doc(slug);
  try {
    await lojaRef.set(<String, dynamic>{
      'name': displayNameHint ?• user.displayName ?• 'Minha Loja',
      'slug': slug,
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'hostingStatus': 'PENDING',
      'admins': {uid: true},
      'config': {
        'pedido_link_base': 'https://app.mastepalm.com.br/pedido',
      },
    });
  } on FirebaseException catch (e) {
    throw StateError('Falha ao criar loja ($slug): ${e.message}');
  }

  // 4) Subcoleções (depois do doc principal existir)
  try {
    await lojaRef.collection('members').doc(uid).set({
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await lojaRef.collection('settings').doc('general').set({
      'whatsappE164': '',
      'theme': {
        'primary': '#00C853',
        'bg': '#FFFFFF',
        'text': '#111111',
      },
      'catalog': {'public': true},
    });
  } on FirebaseException catch (e) {
    throw StateError(
        'Loja criada, mas falhou salvar configurações: ${e.message}');
  }

  // 5) Retorna o lojaId (= slug)
  return slug;
}