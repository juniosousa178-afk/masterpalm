// lib/services/fechamento_firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/fechamento_mensal.dart';

/// Serviço para sincronizar fechamentos mensais com Firestore
class FechamentoFirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Sincroniza um fechamento mensal para o Firestore
  static Future<void> syncFechamento(
    FechamentoMensal fechamento, {
    required String lojaId,
  }) async {
    try {
      // ID único baseado em ano-mes-lojaId
      final fechamentoId =
          '${fechamento.ano}-${fechamento.mes.toString().padLeft(2, '0')}-$lojaId';

      final fechamentoData = {
        'id': fechamentoId,
        'lojaId': lojaId,
        'ano': fechamento.ano,
        'mes': fechamento.mes,
        'totalDinheiro': fechamento.totalDinheiro,
        'totalPix': fechamento.totalPix,
        'totalCartao': fechamento.totalCartao,
        'vendaTotal': fechamento.vendaTotal,
        'custoTotal': fechamento.custoTotal,
        'taxasTotal': fechamento.taxasTotal,
        'lucroTotal': fechamento.lucroTotal,
        'dataFechamento': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('fechamentos_mensais')
          .doc(fechamentoId)
          .set(fechamentoData, SetOptions(merge: true));

      debugPrint('✅ [FECHAMENTO-SYNC] Fechamento $fechamentoId sincronizado');
    } catch (e) {
      debugPrint('❌ [FECHAMENTO-SYNC] Erro ao sincronizar fechamento (type=${e.runtimeType})');
      // Não faz rethrow para não bloquear o fechamento local
    }
  }

  /// Busca um fechamento específico do Firestore
  static Future<Map<String, dynamic>?> getFechamento({
    required String lojaId,
    required int ano,
    required int mes,
  }) async {
    try {
      final fechamentoId = '$ano-${mes.toString().padLeft(2, '0')}-$lojaId';

      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('fechamentos_mensais')
          .doc(fechamentoId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('❌ [FECHAMENTO-SYNC] Erro ao buscar fechamento (type=${e.runtimeType})');
      return null;
    }
  }

  /// Stream de todos os fechamentos da loja
  static Stream<List<Map<String, dynamic>>> streamFechamentos({
    required String lojaId,
  }) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('fechamentos_mensais')
        .orderBy('ano', descending: true)
        .orderBy('mes', descending: true)
        .limit(24)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Deleta um fechamento do Firestore
  static Future<void> deleteFechamento({
    required String lojaId,
    required int ano,
    required int mes,
  }) async {
    try {
      final fechamentoId = '$ano-${mes.toString().padLeft(2, '0')}-$lojaId';

      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('fechamentos_mensais')
          .doc(fechamentoId)
          .delete();

      debugPrint('🗑️ [FECHAMENTO-SYNC] Fechamento $fechamentoId deletado do Firestore');
    } catch (e) {
      debugPrint('❌ [FECHAMENTO-SYNC] Erro ao deletar fechamento (type=${e.runtimeType})');
    }
  }

  /// Sincroniza todos os fechamentos locais para o Firestore
  static Future<void> syncTodosFechamentos({
    required List<FechamentoMensal> fechamentos,
    required String lojaId,
  }) async {
    try {
      debugPrint('🔄 [FECHAMENTO-SYNC] Iniciando sync de ${fechamentos.length} fechamentos...');

      int synced = 0;
      int errors = 0;

      for (final fechamento in fechamentos) {
        if (fechamento.lojaId == lojaId) {
          try {
            await syncFechamento(fechamento, lojaId: lojaId);
            synced++;
          } catch (e) {
            errors++;
            debugPrint('❌ [FECHAMENTO-SYNC] Erro no fechamento ${fechamento.ano}-${fechamento.mes} (type=${e.runtimeType})');
          }
        }
      }

      debugPrint('✅ [FECHAMENTO-SYNC] Sync completo: $synced fechamentos sincronizados, $errors erros');
    } catch (e) {
      debugPrint('❌ [FECHAMENTO-SYNC] Erro geral (type=${e.runtimeType})');
    }
  }
}
