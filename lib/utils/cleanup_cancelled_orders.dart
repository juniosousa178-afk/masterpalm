// lib/utils/cleanup_cancelled_orders.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Utilit ário para limpar pedidos cancelados antigos do Firestore
/// Execute esta função uma vez para remover todos os pedidos com status 'cancelado'
Future<void> cleanupCancelledOrders(String lojaId) async {
  try {
    debugPrint('🧹 Iniciando limpeza de pedidos cancelados para loja: $lojaId');

    final snapshot = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(lojaId)
        .collection('pre_pedidos')
        .where('status', isEqualTo: 'cancelado')
        .get();

    debugPrint('📦 Encontrados ${snapshot.docs.length} pedidos cancelados');

    int deletados = 0;
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
      deletados++;
      debugPrint('🗑️ Pedido cancelado deletado: ${doc.id}');
    }

    debugPrint('✅ Limpeza concluída! $deletados pedidos cancelados foram removidos');
  } catch (e) {
    debugPrint('❌ Erro ao limpar pedidos cancelados (type=${e.runtimeType})');
    rethrow;
  }
}

/// Limpa todos os pedidos antigos (cancelados, confirmados) mantendo apenas pendentes
Future<void> cleanupOldOrders(String lojaId, {int daysToKeep = 30}) async {
  try {
    debugPrint('🧹 Iniciando limpeza de pedidos antigos para loja: $lojaId');

    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

    // Buscar pedidos antigos que não são pendentes
    final snapshot = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(lojaId)
        .collection('pre_pedidos')
        .where('dataCriacao', isLessThan: Timestamp.fromDate(cutoffDate))
        .get();

    debugPrint('📦 Encontrados ${snapshot.docs.length} pedidos antigos');

    int deletados = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'] ?? '';

      // Não deletar pedidos pendentes
      if (status != 'pendente') {
        await doc.reference.delete();
        deletados++;
        debugPrint('🗑️ Pedido antigo ($status) deletado: ${doc.id}');
      }
    }

    debugPrint('✅ Limpeza concluída! $deletados pedidos antigos foram removidos');
  } catch (e) {
    debugPrint('❌ Erro ao limpar pedidos antigos (type=${e.runtimeType})');
    rethrow;
  }
}
