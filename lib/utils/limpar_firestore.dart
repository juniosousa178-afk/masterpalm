// lib/utils/limpar_firestore.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Limpa TODOS os dados da loja no Firestore (CUIDADO: IRREVERSÍVEL!)
Future<void> limparLojaCompleta(String lojaId) async {
  try {
    debugPrint('🧹 ========================================');
    debugPrint('🧹 LIMPANDO LOJA: $lojaId');
    debugPrint('🧹 ========================================');

    final firestore = FirebaseFirestore.instance;

    // 1. Limpar PRÉ-PEDIDOS
    debugPrint('🗑️  Limpando pré-pedidos...');
    final prePedidos = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('pre_pedidos')
        .get();

    int deletedPrePedidos = 0;
    for (final doc in prePedidos.docs) {
      await doc.reference.delete();
      deletedPrePedidos++;
    }
    debugPrint('✅ $deletedPrePedidos pré-pedidos deletados');

    // 2. Limpar VENDAS (estoque_vendas)
    debugPrint('🗑️  Limpando vendas (estoque_vendas)...');
    final vendasEstoque = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('estoque_vendas')
        .get();

    int deletedVendasEstoque = 0;
    for (final doc in vendasEstoque.docs) {
      await doc.reference.delete();
      deletedVendasEstoque++;
    }
    debugPrint('✅ $deletedVendasEstoque vendas (estoque_vendas) deletadas');

    // 2.1. Limpar VENDAS (legado)
    debugPrint('🗑️  Limpando vendas (legado)...');
    final vendasLegado = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('vendas')
        .get();

    int deletedVendasLegado = 0;
    for (final doc in vendasLegado.docs) {
      await doc.reference.delete();
      deletedVendasLegado++;
    }
    debugPrint('✅ $deletedVendasLegado vendas (legado) deletadas');

    // 3. Limpar PEDIDOS DO CATÁLOGO
    debugPrint('🗑️  Limpando pedidos do catálogo...');
    final pedidosCatalogo = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('pedidos_catalogo')
        .get();

    int deletedPedidosCatalogo = 0;
    for (final doc in pedidosCatalogo.docs) {
      await doc.reference.delete();
      deletedPedidosCatalogo++;
    }
    debugPrint('✅ $deletedPedidosCatalogo pedidos do catálogo deletados');

    debugPrint('');
    debugPrint('✅ ========================================');
    debugPrint('✅ LIMPEZA CONCLUÍDA!');
    debugPrint('✅ Total removido: ${deletedPrePedidos + deletedVendasEstoque + deletedVendasLegado + deletedPedidosCatalogo} documentos');
    debugPrint('✅ ========================================');
  } catch (e) {
    debugPrint('❌ Erro ao limpar Firestore (type=${e.runtimeType})');
    rethrow;
  }
}

/// Limpa apenas pedidos antigos (mantém produtos e clientes)
Future<void> limparApenasVendas(String lojaId) async {
  try {
    debugPrint('🧹 Limpando apenas vendas e pedidos da loja: $lojaId');

    final firestore = FirebaseFirestore.instance;

    // Limpar pré-pedidos
    final prePedidos = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('pre_pedidos')
        .get();

    for (final doc in prePedidos.docs) {
      await doc.reference.delete();
    }
    debugPrint('✅ ${prePedidos.docs.length} pré-pedidos deletados');

    // Limpar vendas (estoque_vendas - principal)
    final vendasEstoque = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('estoque_vendas')
        .get();

    for (final doc in vendasEstoque.docs) {
      await doc.reference.delete();
    }
    debugPrint('✅ ${vendasEstoque.docs.length} vendas (estoque_vendas) deletadas');

    // Limpar vendas (legado)
    final vendasLegado = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('vendas')
        .get();

    for (final doc in vendasLegado.docs) {
      await doc.reference.delete();
    }
    debugPrint('✅ ${vendasLegado.docs.length} vendas (legado) deletadas');

    // Limpar pedidos do catálogo
    final pedidosCatalogo = await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection('pedidos_catalogo')
        .get();

    for (final doc in pedidosCatalogo.docs) {
      await doc.reference.delete();
    }
    debugPrint('✅ ${pedidosCatalogo.docs.length} pedidos do catálogo deletados');

    debugPrint('✅ Limpeza de vendas concluída!');
  } catch (e) {
    debugPrint('❌ Erro ao limpar vendas (type=${e.runtimeType})');
    rethrow;
  }
}
