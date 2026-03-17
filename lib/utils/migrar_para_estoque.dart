// lib/utils/migrar_para_estoque.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Migra dados existentes das coleções antigas para as novas coleções estoque_*
/// Execute isso UMA VEZ para migrar dados existentes
Future<void> migrarParaEstoque(String lojaId) async {
  final db = FirebaseFirestore.instance;

  debugPrint('\n${"=" * 80}');
  debugPrint('🔄 MIGRAÇÃO DE DADOS PARA COLEÇÕES ESTOQUE');
  debugPrint("=" * 80);
  debugPrint('Loja: $lojaId');
  debugPrint('${"=" * 80}\n');

  try {
    // 1. Migrar PRODUTOS: produtos → estoque_produtos
    debugPrint('📦 Migrando produtos...');
    final produtosSnapshot = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('produtos')
        .get();

    int produtosMigrados = 0;
    for (final doc in produtosSnapshot.docs) {
      final data = doc.data();
      await db
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_produtos')
          .doc(doc.id)
          .set(data, SetOptions(merge: true));
      produtosMigrados++;
      debugPrint('  ✅ Produto migrado: ${doc.id}');
    }
    debugPrint('✅ $produtosMigrados produtos migrados\n');

    // 2. Migrar CLIENTES: clientes → estoque_clientes
    debugPrint('👥 Migrando clientes...');
    final clientesSnapshot = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('clientes')
        .get();

    int clientesMigrados = 0;
    for (final doc in clientesSnapshot.docs) {
      final data = doc.data();
      await db
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_clientes')
          .doc(doc.id)
          .set(data, SetOptions(merge: true));
      clientesMigrados++;
      debugPrint('  ✅ Cliente migrado: ${doc.id}');
    }
    debugPrint('✅ $clientesMigrados clientes migrados\n');

    // 3. Migrar FORNECEDORES: fornecedores → estoque_fornecedores
    debugPrint('🚚 Migrando fornecedores...');
    final fornecedoresSnapshot = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('fornecedores')
        .get();

    int fornecedoresMigrados = 0;
    for (final doc in fornecedoresSnapshot.docs) {
      final data = doc.data();
      await db
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_fornecedores')
          .doc(doc.id)
          .set(data, SetOptions(merge: true));
      fornecedoresMigrados++;
      debugPrint('  ✅ Fornecedor migrado: ${doc.id}');
    }
    debugPrint('✅ $fornecedoresMigrados fornecedores migrados\n');

    // 4. Migrar VENDAS: vendas → estoque_vendas
    debugPrint('💰 Migrando vendas...');
    final vendasSnapshot = await db
        .collection('lojas')
        .doc(lojaId)
        .collection('vendas')
        .get();

    int vendasMigradas = 0;
    for (final doc in vendasSnapshot.docs) {
      final data = doc.data();
      await db
          .collection('lojas')
          .doc(lojaId)
          .collection('estoque_vendas')
          .doc(doc.id)
          .set(data, SetOptions(merge: true));
      vendasMigradas++;
      debugPrint('  ✅ Venda migrada: ${doc.id}');
    }
    debugPrint('✅ $vendasMigradas vendas migradas\n');

    debugPrint("=" * 80);
    debugPrint('✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!');
    debugPrint("=" * 80);
    debugPrint('Total migrado:');
    debugPrint('  - Produtos: $produtosMigrados');
    debugPrint('  - Clientes: $clientesMigrados');
    debugPrint('  - Fornecedores: $fornecedoresMigrados');
    debugPrint('  - Vendas: $vendasMigradas');
    debugPrint('${"=" * 80}\n');
  } catch (e, st) {
    debugPrint('❌ Erro durante migração (type=${e.runtimeType})');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}
