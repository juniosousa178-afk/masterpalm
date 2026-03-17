// lib/services/migrate_collections_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/store_resolver_facade.dart';

class MigrateCollectionsService {
  final _db = FirebaseFirestore.instance;

  /// Executa TODAS as migrações necessárias para corrigir catálogo,
  /// fretes, cupons e limpeza de coleções antigas.
  Future<void> migrateAll() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
if (lojaId == null) {
  // Tratar caso não exista loja
  throw StateError('Nenhuma loja ativa');
}
    final base = _db.collection('lojas').doc(lojaId);

    debugPrint('🚀 Iniciando MIGRAÇÃO COMPLETA da loja: $lojaId');

    await _fixProdutos(base);
    await _createCupons(base);
    await _createFreteConfig(base);

    await _cleanupDeprecated(base);

    debugPrint('🎉 Migração finalizada com sucesso para loja: $lojaId');
  }

  // ----------------------------------------------------------
  // 1) Corrige produtos e move tudo para /draft_produtos e /produtos
  // ----------------------------------------------------------
  Future<void> _fixProdutos(DocumentReference base) async {
    debugPrint('➡️ Migrando coleções de produtos...');

    final deprecated = [
      'products',
      'produtos_draft',
      'produtos_publicos',
      'draft_config',
    ];

    // Move /produtos_draft -> /draft_produtos
    await _moveCollection(
      from: base.collection('produtos_draft'),
      to: base.collection('draft_produtos'),
    );

    // Move /products -> /produtos
    await _moveCollection(
      from: base.collection('products'),
      to: base.collection('produtos'),
    );

    debugPrint('✔ Coleções de produtos unificadas.');

    // Limpa lixo
    for (final col in deprecated) {
      await base.collection(col).get().then((s) async {
        for (final d in s.docs) {
          await d.reference.delete();
        }
      });
      debugPrint('🗑️ Removido: $col');
    }
  }

  // ----------------------------------------------------------
  // 2) Cria coleção CUPONS se não existir
  // ----------------------------------------------------------
  Future<void> _createCupons(DocumentReference base) async {
    debugPrint('➡️ Verificando coleção CUPONS...');

    final cuponsRef = base.collection('cupons');
    final snap = await cuponsRef.limit(1).get();

    if (snap.docs.isEmpty) {
      await cuponsRef.doc('exemplo10').set({
        'ativo': false,
        'tipo': 'percentual',
        'valor': 10,
        'codigo': 'EXEMPLO10',
        'expiraEm': null,
      });
      debugPrint('✔ Coleção cupons criada e inicializada.');
    } else {
      debugPrint('✔ Coleção cupons já existe.');
    }
  }

  // ----------------------------------------------------------
  // 3) Cria FRETE_CONFIG se não existir
  // ----------------------------------------------------------
  Future<void> _createFreteConfig(DocumentReference base) async {
    debugPrint('➡️ Verificando FRETE_CONFIG...');

    final ref = base.collection('config').doc('frete_config');

    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'provider': 'manual',
        'melhor_envio_token': '',
        'correios_user': '',
        'correios_senha': '',
        'frenet_token': '',
        'fretes': [
          {'nome': 'Retirada', 'valor': 0},
          {'nome': 'Entrega local', 'valor': 10},
        ],
      });
      debugPrint('✔ Frete_config criado.');
    } else {
      debugPrint('✔ Frete_config já existe.');
    }
  }

  // ----------------------------------------------------------
  // MOVE COLLECTION (GENÉRICO)
  // ----------------------------------------------------------
  Future<void> _moveCollection({
    required CollectionReference from,
    required CollectionReference to,
  }) async {
    final snap = await from.get();
    for (final doc in snap.docs) {
      await to.doc(doc.id).set(doc.data(), SetOptions(merge: true));
    }
  }

  // ----------------------------------------------------------
  // 4) Remove coleções antigas
  // ----------------------------------------------------------
  Future<void> _cleanupDeprecated(DocumentReference base) async {
    final deprecated = [
      'products',
      'produtos_draft',
      'draft_config',
      'produtos_publicos',
    ];

    debugPrint('➡️ Limpando coleções obsoletas...');

    for (final col in deprecated) {
      final snap = await base.collection(col).get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
      debugPrint('🗑️ Coleção removida: $col');
    }

    debugPrint('✔ Limpeza concluída.');
  }
}
