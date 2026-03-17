// lib/services/comissao_config_service.dart
// Serviço para gerenciar configurações de comissões

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/comissao_config.dart';

/// Serviço para gerenciar configurações de comissões da loja
class ComissaoConfigService {
  ComissaoConfigService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ============================================================
  // CONFIGURAÇÃO GLOBAL
  // ============================================================

  /// Busca a configuração de comissão da loja
  static Future<ComissaoConfig?> getConfig(String lojaId) async {
    try {
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('configuracoes')
          .doc('comissao')
          .get();

      if (doc.exists) {
        return ComissaoConfig.fromMap(doc.data()!, docId: doc.id);
      }

      // Retorna configuração padrão se não existir
      return ComissaoConfig(lojaId: lojaId);
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao buscar config (type=${e.runtimeType})');
      return null;
    }
  }

  /// Salva a configuração de comissão da loja
  static Future<bool> salvarConfig(ComissaoConfig config) async {
    try {
      await _db
          .collection('lojas')
          .doc(config.lojaId)
          .collection('configuracoes')
          .doc('comissao')
          .set(config.toMap(), SetOptions(merge: true));

      debugPrint('✅ [COMISSAO-CONFIG] Configuração salva para loja ${config.lojaId}');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao salvar config (type=${e.runtimeType})');
      return false;
    }
  }

  /// Atualiza campos específicos da configuração
  static Future<bool> atualizarConfig({
    required String lojaId,
    double? comissaoGlobalPercent,
    bool? apenasAposPagamentoConfirmado,
    bool? excluirFreteDaBase,
    bool? descontoReduzBase,
    int? trackingExpiracaoDias,
    String? regraAtribuicao,
    double? bonusMetaBatida100,
    double? bonusMetaBatida150,
    double? comissaoMinimaValor,
    double? comissaoMaximaValor,
    bool? estornoAutomaticoEmCancelamento,
  }) async {
    try {
      final updates = <String, dynamic>{
        'atualizadoEm': DateTime.now().toIso8601String(),
      };

      if (comissaoGlobalPercent != null) {
        updates['comissaoGlobalPercent'] = comissaoGlobalPercent;
      }
      if (apenasAposPagamentoConfirmado != null) {
        updates['apenasAposPagamentoConfirmado'] = apenasAposPagamentoConfirmado;
      }
      if (excluirFreteDaBase != null) {
        updates['excluirFreteDaBase'] = excluirFreteDaBase;
      }
      if (descontoReduzBase != null) {
        updates['descontoReduzBase'] = descontoReduzBase;
      }
      if (trackingExpiracaoDias != null) {
        updates['trackingExpiracaoDias'] = trackingExpiracaoDias;
      }
      if (regraAtribuicao != null) {
        updates['regraAtribuicao'] = regraAtribuicao;
      }
      if (bonusMetaBatida100 != null) {
        updates['bonusMetaBatida100'] = bonusMetaBatida100;
      }
      if (bonusMetaBatida150 != null) {
        updates['bonusMetaBatida150'] = bonusMetaBatida150;
      }
      if (comissaoMinimaValor != null) {
        updates['comissaoMinimaValor'] = comissaoMinimaValor;
      }
      if (comissaoMaximaValor != null) {
        updates['comissaoMaximaValor'] = comissaoMaximaValor;
      }
      if (estornoAutomaticoEmCancelamento != null) {
        updates['estornoAutomaticoEmCancelamento'] = estornoAutomaticoEmCancelamento;
      }

      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('configuracoes')
          .doc('comissao')
          .set(updates, SetOptions(merge: true));

      debugPrint('✅ [COMISSAO-CONFIG] Configuração atualizada');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao atualizar config (type=${e.runtimeType})');
      return false;
    }
  }

  // ============================================================
  // COMISSÃO POR VENDEDOR
  // ============================================================

  /// Lista todos os vendedores com suas configurações de comissão
  static Future<List<ComissaoVendedor>> listarVendedoresComissao(String lojaId) async {
    try {
      final snapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes_vendedores')
          .orderBy('vendedorNome')
          .get();

      return snapshot.docs
          .map((doc) => ComissaoVendedor.fromMap(doc.data(), docId: doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao listar vendedores (type=${e.runtimeType})');
      return [];
    }
  }

  /// Busca configuração de comissão de um vendedor específico
  static Future<ComissaoVendedor?> getComissaoVendedor({
    required String lojaId,
    required String vendedorUid,
  }) async {
    try {
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes_vendedores')
          .doc(vendedorUid)
          .get();

      if (doc.exists) {
        return ComissaoVendedor.fromMap(doc.data()!, docId: doc.id);
      }
      return null;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao buscar comissão vendedor (type=${e.runtimeType})');
      return null;
    }
  }

  /// Configura a comissão de um vendedor
  static Future<bool> configurarComissaoVendedor({
    required String lojaId,
    required String vendedorUid,
    required String vendedorEmail,
    required String vendedorNome,
    double? comissaoPercentual,
    bool ativo = true,
  }) async {
    try {
      final comissao = ComissaoVendedor(
        lojaId: lojaId,
        vendedorUid: vendedorUid,
        vendedorEmail: vendedorEmail,
        vendedorNome: vendedorNome,
        comissaoPercentual: comissaoPercentual,
        ativo: ativo,
      );

      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes_vendedores')
          .doc(vendedorUid)
          .set(comissao.toMap(), SetOptions(merge: true));

      debugPrint('✅ [COMISSAO-CONFIG] Comissão do vendedor $vendedorNome configurada');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao configurar comissão vendedor (type=${e.runtimeType})');
      return false;
    }
  }

  /// Atualiza apenas o percentual de comissão de um vendedor
  static Future<bool> atualizarPercentualVendedor({
    required String lojaId,
    required String vendedorUid,
    required double? comissaoPercentual,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes_vendedores')
          .doc(vendedorUid)
          .update({
        'comissaoPercentual': comissaoPercentual,
        'atualizadoEm': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ [COMISSAO-CONFIG] Percentual atualizado: $comissaoPercentual%');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao atualizar percentual (type=${e.runtimeType})');
      return false;
    }
  }

  /// Ativa ou desativa comissões para um vendedor
  static Future<bool> toggleVendedorAtivo({
    required String lojaId,
    required String vendedorUid,
    required bool ativo,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes_vendedores')
          .doc(vendedorUid)
          .update({
        'ativo': ativo,
        'atualizadoEm': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ [COMISSAO-CONFIG] Vendedor ${ativo ? "ativado" : "desativado"}');
      return true;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao toggle vendedor (type=${e.runtimeType})');
      return false;
    }
  }

  // ============================================================
  // CÁLCULO DE PERCENTUAL EFETIVO
  // ============================================================

  /// Calcula o percentual de comissão efetivo para um vendedor
  /// Considera: percentual específico, global, e bônus por meta
  static Future<double> calcularPercentualEfetivo({
    required String lojaId,
    required String vendedorUid,
    double? percentualMetaAtingida,
  }) async {
    try {
      // Buscar configuração global
      final config = await getConfig(lojaId);
      if (config == null) {
        return 5.0; // Padrão se não houver configuração
      }

      // Buscar configuração específica do vendedor
      final vendedorConfig = await getComissaoVendedor(
        lojaId: lojaId,
        vendedorUid: vendedorUid,
      );

      // Usar percentual específico ou global
      double percentual = vendedorConfig?.comissaoPercentual ?? config.comissaoGlobalPercent;

      // Aplicar bônus por meta batida
      if (percentualMetaAtingida != null) {
        if (percentualMetaAtingida >= 150) {
          percentual += config.bonusMetaBatida150;
          debugPrint('🎯 [COMISSAO] Bônus 150%: +${config.bonusMetaBatida150}%');
        } else if (percentualMetaAtingida >= 100) {
          percentual += config.bonusMetaBatida100;
          debugPrint('🎯 [COMISSAO] Bônus 100%: +${config.bonusMetaBatida100}%');
        }
      }

      return percentual;
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao calcular percentual (type=${e.runtimeType})');
      return 5.0; // Padrão em caso de erro
    }
  }

  // ============================================================
  // SINCRONIZAÇÃO COM MEMBROS DA LOJA
  // ============================================================

  /// Sincroniza vendedores da loja com as configurações de comissão
  /// Cria entradas para novos vendedores sem configuração
  static Future<void> sincronizarVendedores(String lojaId) async {
    try {
      debugPrint('🔄 [COMISSAO-CONFIG] Sincronizando vendedores da loja $lojaId');

      // Buscar membros da loja que são vendedores
      final membrosSnapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('members')
          .where('tipo', isEqualTo: 'vendedor')
          .get();

      // Buscar configurações existentes
      final configsSnapshot = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('comissoes_vendedores')
          .get();

      final configsExistentes = {
        for (var doc in configsSnapshot.docs) doc.id: true
      };

      // Criar configuração para vendedores sem config
      final batch = _db.batch();
      int novosConfigurados = 0;

      for (final doc in membrosSnapshot.docs) {
        final uid = doc.id;
        if (!configsExistentes.containsKey(uid)) {
          final data = doc.data();
          final comissao = ComissaoVendedor(
            lojaId: lojaId,
            vendedorUid: uid,
            vendedorEmail: data['email'] ?? '',
            vendedorNome: data['nome'] ?? '',
          );

          final ref = _db
              .collection('lojas')
              .doc(lojaId)
              .collection('comissoes_vendedores')
              .doc(uid);

          batch.set(ref, comissao.toMap());
          novosConfigurados++;
        }
      }

      if (novosConfigurados > 0) {
        await batch.commit();
        debugPrint('✅ [COMISSAO-CONFIG] $novosConfigurados novos vendedores configurados');
      } else {
        debugPrint('ℹ️ [COMISSAO-CONFIG] Nenhum novo vendedor para configurar');
      }
    } catch (e) {
      debugPrint('❌ [COMISSAO-CONFIG] Erro ao sincronizar vendedores (type=${e.runtimeType})');
    }
  }
}
