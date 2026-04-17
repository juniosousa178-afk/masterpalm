// lib/services/catalog_publish_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../services/store_resolver_facade.dart';
import '../services/pagamentos_service.dart';

const String _keyCatalogoPrecisaAtualizar = 'catalogo_precisa_atualizar';

class CatalogPublishService {
  CatalogPublishService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Marca que houve alteração manual (foto, preço, descrição, etc.) e o catálogo deve ser atualizado.
  static Future<void> marcarCatalogoPrecisaAtualizar() async {
    final box = await Hive.openBox('config');
    await box.put(_keyCatalogoPrecisaAtualizar, true);
  }

  /// Remove a marca após publicar o catálogo.
  static Future<void> limparCatalogoPrecisaAtualizar() async {
    final box = await Hive.openBox('config');
    await box.delete(_keyCatalogoPrecisaAtualizar);
  }

  /// Indica se há alterações pendentes para publicar no catálogo.
  static Future<bool> get catalogoPrecisaAtualizar async {
    final box = await Hive.openBox('config');
    return box.get(_keyCatalogoPrecisaAtualizar, defaultValue: false) as bool;
  }

  /// Campos de custo / margem nunca podem permanecer em `produtos` (catálogo público).
  /// Com `merge: true`, omitir a chave não apaga valor antigo — usa [FieldValue.delete].
  static Map<String, dynamic> _payloadCatalogoLiveSemCusto(
    Map<String, dynamic> draftData,
  ) {
    final m = Map<String, dynamic>.from(draftData);
    for (final k in const [
      'custoReal',
      'custo',
      'precoCusto',
      'margemLucro',
      'margem',
    ]) {
      m.remove(k);
    }
    m['custoReal'] = FieldValue.delete();
    m['custo'] = FieldValue.delete();
    m['precoCusto'] = FieldValue.delete();
    return m;
  }

  /// Normaliza se o produto deve aparecer no catálogo web
  static bool _isAtivoForWeb(Map<String, dynamic> data) {
    final publicar  = data['publicar'] == true || data['catalogo'] == true;
    final ativoFlag = data['ativo'] != false; // se vier false, respeita
    final estoque   = (data['estoque_atual'] ??
                      data['estoque'] ??
                      data['qtdEstoque'] ??
                      0) as num;

    // Só aparece se:
    //  - estiver marcado para catálogo (publicar/catalogo == true)
    //  - e tiver estoque > 0
    //  - e não estiver explicitamente desativado
    return publicar && ativoFlag && estoque > 0;
  }

  /// Promove UM item do draft para live (mantém o mesmo docId).
  /// Se não existir no draft, remove do live.
  ///
  /// [lojaIdOverride] evita re-resolver loja quando o chamador já tem o id da tela ativa.
  static Future<void> promoteOne(String docId, {String? lojaIdOverride}) async {
    final resolved = lojaIdOverride?.trim();
    final lojaId = (resolved != null && resolved.isNotEmpty)
        ? resolved
        : await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      throw StateError('Nenhuma loja ativa');
    }
    final base = _db.collection('lojas').doc(lojaId);
    final draftRef = base.collection('draft_produtos').doc(docId);
    final liveRef  = base.collection('produtos').doc(docId);

    final snap = await draftRef.get();
    if (!snap.exists) {
      // foi apagado do draft => tira do catálogo web
      await liveRef.delete();
      return;
    }

    final draftData = Map<String, dynamic>.from(snap.data()!);

    final ativoWeb = _isAtivoForWeb(draftData);

    if (ativoWeb) {
      final data = _payloadCatalogoLiveSemCusto(draftData);
      data['ativo'] = ativoWeb;
      data['publicado'] = ativoWeb;
      data['updatedAt'] = FieldValue.serverTimestamp();
      await liveRef.set(data, SetOptions(merge: true));
    } else {
      // não atende as regras => some do catálogo web
      await liveRef.delete();
    }
  }

  /// Limite seguro de operações por commit (Firestore max 500).
  static const int _maxBatchOps = 450;

  /// Promove TODOS do draft para live; também faz "purge" de órfãos.
  /// Commits em chunks para não estourar o limite de 500 ops do Firestore.
  static Future<void> promoteAll() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      throw StateError('Nenhuma loja ativa');
    }
    final base = _db.collection('lojas').doc(lojaId);
    final draftCol = base.collection('draft_produtos');
    final liveCol = base.collection('produtos');

    final draft = await draftCol.get();
    final live = await liveCol.get();
    final draftIds = draft.docs.map((d) => d.id).toSet();

    WriteBatch batch = _db.batch();
    var opCount = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (opCount == 0) return;
      if (!force && opCount < _maxBatchOps) return;
      await batch.commit();
      if (kDebugMode) {
        debugPrint('📦 [PUBLISH-ALL] batch commit ops=$opCount (chunk)');
      }
      batch = _db.batch();
      opCount = 0;
    }

    for (final d in draft.docs) {
      final draftData = Map<String, dynamic>.from(d.data());
      final ativoWeb = _isAtivoForWeb(draftData);

      if (ativoWeb) {
        final data = _payloadCatalogoLiveSemCusto(draftData);
        data['ativo'] = ativoWeb;
        data['publicado'] = ativoWeb;
        data['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(liveCol.doc(d.id), data, SetOptions(merge: true));
      } else {
        batch.delete(liveCol.doc(d.id));
      }
      opCount++;
      await commitIfNeeded();
    }

    for (final l in live.docs) {
      if (!draftIds.contains(l.id)) {
        batch.delete(liveCol.doc(l.id));
        opCount++;
        await commitIfNeeded();
      }
    }

    await commitIfNeeded(force: true);
  }

  /// ✨ Publica configurações gerais do draft para live
  static Future<void> publishConfig() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null) {
      throw StateError('Nenhuma loja ativa');
    }

    final draftRef = _db.collection('lojas').doc(lojaId).collection('draft_config').doc('config');
    final liveRef = _db.collection('lojas').doc(lojaId).collection('config').doc('config');

    debugPrint('📖 [PUBLISH-CONFIG] Lendo draft: lojas/$lojaId/draft_config/config');
    final draftSnap = await draftRef.get();
    if (!draftSnap.exists) {
      debugPrint('⚠️ [PUBLISH-CONFIG] Nenhuma config draft encontrada');
      return;
    }

    final data = Map<String, dynamic>.from(draftSnap.data()!);
    data['publishedAt'] = FieldValue.serverTimestamp();
    data['publishedFrom'] = 'draft';

    debugPrint('💾 [PUBLISH-CONFIG] Salvando em LIVE: lojas/$lojaId/config/config (merge: true)');
    debugPrint('   Campos: ${data.keys.length} campos sendo publicados');
    await liveRef.set(data, SetOptions(merge: true));
    debugPrint('✅ [PUBLISH-CONFIG] Config publicado com sucesso!');
  }

  /// ✨ Publica configurações de pagamento do draft para live
  static Future<void> publishPayments() async {
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null) {
      throw StateError('Nenhuma loja ativa');
    }

    final draftRef = _db.collection('lojas').doc(lojaId).collection('draft_config').doc('payments');
    final liveRef = _db.collection('lojas').doc(lojaId).collection('config').doc('payments');

    debugPrint('📖 [PUBLISH-PAYMENTS] Lendo draft: lojas/$lojaId/draft_config/payments');
    final draftSnap = await draftRef.get();
    if (!draftSnap.exists) {
      debugPrint('⚠️ [PUBLISH-PAYMENTS] Nenhum payment draft encontrado');
      return;
    }

    final data = Map<String, dynamic>.from(draftSnap.data()!);
    data['publishedAt'] = FieldValue.serverTimestamp();

    debugPrint('💾 [PUBLISH-PAYMENTS] Salvando em LIVE: lojas/$lojaId/config/payments (merge: true)');
    debugPrint('   Campos: ${data.keys.length} campos sendo publicados');
    await liveRef.set(data, SetOptions(merge: true));
    await PagamentosService.syncPaymentsPublic(lojaId);
    debugPrint('✅ [PUBLISH-PAYMENTS] Payments publicado com sucesso!');
  }

  /// ✨ Publica TUDO de uma vez (config + payments + produtos + campanhas)
  static Future<Map<String, dynamic>> publishEverything() async {
    final errors = <String>[];
    final results = <String, dynamic>{
      'success': true,
      'errors': errors,
      'config': false,
      'payments': false,
      'products': 0,
      'campaigns': 0,
    };

    try {
      final lojaId = await StoreResolverFacade.resolveForAdminApp();
      if (lojaId == null) {
        results['success'] = false;
        errors.add('LojaId não encontrado');
        return results;
      }

      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('🚀 [PUBLISH-ALL] INICIANDO PUBLICAÇÃO COMPLETA');
      debugPrint('   Loja: $lojaId');
      debugPrint('   Timestamp: ${DateTime.now()}');
      debugPrint('═══════════════════════════════════════════════════════════');

      // 1. Publicar configurações gerais
      try {
        debugPrint('\n📋 [PUBLISH-ALL] Etapa 1/4: Publicando configurações gerais...');
        await publishConfig();
        results['config'] = true;
        debugPrint('✅ [PUBLISH-ALL] Etapa 1/4: Configurações publicadas');
      } catch (e) {
        errors.add('Erro ao publicar config: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro config (type=${e.runtimeType})');
      }

      // 2. Publicar configurações de pagamento
      try {
        debugPrint('\n💳 [PUBLISH-ALL] Etapa 2/4: Publicando configurações de pagamento...');
        await publishPayments();
        results['payments'] = true;
        debugPrint('✅ [PUBLISH-ALL] Etapa 2/4: Pagamentos publicados');
      } catch (e) {
        errors.add('Erro ao publicar payments: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro payments (type=${e.runtimeType})');
      }

      // 3. Publicar produtos (usando método existente)
      try {
        debugPrint('\n📦 [PUBLISH-ALL] Etapa 3/4: Publicando produtos...');
        await promoteAll();

        // Contar quantos foram publicados
        final liveSnap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('produtos')
            .get();
        results['products'] = liveSnap.docs.length;
        debugPrint('✅ [PUBLISH-ALL] Etapa 3/4: ${results['products']} produtos publicados');
      } catch (e) {
        errors.add('Erro ao publicar produtos: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro produtos (type=${e.runtimeType})');
      }

      // 4. Verificar campanhas ativas (já estão na mesma collection)
      try {
        debugPrint('\n🎯 [PUBLISH-ALL] Etapa 4/4: Verificando campanhas ativas...');
        final campaignsSnap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('campanhas_sorteio')
            .where('ativa', isEqualTo: true)
            .get();

        results['campaigns'] = campaignsSnap.docs.length;
        debugPrint('✅ [PUBLISH-ALL] Etapa 4/4: ${results['campaigns']} campanhas ativas encontradas');
      } catch (e) {
        errors.add('Erro ao verificar campanhas: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro campanhas (type=${e.runtimeType})');
      }

      if (errors.isNotEmpty) {
        results['success'] = false;
      }

      debugPrint('\n═══════════════════════════════════════════════════════════');
      debugPrint('🎉 [PUBLISH-ALL] PUBLICAÇÃO COMPLETA FINALIZADA');
      debugPrint('   ✅ Config: ${results['config']}');
      debugPrint('   ✅ Payments: ${results['payments']}');
      debugPrint('   📦 Products: ${results['products']}');
      debugPrint('   🎯 Campaigns: ${results['campaigns']}');
      debugPrint('   ⚠️  Errors: ${errors.length}');
      if (errors.isNotEmpty) {
        debugPrint('   ❌ Detalhes dos erros:');
        for (var i = 0; i < errors.length; i++) {
          debugPrint('      ${i + 1}. ${errors[i]}');
        }
      }
      debugPrint('═══════════════════════════════════════════════════════════\n');

      return results;
    } catch (e) {
      debugPrint('❌ [PUBLISH-ALL] Erro geral (type=${e.runtimeType})');
      results['success'] = false;
      errors.add('Erro geral: $e');
      return results;
    }
  }
}