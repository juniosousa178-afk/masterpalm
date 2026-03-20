// lib/services/firestore_cleanup_script.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Script para limpar coleções desnecessárias do Firestore
/// Mantém apenas as coleções que são realmente utilizadas pelo app
class FirestoreCleanupScript {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Coleções ESSENCIAIS que DEVEM SER MANTIDAS
  static const Set<String> _colecoesEssenciais = {
    // Nível ROOT
    'lojas',
    'users',
    'usuarios',
    'pedidos_temp',
    'pedidos',

    // Sub-coleções por loja (dentro de lojas/{lojaId}/)
    'produtos',
    'clientes',
    'vendas',
    'categorias',
    'fornecedores',
    'config',
    'draft_config',
    'settings',
    'members',
    'campanhas_sorteio',
    'campanhas_sorteio_config',
    'cupons_premio',

    // Sub-coleções de campanhas (dentro de campanhas_sorteio/{campanhaId}/)
    'participantes',
  };

  /// Coleções OBSOLETAS que PODEM SER REMOVIDAS
  /// (Coleções antigas que não são mais usadas)
  static const Set<String> _colecoesObsoletas = {
    'temp_orders',     // Obsoleto - agora usa 'pedidos_temp'
    'old_vendas',      // Backup antigo
    'cache',           // Cache temporário
    'logs',            // Logs antigos
    'sessions',        // Sessões antigas
    'temp',            // Temporários
  };

  /// Executa limpeza completa
  static Future<Map<String, dynamic>> executarLimpeza({
    required String lojaId,
    bool dryRun = true,  // Se true, apenas mostra o que seria removido
  }) async {
    debugPrint('🧹 [CLEANUP] Iniciando limpeza do Firestore...');
    debugPrint('🏪 [CLEANUP] Loja: $lojaId');
    debugPrint('🔍 [CLEANUP] Modo: ${dryRun ? "DRY RUN (simulação)" : "EXECUÇÃO REAL"}');

    final results = <String, dynamic>{
      'success': true,
      'lojaId': lojaId,
      'dryRun': dryRun,
      'colecoesAnalisadas': <String>[],
      'colecoesObsoletas': <String>[],
      'colecoesRemovidas': <String>[],
      'documentosRemovidos': 0,
      'errors': <String>[],
    };

    try {
      // 1. Analisar coleções na raiz da loja
      debugPrint('📊 [CLEANUP] Analisando coleções em /lojas/$lojaId/...');
      final lojaRef = _db.collection('lojas').doc(lojaId);

      // Infelizmente, Firestore não tem método para listar coleções
      // Vamos verificar as coleções conhecidas obsoletas

      for (final colecao in _colecoesObsoletas) {
        try {
          final snapshot = await lojaRef.collection(colecao).get();

          if (snapshot.docs.isNotEmpty) {
            debugPrint('🗑️ [CLEANUP] Encontrada coleção obsoleta: $colecao (${snapshot.docs.length} docs)');
            (results['colecoesObsoletas'] as List<String>).add(colecao);

            if (!dryRun) {
              // REMOÇÃO REAL
              final batch = _db.batch();
              int count = 0;

              for (final doc in snapshot.docs) {
                batch.delete(doc.reference);
                count++;

                // Commit a cada 450 documentos (limite do Firestore)
                if (count % 450 == 0) {
                  await batch.commit();
                  debugPrint('✅ [CLEANUP] Batch commit: $count docs removidos de $colecao');
                }
              }

              // Commit final
              if (count % 450 != 0) {
                await batch.commit();
              }

              (results['colecoesRemovidas'] as List<String>).add(colecao);
              results['documentosRemovidos'] =
                  (results['documentosRemovidos'] as int) + snapshot.docs.length;

              debugPrint('✅ [CLEANUP] Removida: $colecao (${snapshot.docs.length} docs)');

            } else {
              debugPrint('🔍 [CLEANUP] [DRY RUN] Seria removida: $colecao (${snapshot.docs.length} docs)');
            }
          }

        } catch (e) {
          debugPrint('⚠️ [CLEANUP] Erro ao verificar $colecao (type=${e.runtimeType})');
          (results['errors'] as List<String>).add('$colecao: $e');
        }
      }

      // 2. Limpar documentos órfãos (sem lojaId ou com lojaId errado)
      debugPrint('🔍 [CLEANUP] Verificando documentos órfãos...');
      await _limparDocumentosOrfaos(lojaId, dryRun, results);

      // 3. Limpar coleções temporárias antigas
      debugPrint('🔍 [CLEANUP] Verificando coleções temporárias...');
      await _limparColecoesTemporarias(dryRun, results);

      debugPrint('✅ [CLEANUP] Limpeza concluída!');

    } catch (e, stack) {
      debugPrint('❌ [CLEANUP] Erro geral (type=${e.runtimeType})');
      debugPrint('Stack: $stack');
      results['success'] = false;
      (results['errors'] as List<String>).add('Erro geral: $e');
    }

    return results;
  }

  /// Limpa documentos órfãos (sem lojaId correto)
  static Future<void> _limparDocumentosOrfaos(
    String lojaId,
    bool dryRun,
    Map<String, dynamic> results,
  ) async {
    // Verificar produtos
    await _limparOrfaosDeColecao(
      lojaId: lojaId,
      colecao: 'produtos',
      dryRun: dryRun,
      results: results,
    );

    // Verificar clientes
    await _limparOrfaosDeColecao(
      lojaId: lojaId,
      colecao: 'clientes',
      dryRun: dryRun,
      results: results,
    );

    // Verificar vendas
    await _limparOrfaosDeColecao(
      lojaId: lojaId,
      colecao: 'vendas',
      dryRun: dryRun,
      results: results,
    );
  }

  /// Limpa órfãos de uma coleção específica
  static Future<void> _limparOrfaosDeColecao({
    required String lojaId,
    required String colecao,
    required bool dryRun,
    required Map<String, dynamic> results,
  }) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection(colecao)
          .get();

      int orfaos = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final docLojaId = data['lojaId'] as String?;

        // Documento órfão: sem lojaId ou lojaId diferente
        if (docLojaId == null || docLojaId != lojaId) {
          orfaos++;

          if (!dryRun) {
            await doc.reference.delete();
          } else {
            debugPrint('🔍 [CLEANUP] [DRY RUN] Órfão encontrado em $colecao');
          }
        }
      }

      if (orfaos > 0) {
        if (dryRun) {
          debugPrint('🔍 [CLEANUP] [DRY RUN] Encontrados $orfaos órfãos em $colecao');
        } else {
          debugPrint('✅ [CLEANUP] Removidos $orfaos órfãos de $colecao');
          results['documentosRemovidos'] =
              (results['documentosRemovidos'] as int) + orfaos;
        }
      }

    } catch (e) {
      debugPrint('⚠️ [CLEANUP] Erro ao verificar órfãos em $colecao (type=${e.runtimeType})');
      (results['errors'] as List<String>).add('Órfãos $colecao: $e');
    }
  }

  /// Limpa coleções temporárias antigas (pedidos_temp com mais de 30 dias)
  static Future<void> _limparColecoesTemporarias(
    bool dryRun,
    Map<String, dynamic> results,
  ) async {
    try {
      final limite = DateTime.now().subtract(const Duration(days: 30));
      final snapshot = await _db
          .collection('pedidos_temp')
          .where('createdAt', isLessThan: Timestamp.fromDate(limite))
          .get();

      if (snapshot.docs.isNotEmpty) {
        debugPrint('🗑️ [CLEANUP] Encontrados ${snapshot.docs.length} pedidos_temp antigos');

        if (!dryRun) {
          final batch = _db.batch();
          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();

          debugPrint('✅ [CLEANUP] Removidos ${snapshot.docs.length} pedidos_temp antigos');
          results['documentosRemovidos'] =
              (results['documentosRemovidos'] as int) + snapshot.docs.length;

        } else {
          debugPrint('🔍 [CLEANUP] [DRY RUN] Seriam removidos ${snapshot.docs.length} pedidos_temp antigos');
        }
      }

    } catch (e) {
      debugPrint('⚠️ [CLEANUP] Erro ao limpar temporários (type=${e.runtimeType})');
      (results['errors'] as List<String>).add('Temporários: $e');
    }
  }

  /// Lista todas as coleções da loja para análise manual
  static Future<List<String>> listarColecoes(String lojaId) async {
    // Firestore não tem método oficial para listar coleções
    // Essa é uma lista das coleções conhecidas
    debugPrint('📋 [CLEANUP] Coleções conhecidas em /lojas/$lojaId/:');

    for (final colecao in _colecoesEssenciais) {
      // Pular coleções de nível ROOT
      if (['lojas', 'users', 'usuarios', 'pedidos_temp', 'pedidos'].contains(colecao)) {
        continue;
      }

      try {
        final snapshot = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(colecao)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          debugPrint('  ✅ $colecao (tem dados)');
        } else {
          debugPrint('  ⚪ $colecao (vazia)');
        }

      } catch (e) {
        debugPrint('  ❌ $colecao (erro: type=${e.runtimeType})');
      }
    }

    return _colecoesEssenciais.toList();
  }

  /// Verifica integridade das coleções
  static Future<Map<String, dynamic>> verificarIntegridade(String lojaId) async {
    debugPrint('🔍 [CLEANUP] Verificando integridade para loja: $lojaId');

    final stats = <String, dynamic>{
      'lojaId': lojaId,
      'colecoes': <String, Map<String, dynamic>>{},
    };

    for (final colecao in ['produtos', 'clientes', 'vendas', 'categorias']) {
      try {
        final snapshot = await _db
            .collection('lojas')
            .doc(lojaId)
            .collection(colecao)
            .get();

        int total = snapshot.docs.length;
        int comLojaId = 0;
        int semLojaId = 0;
        int lojaIdErrado = 0;

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final docLojaId = data['lojaId'] as String?;

          if (docLojaId == null) {
            semLojaId++;
          } else if (docLojaId != lojaId) {
            lojaIdErrado++;
          } else {
            comLojaId++;
          }
        }

        stats['colecoes'][colecao] = {
          'total': total,
          'comLojaIdCorreto': comLojaId,
          'semLojaId': semLojaId,
          'lojaIdErrado': lojaIdErrado,
          'integridade': total > 0 ? '${(comLojaId / total * 100).toStringAsFixed(1)}%' : '100%',
        };

        debugPrint('📊 [CLEANUP] $colecao: $total docs | ✅ $comLojaId | ⚠️ $semLojaId sem lojaId | ❌ $lojaIdErrado errados');

      } catch (e) {
        debugPrint('❌ [CLEANUP] Erro ao verificar $colecao (type=${e.runtimeType})');
      }
    }

    return stats;
  }
}
