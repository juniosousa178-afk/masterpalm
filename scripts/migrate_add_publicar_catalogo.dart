// Script para adicionar campo publicadoNoCatalogo em produtos existentes
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  print('🔧 Iniciando migração: adicionar publicadoNoCatalogo');

  // Inicializar Firebase
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;

  try {
    // Buscar todas as lojas
    print('📦 Buscando lojas...');
    final lojasSnap = await firestore.collection('lojas').get();
    print('✅ Encontradas ${lojasSnap.docs.length} lojas');

    int totalProdutos = 0;
    int produtosAtualizados = 0;

    for (final lojaDoc in lojasSnap.docs) {
      final lojaId = lojaDoc.id;
      print('\n🏪 Processando loja: $lojaId');

      // Processar produtos
      final produtosSnap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .get();

      print('  📦 Produtos encontrados: ${produtosSnap.docs.length}');
      totalProdutos += produtosSnap.docs.length;

      for (final prodDoc in produtosSnap.docs) {
        final data = prodDoc.data();

        // Se já tem o campo, pular
        if (data.containsKey('publicadoNoCatalogo')) {
          continue;
        }

        // Adicionar campo publicadoNoCatalogo = true
        await prodDoc.reference.update({
          'publicadoNoCatalogo': true,
        });

        produtosAtualizados++;

        if (produtosAtualizados % 10 == 0) {
          print('  ✅ Atualizados: $produtosAtualizados');
        }
      }

      print('  ✅ Loja $lojaId concluída');
    }

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!');
    print('   Total de lojas: ${lojasSnap.docs.length}');
    print('   Total de produtos: $totalProdutos');
    print('   Produtos atualizados: $produtosAtualizados');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  } catch (e, stack) {
    print('❌ Erro durante migração (type=${e.runtimeType})');
    print('Stack trace: $stack');
    exit(1);
  }

  exit(0);
}
