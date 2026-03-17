import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'session_sanity.dart';

/// Script para consolidar duas lojas em uma só
///
/// Problema: Dados divididos entre:
/// - loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2 (loja técnica)
/// - nathy-pratas-e-folheados (loja slug)
///
/// Solução: Mover tudo para nathy-pratas-e-folheados
class ConsolidateStoresService {
  static const String _sourceLoja = 'loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2';
  static const String _targetLoja = 'nathy-pratas-e-folheados';

  /// Executa a consolidação completa
  static Future<Map<String, dynamic>> consolidate() async {
    final results = <String, dynamic>{};

    try {
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🔄 Iniciando consolidação de lojas');
      debugPrint('   Origem: $_sourceLoja');
      debugPrint('   Destino: $_targetLoja');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 1. Copiar produtos
      final produtosCopiados = await _copyProdutos();
      results['produtos'] = produtosCopiados;
      debugPrint('✅ Produtos copiados: $produtosCopiados');

      // 2. Copiar draft_produtos
      final draftProdutosCopiados = await _copyDraftProdutos();
      results['draft_produtos'] = draftProdutosCopiados;
      debugPrint('✅ Draft produtos copiados: $draftProdutosCopiados');

      // 3. Copiar configurações
      final configCopiada = await _copyConfig();
      results['config'] = configCopiada;
      debugPrint('✅ Config copiada: $configCopiada');

      // 4. Copiar draft_config
      final draftConfigCopiada = await _copyDraftConfig();
      results['draft_config'] = draftConfigCopiada;
      debugPrint('✅ Draft config copiada: $draftConfigCopiada');

      // 5. Remover redirectTo da loja origem
      await _removeRedirect();
      results['redirect_removed'] = true;
      debugPrint('✅ Redirect removido');

      // 6. Atualizar metadata da loja destino
      await _updateTargetMetadata();
      results['metadata_updated'] = true;
      debugPrint('✅ Metadata atualizada');

      // 7. Limpar cache local para forçar nova resolução
      await SessionSanity.clearAllStoreCache();
      results['cache_cleared'] = true;
      debugPrint('✅ Cache local limpo');

      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🎉 Consolidação concluída com sucesso!');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      results['success'] = true;
      return results;
    } catch (e, stackTrace) {
      debugPrint('❌ Erro na consolidação (type=${e.runtimeType})');
      debugPrint(stackTrace.toString());
      results['success'] = false;
      results['error'] = e.toString();
      return results;
    }
  }

  /// Copia todos os produtos da loja origem para destino
  static Future<int> _copyProdutos() async {
    final firestore = FirebaseFirestore.instance;
    final sourceRef = firestore.collection('lojas/$_sourceLoja/produtos');
    final targetRef = firestore.collection('lojas/$_targetLoja/produtos');

    final snapshot = await sourceRef.get();
    int count = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data();

      // Atualizar IDs e referências
      final newId = doc.id.replaceFirst(_sourceLoja, _targetLoja);
      data['lojaId'] = _targetLoja;
      data['id'] = newId;

      // Verificar se já existe no destino
      final targetDoc = await targetRef.doc(newId).get();
      if (!targetDoc.exists) {
        await targetRef.doc(newId).set(data);
        count++;
        debugPrint('  📦 Produto copiado: $newId');
      } else {
        debugPrint('  ⏭️  Produto já existe: $newId (pulando)');
      }
    }

    return count;
  }

  /// Copia todos os draft_produtos da loja origem para destino
  static Future<int> _copyDraftProdutos() async {
    final firestore = FirebaseFirestore.instance;
    final sourceRef = firestore.collection('lojas/$_sourceLoja/draft_produtos');
    final targetRef = firestore.collection('lojas/$_targetLoja/draft_produtos');

    final snapshot = await sourceRef.get();
    int count = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data();

      // Atualizar IDs e referências
      final newId = doc.id.replaceFirst(_sourceLoja, _targetLoja);
      data['lojaId'] = _targetLoja;
      data['id'] = newId;

      // Verificar se já existe no destino
      final targetDoc = await targetRef.doc(newId).get();
      if (!targetDoc.exists) {
        await targetRef.doc(newId).set(data);
        count++;
        debugPrint('  📝 Draft produto copiado: $newId');
      } else {
        debugPrint('  ⏭️  Draft produto já existe: $newId (pulando)');
      }
    }

    return count;
  }

  /// Copia config da loja origem para destino (merge AGRESSIVO)
  static Future<bool> _copyConfig() async {
    final firestore = FirebaseFirestore.instance;
    final sourceDoc = firestore.doc('lojas/$_sourceLoja/config/config');
    final targetDoc = firestore.doc('lojas/$_targetLoja/config/config');

    final sourceSnapshot = await sourceDoc.get();
    final targetSnapshot = await targetDoc.get();

    Map<String, dynamic> mergedData = {};

    // Se origem existe, usar dados dela como base
    if (sourceSnapshot.exists) {
      mergedData = {...sourceSnapshot.data()!};
      debugPrint('  📋 Config origem encontrada');
    }

    // Se destino existe, sobrescrever/adicionar seus dados
    if (targetSnapshot.exists) {
      final targetData = targetSnapshot.data()!;
      targetData.forEach((key, value) {
        mergedData[key] = value;
      });
      debugPrint('  📋 Config destino mesclada');
    }

    // Garantir campos essenciais
    mergedData['lojaId'] = _targetLoja;
    mergedData['slug'] = _targetLoja;
    mergedData['updatedAt'] = FieldValue.serverTimestamp();

    if (mergedData.isNotEmpty) {
      await targetDoc.set(mergedData, SetOptions(merge: true));
      debugPrint('  ✅ Config consolidada com ${mergedData.length} campos');
      return true;
    } else {
      debugPrint('  ⚠️  Nenhuma config encontrada para consolidar');
      return false;
    }
  }

  /// Copia draft_config da loja origem para destino (merge AGRESSIVO)
  static Future<bool> _copyDraftConfig() async {
    final firestore = FirebaseFirestore.instance;
    final sourceDoc = firestore.doc('lojas/$_sourceLoja/draft_config/config');
    final targetDoc = firestore.doc('lojas/$_targetLoja/draft_config/config');

    final sourceSnapshot = await sourceDoc.get();
    final targetSnapshot = await targetDoc.get();

    Map<String, dynamic> mergedData = {};

    // Se origem existe, usar dados dela como base
    if (sourceSnapshot.exists) {
      mergedData = {...sourceSnapshot.data()!};
      debugPrint('  📝 Draft config origem encontrada');
    }

    // Se destino existe, sobrescrever/adicionar seus dados
    if (targetSnapshot.exists) {
      final targetData = targetSnapshot.data()!;
      targetData.forEach((key, value) {
        mergedData[key] = value;
      });
      debugPrint('  📝 Draft config destino mesclada');
    }

    // Garantir campos essenciais
    mergedData['lojaId'] = _targetLoja;
    mergedData['slug'] = _targetLoja;
    mergedData['updatedAt'] = FieldValue.serverTimestamp();

    if (mergedData.isNotEmpty) {
      await targetDoc.set(mergedData, SetOptions(merge: true));
      debugPrint('  ✅ Draft config consolidada com ${mergedData.length} campos');
      return true;
    } else {
      debugPrint('  ⚠️  Nenhuma draft config encontrada para consolidar');
      return false;
    }
  }

  /// Remove o campo redirectTo da loja origem
  static Future<void> _removeRedirect() async {
    final firestore = FirebaseFirestore.instance;
    final lojaDoc = firestore.doc('lojas/$_sourceLoja');

    await lojaDoc.update({
      'redirectTo': FieldValue.delete(),
    });

    debugPrint('  🗑️  Campo redirectTo removido de $_sourceLoja');
  }

  /// Atualiza metadata da loja destino (COMPLETO)
  static Future<void> _updateTargetMetadata() async {
    final firestore = FirebaseFirestore.instance;
    final lojaDoc = firestore.doc('lojas/$_targetLoja');
    final sourceDoc = firestore.doc('lojas/$_sourceLoja');

    // Pegar dados da loja origem
    final sourceSnapshot = await sourceDoc.get();
    Map<String, dynamic> metadata = {};

    if (sourceSnapshot.exists) {
      metadata = {...sourceSnapshot.data()!};
      debugPrint('  📋 Metadata origem copiada');
    }

    // Pegar dados da loja destino (se existir)
    final targetSnapshot = await lojaDoc.get();
    if (targetSnapshot.exists) {
      final targetData = targetSnapshot.data()!;
      targetData.forEach((key, value) {
        metadata[key] = value;
      });
      debugPrint('  📋 Metadata destino mesclada');
    }

    // Forçar campos essenciais
    metadata['slug'] = _targetLoja;
    metadata['lojaId'] = _targetLoja;
    metadata['id'] = _targetLoja;
    metadata['consolidatedAt'] = FieldValue.serverTimestamp();
    metadata['consolidatedFrom'] = _sourceLoja;
    metadata['updatedAt'] = FieldValue.serverTimestamp();

    // Remover redirectTo se existir
    metadata.remove('redirectTo');

    await lojaDoc.set(metadata, SetOptions(merge: true));

    debugPrint('  ✍️  Metadata consolidada em $_targetLoja com ${metadata.length} campos');
  }

  /// Executa verificação pós-consolidação
  static Future<Map<String, dynamic>> verify() async {
    final firestore = FirebaseFirestore.instance;
    final results = <String, dynamic>{};

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔍 Verificando consolidação...');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Verificar produtos
    final produtosSnapshot = await firestore
        .collection('lojas/$_targetLoja/produtos')
        .get();
    results['produtos_count'] = produtosSnapshot.docs.length;
    debugPrint('📦 Produtos em $_targetLoja: ${produtosSnapshot.docs.length}');

    // Verificar draft_produtos
    final draftProdutosSnapshot = await firestore
        .collection('lojas/$_targetLoja/draft_produtos')
        .get();
    results['draft_produtos_count'] = draftProdutosSnapshot.docs.length;
    debugPrint('📝 Draft produtos em $_targetLoja: ${draftProdutosSnapshot.docs.length}');

    // Verificar config
    final configDoc = await firestore
        .doc('lojas/$_targetLoja/config/config')
        .get();
    results['has_config'] = configDoc.exists;
    debugPrint('📋 Config existe: ${configDoc.exists}');

    // Verificar draft_config
    final draftConfigDoc = await firestore
        .doc('lojas/$_targetLoja/draft_config/config')
        .get();
    results['has_draft_config'] = draftConfigDoc.exists;
    debugPrint('📝 Draft config existe: ${draftConfigDoc.exists}');

    // Verificar redirectTo removido
    final lojaOrigemDoc = await firestore.doc('lojas/$_sourceLoja').get();
    final hasRedirect = lojaOrigemDoc.data()?['redirectTo'] != null;
    results['redirect_removed'] = !hasRedirect;
    debugPrint('🔀 Redirect removido: ${!hasRedirect}');

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    return results;
  }
}
