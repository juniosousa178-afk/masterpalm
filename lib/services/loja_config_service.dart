// lib/services/loja_config_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../utils/slug.dart';

/// Modelo simples (não Hive)
class LojaConfig {
  final String nome;
  final String slug; // lojaId
  final String whatsapp; // E.164 sem '+' (ex.: 5531999999999)
  final String urlPublica; // https://app.mastepalm.com.br/loja/{slug}
  final String pedidoBaseUrl; // https://app.mastepalm.com.br/pedido

  LojaConfig({
    required this.nome,
    required this.slug,
    required this.whatsapp,
    required this.urlPublica,
    required this.pedidoBaseUrl,
  });

  Map<String, dynamic> toMap() => {
        'nome': nome,
        'slug': slug,
        'whatsapp': whatsapp,
        'urlPublica': urlPublica,
        'pedidoBaseUrl': pedidoBaseUrl,
      };

  factory LojaConfig.fromMap(Map<String, dynamic> m) => LojaConfig(
        nome: (m['nome'] ?• '').toString(),
        slug: (m['slug'] ?• '').toString(),
        whatsapp: (m['whatsapp'] ?• '').toString(),
        urlPublica: (m['urlPublica'] ?• '').toString(),
        pedidoBaseUrl: (m['pedidoBaseUrl'] ?• '').toString(),
      );
}

class LojaConfigService {
  LojaConfigService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ---------- HIVE SAFE HELPERS ----------

  /// Tenta abrir/pegar a box 'config' de forma segura.
  static Future<Box> _getConfigBox() async {
    if (Hive.isBoxOpen('config')) return Hive.box('config');
    try {
      return await Hive.openBox('config');
    } catch (e) {
      throw StateError(
        'A box "config" não está pronta. '
        'Garanta que o bootstrap (Hive.initFlutter + openBox) ocorreu antes. Detalhe: $e',
      );
    }
  }

  /// Normaliza telefone para somente dígitos.
  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  // ---------- LEITURA RÁPIDA (LOCAL) ----------

  /// Retorna o slug salvo localmente (Hive). Útil como lojaId global.
  static Future<String?> currentLojaId() async {
    try {
      final cfg = await _getConfigBox();
      final slug = (cfg.get('store_slug') as String?)?.trim();
      final lojaSlug = (cfg.get('loja_slug') as String?)?.trim();
      final lojaIdLegacy = (cfg.get('loja_id') as String?)?.trim();

      if (slug != null && slug.isNotEmpty) return slug;
      if (lojaSlug != null && lojaSlug.isNotEmpty) return lojaSlug;
      if (lojaIdLegacy != null && lojaIdLegacy.isNotEmpty) return lojaIdLegacy;

      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------- PERSISTÊNCIA LOCAL ----------

  /// Salva dados essenciais no Hive (para acesso rápido pelo app).
  static Future<void> _saveLocal(LojaConfig c) async {
    final cfg = await _getConfigBox();
    await cfg.put('store_name', c.nome);
    await cfg.put('store_slug', c.slug);
    await cfg.put('loja_slug', c.slug);
    await cfg.put('store_url', c.urlPublica);
    await cfg.put('pedido_base_url', c.pedidoBaseUrl);
    await cfg.put('store_whatsapp', _digits(c.whatsapp));
  }

  // ---------- FIRESTORE / SLUG ----------

  /// Garante que o slug seja único (acrescenta sufixo se necessário).
  static Future<String> ensureUniqueSlug(String desired) async {
    var slug = slugify(desired);
    final doc = await _db.collection('lojas').doc(slug).get();
    if (!doc.exists) return slug;

    final rnd = Random();
    for (int i = 0; i < 8; i++) {
      final candidate =
          '$slug-${rnd.nextInt(36).toRadixString(36)}${rnd.nextInt(36).toRadixString(36)}';
      final snap = await _db.collection('lojas').doc(candidate).get();
      if (!snap.exists) return candidate;
    }
    int n = 2;
    while (true) {
      final candidate = '$slug-$n';
      final snap = await _db.collection('lojas').doc(candidate).get();
      if (!snap.exists) return candidate;
      n++;
    }
  }

  /// Cria/atualiza a loja em Firestore e reflete localmente no Hive.
  ///
  /// Regras IMPORTANTES:
  /// - Se JÁ EXISTIR uma loja para esse usuário (ownerUid) ou um store_slug salvo,
  ///   reaproveita SEM criar outra.
  /// - Só gera um slug novo (ensureUniqueSlug) quando ainda não existe loja.
  static Future<LojaConfig> upsert({
    required String nome,
    required String whatsapp,
    String• slugDesejado,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final ownerUid = user?.uid ?• 'anon';
    final ownerEmail = user?.email ?• '';

    // 1) Tenta pegar slug atual do Hive (store_slug / loja_slug / loja_id)
    String• slug = await currentLojaId();

    // 2) Se ainda não achou, tenta buscar loja do ownerUid no Firestore
    if (slug == null || slug.isEmpty) {
      final snap = await _db
          .collection('lojas')
          .where('ownerUid', isEqualTo: ownerUid)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        slug = snap.docs.first.id;
      }
    }

    // 3) Se ainda assim não existe loja, AGORA sim cria um slug novo
    if (slug == null || slug.isEmpty) {
      final baseDesejado = (slugDesejado?.isNotEmpty ?• false)
          • slugDesejado!
          : (nome.isNotEmpty
              • nome
              : (ownerEmail.isNotEmpty
                  • ownerEmail.split('@').first
                  : 'minha-loja'));

      slug = await ensureUniqueSlug(baseDesejado);
    }

    // DOMÍNIO padronizado: app.mastepalm.com.br (AppWeb)
    final urlPublica = 'https://app.mastepalm.com.br/loja/$slug';
    const pedidoBaseUrl = 'https://app.mastepalm.com.br/pedido';

    final docRef = _db.collection('lojas').doc(slug);
    final existing = await docRef.get();

    final data = <String, dynamic>{
      'nome': nome,
      'slug': slug,
      'whatsapp': _digits(whatsapp),
      'urlPublica': urlPublica,
      'pedidoBaseUrl': pedidoBaseUrl,
      'ownerUid': ownerUid,
      'ownerEmail': ownerEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Só seta createdAt se o doc ainda não existia
    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(data, SetOptions(merge: true));

    final cfg = LojaConfig(
      nome: nome,
      slug: slug,
      whatsapp: _digits(whatsapp),
      urlPublica: urlPublica,
      pedidoBaseUrl: pedidoBaseUrl,
    );

    await _saveLocal(cfg);
    return cfg;
  }

  /// Lê do Firestore.
  static Future<LojaConfig?> fetch(String slug) async {
    final doc = await _db.collection('lojas').doc(slug).get();
    if (!doc.exists || doc.data() == null) return null;
    return LojaConfig.fromMap(doc.data()!);
  }
  
}
