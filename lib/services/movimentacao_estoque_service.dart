// lib/services/movimentacao_estoque_service.dart
// Registra histórico de entradas e saídas de estoque (vendas, ajustes, importação).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class MovimentacaoEstoqueService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Registra uma movimentação de estoque (entrada ou saída).
  /// Chamado de forma não bloqueante – falhas não interrompem o fluxo principal.
  static Future<void> registrar({
    required String lojaId,
    required String produtoId,
    required String produtoNome,
    required String tipo, // 'entrada' | 'saida' | 'correcao_fisica'
    required int quantidade,
    String motivo = '',
    String usuario = 'App',
    String? vendaId,
    int? beforeQty,
    int? afterQty,
    int? delta,
    List<Map<String, dynamic>>? cellsChanged,
    String? stockOperationId,
  }) async {
    try {
      await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('movimentacoes_estoque')
          .add({
        'produtoId': produtoId,
        'produtoNome': produtoNome,
        'tipo': tipo,
        'quantidade': quantidade,
        'data': FieldValue.serverTimestamp(),
        'motivo': motivo,
        'usuario': usuario,
        if (vendaId != null) 'vendaId': vendaId,
        if (beforeQty != null) 'beforeQty': beforeQty,
        if (afterQty != null) 'afterQty': afterQty,
        if (delta != null) 'delta': delta,
        if (cellsChanged != null) 'cellsChanged': cellsChanged,
        if (stockOperationId != null) 'stockOperationId': stockOperationId,
      });
      debugPrint('✅ Movimentação registrada: $tipo $quantidade x $produtoNome');
    } catch (e) {
      debugPrint('⚠️ Erro ao registrar movimentação (não bloqueia): $e');
    }
  }

  /// Stream de movimentações para uma loja (ordenado por data decrescente).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMovimentacoes({
    required String lojaId,
    int limit = 200,
  }) {
    return _db
        .collection('lojas')
        .doc(lojaId)
        .collection('movimentacoes_estoque')
        .orderBy('data', descending: true)
        .limit(limit)
        .snapshots();
  }
}
