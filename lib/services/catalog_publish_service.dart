import 'stock_catalog_backend_service.dart';
// lib/services/catalog_publish_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../screens/public_catalog/catalog_estoque_helper.dart';

import '../services/store_resolver_facade.dart';
import '../services/pagamentos_service.dart';

const String _keyCatalogoPrecisaAtualizar = 'catalogo_precisa_atualizar';
const String _keyPendenciasSyncAposEstoque = 'catalogo_web_apos_estoque_pendente';

class CatalogPublishService {
  CatalogPublishService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static bool get usaBackendConfiavel => debugFirestoreOverride == null;

  @visibleForTesting
  static Future<void> Function(String lojaId)? debugSyncPaymentsPublicOverride;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static Future<String> _resolveLojaId({String? lojaIdOverride}) async {
    final resolved = lojaIdOverride?.trim();
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      throw StateError('Nenhuma loja ativa');
    }
    return lojaId;
  }

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

  /// IDs de produto cuja sync do catálogo falhou após mutação de estoque.
  /// Persistido no Hive (`config`) — sobrevive ao fechar o app.
  static Future<Map<String, Set<String>>> lerPendenciasSyncAposEstoque() async {
    final box = await Hive.openBox('config');
    return _decodePendenciasSyncAposEstoque(box.get(_keyPendenciasSyncAposEstoque));
  }

  /// Acumula pendências por loja e acende o FAB "Atualizar catálogo".
  static Future<void> registrarPendenciaSyncAposEstoque({
    required String lojaId,
    required Iterable<String> productIds,
  }) async {
    final li = lojaId.trim();
    final ids = productIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (li.isEmpty || ids.isEmpty) return;
    await marcarCatalogoPrecisaAtualizar();
    final box = await Hive.openBox('config');
    final current = _decodePendenciasSyncAposEstoque(
      box.get(_keyPendenciasSyncAposEstoque),
    );
    current.putIfAbsent(li, () => <String>{}).addAll(ids);
    await box.put(_keyPendenciasSyncAposEstoque, _encodePendenciasSyncAposEstoque(current));
  }

  /// Remove IDs já sincronizados com sucesso. Não limpa o FAB sozinha
  /// (outras alterações de catálogo podem coexistir).
  static Future<void> removerPendenciaSyncAposEstoque({
    required String lojaId,
    required Iterable<String> productIds,
  }) async {
    final li = lojaId.trim();
    final ids = productIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (li.isEmpty || ids.isEmpty) return;
    final box = await Hive.openBox('config');
    final current = _decodePendenciasSyncAposEstoque(
      box.get(_keyPendenciasSyncAposEstoque),
    );
    final remaining = current[li];
    if (remaining == null) return;
    remaining.removeAll(ids);
    if (remaining.isEmpty) {
      current.remove(li);
    }
    if (current.isEmpty) {
      await box.delete(_keyPendenciasSyncAposEstoque);
    } else {
      await box.put(
        _keyPendenciasSyncAposEstoque,
        _encodePendenciasSyncAposEstoque(current),
      );
    }
  }

  static Map<String, Set<String>> _decodePendenciasSyncAposEstoque(dynamic raw) {
    final out = <String, Set<String>>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final loja = key.toString().trim();
      if (loja.isEmpty) return;
      final ids = <String>{};
      if (value is List) {
        for (final e in value) {
          final id = e.toString().trim();
          if (id.isNotEmpty) ids.add(id);
        }
      }
      if (ids.isNotEmpty) out[loja] = ids;
    });
    return out;
  }

  static Map<String, List<String>> _encodePendenciasSyncAposEstoque(
    Map<String, Set<String>> current,
  ) {
    return {
      for (final e in current.entries)
        if (e.key.trim().isNotEmpty && e.value.isNotEmpty)
          e.key.trim(): e.value.toList(),
    };
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
    final publicar = data['publicar'] == true || data['catalogo'] == true;
    final ativoFlag = data['ativo'] != false; // se vier false, respeita
    final stock = CatalogEstoqueHelper.processStockFromFirestoreMap(
      data,
      isCombo: data['tipoProduto'] == 'combo',
    );
    return publicar && ativoFlag && stock.incluirNoCatalogo;
  }

  static int _readQtd(Map<String, dynamic> data) {
    final raw = data['quantidade'] ??
        data['estoque_atual'] ??
        data['estoque'] ??
        data['qtdEstoque'] ??
        0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim()) ?? 0;
  }

  static Map<String, dynamic> _asStringDynamicMap(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  /// Campo de grade no estoque: ausente → mantém draft; presente (mesmo `{}`) → canônico.
  static Map<String, dynamic> _mapGradeCanonico({
    required Map<String, dynamic>? estoqueData,
    required Map<String, dynamic> draftData,
    required String field,
  }) {
    if (estoqueData == null) {
      return _asStringDynamicMap(draftData[field]);
    }
    if (!estoqueData.containsKey(field)) {
      return _asStringDynamicMap(draftData[field]);
    }
    return _asStringDynamicMap(estoqueData[field]);
  }

  static List<String> _tamanhosCanonico({
    required Map<String, dynamic>? estoqueData,
    required Map<String, dynamic> draftData,
  }) {
    if (estoqueData != null && estoqueData.containsKey('tamanhos')) {
      final raw = estoqueData['tamanhos'];
      if (raw is List) {
        return raw.map((e) => e.toString()).where((t) => t.isNotEmpty).toList();
      }
    }
    final draftRaw = draftData['tamanhos'];
    if (draftRaw is List) {
      return draftRaw.map((e) => e.toString()).where((t) => t.isNotEmpty).toList();
    }
    return const [];
  }

  static Map<String, dynamic> _draftComEstoqueCanonico({
    required String lojaId,
    required String productId,
    required Map<String, dynamic> draftData,
    required Map<String, dynamic>? estoqueData,
  }) {
    if (estoqueData == null) return draftData;

    final merged = Map<String, dynamic>.from(draftData);
    final draftQtd = _readQtd(draftData);
    final estoqueQtd = _readQtd(estoqueData);

    if (kDebugMode && draftQtd != estoqueQtd) {
      debugPrint(
        '[catalog_publish_stock_conflict] '
        'lojaId=$lojaId productId=$productId draftQtd=$draftQtd estoqueQtd=$estoqueQtd',
      );
    }

    merged['quantidade'] = estoqueQtd;
    merged['estoque'] = estoqueQtd;
    merged['estoque_atual'] = estoqueQtd;
    merged['qtdEstoque'] = estoqueQtd;
    final rawVariacoes = estoqueData.containsKey('variacoes')
        ? estoqueData['variacoes']
        : draftData['variacoes'];
    merged['variacoes'] = rawVariacoes is Map
        ? _asStringDynamicMap(rawVariacoes)
        : null;
    merged['estoquePorTamanho'] = _mapGradeCanonico(
      estoqueData: estoqueData,
      draftData: draftData,
      field: 'estoquePorTamanho',
    );
    merged['estoquePorCor'] = _mapGradeCanonico(
      estoqueData: estoqueData,
      draftData: draftData,
      field: 'estoquePorCor',
    );
    merged['variacoesExtraTipo'] = _mapGradeCanonico(
      estoqueData: estoqueData,
      draftData: draftData,
      field: 'variacoesExtraTipo',
    );
    merged['tamanhos'] = _tamanhosCanonico(
      estoqueData: estoqueData,
      draftData: draftData,
    );
    final draftPrecoPorTamanho = draftData['precoPorTamanho'];
    final estoquePrecoPorTamanho = estoqueData['precoPorTamanho'];
    final draftTemPrecoPorTamanho =
        draftPrecoPorTamanho is Map && draftPrecoPorTamanho.isNotEmpty;
    if (!draftTemPrecoPorTamanho &&
        estoquePrecoPorTamanho is Map &&
        estoquePrecoPorTamanho.isNotEmpty) {
      merged['precoPorTamanho'] = _asStringDynamicMap(estoquePrecoPorTamanho);
    } else if (estoqueData.containsKey('precoPorTamanho') &&
        estoquePrecoPorTamanho is Map &&
        estoquePrecoPorTamanho.isNotEmpty) {
      merged['precoPorTamanho'] = _asStringDynamicMap(estoquePrecoPorTamanho);
    }
    return merged;
  }

  /// Fluxo canônico único de publicação do catálogo (config + payments + produtos + campanhas).
  /// Usado por Publicar catálogo, Atualizar catálogo e demais botões equivalentes.
  static Future<Map<String, dynamic>> publicarCatalogoCanonicamente({
    String? lojaIdOverride,
  }) =>
      publishEverything(lojaIdOverride: lojaIdOverride);

  @visibleForTesting
  static Map<String, dynamic> mergeDraftComEstoqueCanonicoForTest({
    required String lojaId,
    required String productId,
    required Map<String, dynamic> draftData,
    required Map<String, dynamic>? estoqueData,
  }) =>
      _draftComEstoqueCanonico(
        lojaId: lojaId,
        productId: productId,
        draftData: draftData,
        estoqueData: estoqueData,
      );

  /// Promove UM item do draft para live (mantém o mesmo docId).
  /// Se não existir no draft, remove do live.
  ///
  /// [lojaIdOverride] evita re-resolver loja quando o chamador já tem o id da tela ativa.
  static Future<void> promoteOne(String docId, {String? lojaIdOverride}) async {
    final lojaId = await _resolveLojaId(lojaIdOverride: lojaIdOverride);
    final base = _db.collection('lojas').doc(lojaId);
    if (debugFirestoreOverride == null) {
      await StockCatalogBackendService.publishOne(lojaId, docId);
      return;
    }
    // Existing fake-Firestore regression harness only; production uses server.
    final draftRef = base.collection('draft_produtos').doc(docId);
    final liveRef = base.collection('produtos').doc(docId);
    final estoqueRef = base.collection('estoque_produtos').doc(docId);

    // Firestore validates every document read at commit and retries conflicts.
    // No client clock/revision guess: the stock and draft snapshots used to
    // publish must still be current when the derived live write commits.
    await _db.runTransaction((tx) async {
      final snap = await tx.get(draftRef);
      final estoqueSnap = await tx.get(estoqueRef);
      if (!snap.exists) {
        tx.delete(liveRef);
        return;
      }
      final mergedData = _draftComEstoqueCanonico(
        lojaId: lojaId,
        productId: docId,
        draftData: Map<String, dynamic>.from(snap.data()!),
        estoqueData: estoqueSnap.exists
            ? Map<String, dynamic>.from(estoqueSnap.data()!)
            : null,
      );
      final ativoWeb = _isAtivoForWeb(mergedData);
      if (ativoWeb) {
        final data = _payloadCatalogoLiveSemCusto(mergedData);
        data['ativo'] = true;
        data['publicado'] = true;
        data['updatedAt'] = FieldValue.serverTimestamp();
        tx.set(liveRef, data, SetOptions(merge: true));
      } else {
        tx.delete(liveRef);
      }
    });
  }

  /// Enumera IDs, mas decide publicação/remoção em transação por produto.
  /// O snapshot da enumeração nunca é usado como payload de estoque.
  static Future<void> promoteAll({String? lojaIdOverride}) async {
    final lojaId = await _resolveLojaId(lojaIdOverride: lojaIdOverride);
    final base = _db.collection('lojas').doc(lojaId);
    if (debugFirestoreOverride == null) {
      await StockCatalogBackendService.publishAll(lojaId);
      return;
    }
    final draft = await base.collection('draft_produtos').get();
    final live = await base.collection('produtos').get();
    final ids = {...draft.docs.map((d) => d.id), ...live.docs.map((d) => d.id)};
    for (final id in ids) {
      await promoteOne(id, lojaIdOverride: lojaId);
    }
  }

  /// ✨ Publica configurações gerais do draft para live
  static Future<void> publishConfig({String? lojaIdOverride}) async {
    final lojaId = await _resolveLojaId(lojaIdOverride: lojaIdOverride);

    final draftRef = _db
        .collection('lojas')
        .doc(lojaId)
        .collection('draft_config')
        .doc('config');
    final liveRef =
        _db.collection('lojas').doc(lojaId).collection('config').doc('config');

    debugPrint(
        '📖 [PUBLISH-CONFIG] Lendo draft: lojas/$lojaId/draft_config/config');
    final draftSnap = await draftRef.get();
    if (!draftSnap.exists) {
      debugPrint('⚠️ [PUBLISH-CONFIG] Nenhuma config draft encontrada');
      return;
    }

    final data = Map<String, dynamic>.from(draftSnap.data()!);
    data['publishedAt'] = FieldValue.serverTimestamp();
    data['publishedFrom'] = 'draft';

    debugPrint(
        '💾 [PUBLISH-CONFIG] Salvando em LIVE: lojas/$lojaId/config/config (merge: true)');
    debugPrint('   Campos: ${data.keys.length} campos sendo publicados');
    await liveRef.set(data, SetOptions(merge: true));
    debugPrint('✅ [PUBLISH-CONFIG] Config publicado com sucesso!');
  }

  /// ✨ Publica configurações de pagamento do draft para live
  static Future<void> publishPayments({String? lojaIdOverride}) async {
    final lojaId = await _resolveLojaId(lojaIdOverride: lojaIdOverride);

    final draftRef = _db
        .collection('lojas')
        .doc(lojaId)
        .collection('draft_config')
        .doc('payments');
    final liveRef = _db
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('payments');

    debugPrint(
        '📖 [PUBLISH-PAYMENTS] Lendo draft: lojas/$lojaId/draft_config/payments');
    final draftSnap = await draftRef.get();
    if (!draftSnap.exists) {
      debugPrint('⚠️ [PUBLISH-PAYMENTS] Nenhum payment draft encontrado');
      return;
    }

    final data = Map<String, dynamic>.from(draftSnap.data()!);
    data['publishedAt'] = FieldValue.serverTimestamp();

    debugPrint(
        '💾 [PUBLISH-PAYMENTS] Salvando em LIVE: lojas/$lojaId/config/payments (merge: true)');
    debugPrint('   Campos: ${data.keys.length} campos sendo publicados');
    await liveRef.set(data, SetOptions(merge: true));
    if (debugSyncPaymentsPublicOverride != null) {
      await debugSyncPaymentsPublicOverride!(lojaId);
    } else {
      await PagamentosService.syncPaymentsPublic(lojaId);
    }
    debugPrint('✅ [PUBLISH-PAYMENTS] Payments publicado com sucesso!');
  }

  /// ✨ Publica TUDO de uma vez (config + payments + produtos + campanhas)
  static Future<Map<String, dynamic>> publishEverything({
    String? lojaIdOverride,
  }) async {
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
      final lojaId = await _resolveLojaId(lojaIdOverride: lojaIdOverride);

      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('🚀 [PUBLISH-ALL] INICIANDO PUBLICAÇÃO COMPLETA');
      debugPrint('   Loja: $lojaId');
      debugPrint('   Timestamp: ${DateTime.now()}');
      debugPrint('═══════════════════════════════════════════════════════════');

      // 1. Publicar configurações gerais
      try {
        debugPrint(
            '\n📋 [PUBLISH-ALL] Etapa 1/4: Publicando configurações gerais...');
        await publishConfig(lojaIdOverride: lojaId);
        results['config'] = true;
        debugPrint('✅ [PUBLISH-ALL] Etapa 1/4: Configurações publicadas');
      } catch (e) {
        errors.add('Erro ao publicar config: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro config (type=${e.runtimeType})');
      }

      // 2. Publicar configurações de pagamento
      try {
        debugPrint(
            '\n💳 [PUBLISH-ALL] Etapa 2/4: Publicando configurações de pagamento...');
        await publishPayments(lojaIdOverride: lojaId);
        results['payments'] = true;
        debugPrint('✅ [PUBLISH-ALL] Etapa 2/4: Pagamentos publicados');
      } catch (e) {
        errors.add('Erro ao publicar payments: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro payments (type=${e.runtimeType})');
      }

      // 3. Publicar produtos (usando método existente)
      try {
        debugPrint('\n📦 [PUBLISH-ALL] Etapa 3/4: Publicando produtos...');
        await promoteAll(lojaIdOverride: lojaId);

        // Contar quantos foram publicados
        final liveSnap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('produtos')
            .get();
        results['products'] = liveSnap.docs.length;
        debugPrint(
            '✅ [PUBLISH-ALL] Etapa 3/4: ${results['products']} produtos publicados');
      } catch (e) {
        errors.add('Erro ao publicar produtos: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro produtos (type=${e.runtimeType})');
      }

      // 4. Verificar campanhas ativas (já estão na mesma collection)
      try {
        debugPrint(
            '\n🎯 [PUBLISH-ALL] Etapa 4/4: Verificando campanhas ativas...');
        final campaignsSnap = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection('campanhas_sorteio')
            .where('ativa', isEqualTo: true)
            .get();

        results['campaigns'] = campaignsSnap.docs.length;
        debugPrint(
            '✅ [PUBLISH-ALL] Etapa 4/4: ${results['campaigns']} campanhas ativas encontradas');
      } catch (e) {
        errors.add('Erro ao verificar campanhas: $e');
        debugPrint('❌ [PUBLISH-ALL] Erro campanhas (type=${e.runtimeType})');
      }

      if (errors.isNotEmpty) {
        results['success'] = false;
      }

      debugPrint(
          '\n═══════════════════════════════════════════════════════════');
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
      debugPrint(
          '═══════════════════════════════════════════════════════════\n');

      return results;
    } catch (e) {
      debugPrint('❌ [PUBLISH-ALL] Erro geral (type=${e.runtimeType})');
      results['success'] = false;
      errors.add('Erro geral: $e');
      return results;
    }
  }
}
