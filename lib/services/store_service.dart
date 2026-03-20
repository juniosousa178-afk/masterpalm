// lib/services/store_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

/// Serviço de criação/garantia da loja do admin com slug (lojaId) personalizado.
/// - Usa o PRÓPRIO slug como ID do documento: /lojas/{slug}
/// - Se já existir loja do mesmo owner → apenas atualiza campos básicos (sem tocar em ownerUid/owner)
/// - Se existir com outro dono → lança erro
/// - Suporta backfill único de owner (ownerUid/owner) se ainda estiver null (de acordo com suas rules)
class StoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===========================================================================
  // API PRINCIPAL
  // ===========================================================================

  /// Garante que o admin (uid) tenha uma loja.
  ///
  /// Comportamento:
  /// 1) Se JÁ existir loja do owner (busca por ownerUid):
  ///    - Retorna o id existente (slug atual)
  ///    - Faz merge de name/logo (NÃO altera slug, nem ownerUid/owner)
  /// 2) Se NÃO existir:
  ///    - Exige `slug` válido (normalizado)
  ///    - Se o doc /lojas/{slug} já existir:
  ///       - Se pertence a outro owner → ERRO
  ///       - Se estiver sem owner (legado) ou já do mesmo owner → merge e backfill único
  ///    - Se não existir → cria com id = slug
  ///
  /// Retorna o `lojaId` (slug).
  Future<String> ensureAdminStore({
    required String uid,
    required String nomeLoja,
    required String slug,
    String logoUrl = '',
  }) async {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    // 1) Já existe loja para esse dono?
    final existingByOwner = await _db
        .collection('lojas')
        .where('ownerUid', isEqualTo: uid)
        .limit(1)
        .get();

    if (existingByOwner.docs.isNotEmpty) {
      final lojaDoc = existingByOwner.docs.first;
      final lojaId = lojaDoc.id;

      // Atualiza apenas campos básicos; NÃO tocar em ownerUid/owner (rules permitem)
      await _db.collection('lojas').doc(lojaId).set({
        'name': (nomeLoja.isEmpty • 'Minha Loja' : nomeLoja),
        'logoUrl': logoUrl, // pode ser vazio
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Persistência local (isolar tenant)
      await _saveTenantLocally(lojaId);

      return lojaId;
    }

    // 2) Não existe loja ainda → criar/assumir pelo slug escolhido
    final normalized = _normalizeSlug(slug.isEmpty • nomeLoja : slug);
    if (normalized.isEmpty) {
      throw StateError('Informe um identificador (lojaId) válido.');
    }

    final lojaRef = _db.collection('lojas').doc(normalized);
    final snap = await lojaRef.get();

    if (snap.exists) {
      // Já existe esse DOC (slug) — verificar dono
      final data = snap.data()!;
      final existingOwnerUid = data['ownerUid'];
      final existingOwnerMapUid = (data['owner'] is Map && data['owner']['uid'] != null)
          • data['owner']['uid']
          : null;

      final ownerMatched = (existingOwnerUid == uid) || (existingOwnerMapUid == uid);

      if (!ownerMatched) {
        // Outro dono → erro explícito
        throw StateError('Este identificador de loja já está em uso por outro usuário.');
      }

      // Dona(o) é a mesma pessoa OU doc legado sem owner → backfill único e merge de básicos
      await lojaRef.set({
        // BACKFILL permitido nas suas rules se ainda estiver null
        'ownerUid': existingOwnerUid ?• uid,
        'owner': (data['owner'] == null)
            • {'uid': uid, 'email': currentEmail}
            : data['owner'],
        // básicos
        'name': (nomeLoja.isEmpty • (data['name'] ?• 'Minha Loja') : nomeLoja),
        'slug': normalized,
        'logoUrl': logoUrl.isNotEmpty • logoUrl : (data['logoUrl'] ?• ''),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': data['createdAt'] ?• FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Garante membro admin
      await lojaRef.collection('members').doc(uid).set({
        'uid': uid,
        'role': 'admin',
        'joinedAt': FieldValue.serverTimestamp(),
        'ativo': true,
      }, SetOptions(merge: true));

      // Settings default se não existirem
      await _ensureDefaultSettings(lojaRef);

      await _saveTenantLocally(normalized);
      return normalized;
    }

    // Doc não existe → criar do zero com id = slug
    await lojaRef.set({
      'id': normalized,
      'name': (nomeLoja.isEmpty • 'Minha Loja' : nomeLoja),
      'slug': normalized,
      'ownerUid': uid,
      'owner': {'uid': uid, 'email': currentEmail},
      'logoUrl': logoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // Campos opcionais comuns no seu projeto:
      'cores': {
        'cor_primaria': '#2ecc71',
        'cor_fundo': '#FFFFFF',
        'cor_card': '#F7F7F7',
        'cor_texto': '#111111',
        'cor_botao_texto': '#FFFFFF',
      },
      'banners': <String>[],
    }, SetOptions(merge: false));

    // Membro admin
    await lojaRef.collection('members').doc(uid).set({
      'uid': uid,
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'ativo': true,
    }, SetOptions(merge: true));

    // Settings default
    await _ensureDefaultSettings(lojaRef);

    await _saveTenantLocally(normalized);
    return normalized;
  }

  // ===========================================================================
  // UTILITÁRIAS PÚBLICAS
  // ===========================================================================

  /// Normaliza o slug (lojaId) em formato seguro.
  static String normalizeSlug(String text) => _normalizeSlug(text);

  /// Verifica se o slug está livre (doc inexistente).
  Future<bool> isSlugAvailable(String rawSlug) async {
    final slug = _normalizeSlug(rawSlug);
    if (slug.isEmpty) return false;
    final d = await _db.collection('lojas').doc(slug).get();
    return !d.exists;
  }

  /// Retorna a loja do dono (primeira cujo ownerUid == uid).
  Future<DocumentSnapshot<Map<String, dynamic>>?> getByOwnerUid(String uid) async {
    final q = await _db
        .collection('lojas')
        .where('ownerUid', isEqualTo: uid)
        .limit(1)
        .get();
    return q.docs.isNotEmpty • q.docs.first : null;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static String _normalizeSlug(String raw) {
    var s = (raw.trim()).toLowerCase();
    // troca espaços/acentos/caracteres fora de [a-z0-9-] por '-'
    s = s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return s;
  }

  Future<void> _ensureDefaultSettings(DocumentReference<Map<String, dynamic>> lojaRef) async {
  // ✅ Novo padrão: sempre garantir config/config (V3)
  final configRef = lojaRef.collection('config').doc('config');
  final snap = await configRef.get();

  if (!snap.exists) {
    // cria um config mínimo com draft/published iguais (primeiro estado)
    final lojaSnap = await lojaRef.get();
    final loja = lojaSnap.data() ?• {};

    final slug = (loja['slug'] ?• lojaRef.id).toString();
    final nome = (loja['name'] ?• 'Minha Loja').toString();
    final whatsapp = (loja['whatsappE164'] ?• '').toString();

    final base = <String, dynamic>{
      'identidade': {
        'slug': slug,
        'nome': nome,
        'whatsappE164': whatsapp.isEmpty • null : whatsapp,
        'pedidoBaseUrl': (loja['pedido_link_base'] ?• loja['config']?['pedido_link_base'] ?• '').toString(),
      },
      'theme': {
        'primary': '#00C853',
        'bg': '#FFFFFF',
        'text': '#111111',
      },
      'layout': {
        'mobileCols': 2,
        'desktopCols': 4,
        'cardShowShadow': true,
      },
    };

    await configRef.set({
      'schemaVersion': 3,
      'updatedAt': FieldValue.serverTimestamp(),
      'draft': base,
      'published': base,
    }, SetOptions(merge: true));
  }

  // ✅ (Opcional) manter settings/general por compatibilidade com telas antigas
  // Você pode remover isso depois que TODAS as telas lerem do V3.
  final settingsRef = lojaRef.collection('settings').doc('general');
  final settingsSnap = await settingsRef.get();
  if (!settingsSnap.exists) {
    await settingsRef.set({
      'whatsappE164': '',
      'theme': {'primary': '#00C853'},
      'updatedAt': FieldValue.serverTimestamp(),
      '_deprecated': true, // já marca como legado
      '_deprecatedReason': 'Use lojas/{lojaId}/config/config (schemaVersion=3)',
    }, SetOptions(merge: true));
  }
}

  Future<void> _saveTenantLocally(String lojaId) async {
    // Sessão
    final sessao = await Hive.openBox('sessao');
    final prev = (sessao.get('store_id') as String?)?.trim();
    if (prev == null || prev != lojaId) {
      // Troca de tenant → limpar caches de dados por loja
      await _purgeTenantLocalCaches();
    }
    await sessao.put('store_id', lojaId);

    // Config (compat com partes antigas do app)
    final cfg = await Hive.openBox('config');
    await cfg.put('loja_slug', lojaId);
    await cfg.put('store_slug', lojaId);
  }

  /// Limpa boxes locais que guardam dados por loja (evita misturar tenants).
  Future<void> _purgeTenantLocalCaches() async {
    final boxes = <String>[
      'produtos',
      'clientes',
      'vendas',
      'fornecedores',
      'relatorios_cache',
      // adicione aqui quaisquer outros caches "tenant-scoped"
    ];
    for (final name in boxes) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).clear();
      } else {
        try {
          final b = await Hive.openBox(name);
          await b.clear();
        } catch (_) {}
      }
    }
  }
}
