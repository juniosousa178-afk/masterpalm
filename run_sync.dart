// run_sync.dart - Script para executar sincronização automática

import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'lib/models/produto.dart';
import 'lib/models/cliente.dart';
import 'lib/models/venda.dart';
import 'lib/models/categoria.dart';
import 'lib/models/fornecedor.dart';
import 'lib/models/venda_item.dart';
import 'lib/services/sync_firestore_script.dart';

void main() async {
  print('🚀 Iniciando sincronização automática do Firestore...\n');

  try {
    // 1. Inicializar Firebase
    print('📡 Inicializando Firebase...');
    await Firebase.initializeApp();
    print('✅ Firebase inicializado\n');

    // 2. Inicializar Hive
    print('💾 Inicializando Hive...');
    final appDir = await getApplicationDocumentsDirectory();
    Hive.init(appDir.path);

    // Registrar adaptadores
    Hive.registerAdapter(ProdutoAdapter());
    Hive.registerAdapter(ClienteAdapter());
    Hive.registerAdapter(VendaAdapter());
    Hive.registerAdapter(VendaItemAdapter());
    Hive.registerAdapter(CategoriaAdapter());
    Hive.registerAdapter(FornecedorAdapter());
    print('✅ Hive inicializado\n');

    // 3. Executar sincronização completa
    print('🔄 Executando sincronização COMPLETA...\n');
    print('=' * 60);

    final results = await SyncFirestoreScript.syncTudo();

    print('=' * 60);
    print('\n📊 RESULTADOS DA SINCRONIZAÇÃO');
    print('=' * 60);

    if (results['success'] == true) {
      print('✅ Status: SUCESSO\n');
      print('🏪 Loja: ${results['lojaId']}\n');

      final produtos = results['produtos'] as Map<String, int>;
      final clientes = results['clientes'] as Map<String, int>;
      final vendas = results['vendas'] as Map<String, int>;
      final categorias = results['categorias'] as Map<String, int>;
      final fornecedores = results['fornecedores'] as Map<String, int>;

      print('📦 PRODUTOS:');
      print('   ✅ Sincronizados: ${produtos['synced']}');
      print('   ❌ Erros: ${produtos['errors']}\n');

      print('👥 CLIENTES:');
      print('   ✅ Sincronizados: ${clientes['synced']}');
      print('   ❌ Erros: ${clientes['errors']}\n');

      print('💰 VENDAS:');
      print('   ✅ Sincronizadas: ${vendas['synced']}');
      print('   ❌ Erros: ${vendas['errors']}\n');

      print('🏷️ CATEGORIAS:');
      print('   ✅ Sincronizadas: ${categorias['synced']}');
      print('   ❌ Erros: ${categorias['errors']}\n');

      print('🏭 FORNECEDORES:');
      print('   ✅ Sincronizados: ${fornecedores['synced']}');
      print('   ❌ Erros: ${fornecedores['errors']}\n');

      print('=' * 60);
      print('✅ SINCRONIZAÇÃO COMPLETA COM SUCESSO!');
      print('=' * 60);

    } else {
      print('❌ Status: FALHA\n');

      final errors = results['errors'] as List<String>;
      if (errors.isNotEmpty) {
        print('Erros encontrados:');
        for (final error in errors) {
          print('  • $error');
        }
      }
      print('');
    }

  } catch (e, stack) {
    print('\n❌ ERRO AO EXECUTAR SINCRONIZAÇÃO (type=${e.runtimeType})');
    print('\nStack trace:');
    print(stack);
  }
}
