// scripts/sync_firestore.dart - Script CLI para sincronização Firestore

import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';

// Importar modelos
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/models/categoria.dart';
import 'package:master_palm/models/fornecedor.dart';

// Importar serviços
import 'package:master_palm/services/sync_firestore_script.dart';
import 'package:master_palm/services/store_resolver_service.dart';

void main(List<String> args) async {
  print('🚀 Script de Sincronização Firestore\n');
  print('=' * 60);

  // Parse argumentos
  final command = args.isNotEmpty ? args[0].toLowerCase() : 'all';

  if (command == 'help' || command == '--help' || command == '-h') {
    _printHelp();
    return;
  }

  try {
    // 1. Inicializar Firebase
    print('📡 Inicializando Firebase...');
    await Firebase.initializeApp();
    print('✅ Firebase inicializado\n');

    // 2. Inicializar Hive
    print('💾 Inicializando Hive...');

    // Usar diretório temporário para scripts CLI
    final tempDir = Directory.systemTemp.createTempSync('hive_sync');
    Hive.init(tempDir.path);

    // Registrar adaptadores
    Hive.registerAdapter(ProdutoAdapter());
    Hive.registerAdapter(ClienteAdapter());
    Hive.registerAdapter(VendaAdapter());
    Hive.registerAdapter(VendaItemAdapter());
    Hive.registerAdapter(CategoriaAdapter());
    Hive.registerAdapter(FornecedorAdapter());

    print('✅ Hive inicializado\n');

    // 3. Resolver lojaId
    print('🏪 Resolvendo lojaId...');
    final lojaId = await StoreResolverService.resolve();
    if (lojaId == null || lojaId.isEmpty) {
      print('❌ ERRO: Não foi possível resolver o lojaId');
      print('   Certifique-se de que a sessão está configurada corretamente.\n');
      exit(1);
    }
    print('✅ LojaId: $lojaId\n');
    print('=' * 60);

    // 4. Executar comando
    switch (command) {
      case 'all':
      case 'tudo':
        await _syncAll();
        break;

      case 'produtos':
      case 'products':
        await _syncProdutos();
        break;

      case 'vendas':
      case 'sales':
        await _syncVendas();
        break;

      case 'stats':
      case 'estatisticas':
        await _showStats(lojaId);
        break;

      default:
        print('❌ Comando desconhecido: $command');
        print('   Use "help" para ver comandos disponíveis.\n');
        exit(1);
    }

    print('=' * 60);
    print('✅ Script finalizado com sucesso!');
    print('=' * 60);

  } catch (e, stack) {
    print('\n❌ ERRO AO EXECUTAR SCRIPT (type=${e.runtimeType})');
    print('\nStack trace:');
    print(stack);
    exit(1);
  }
}

/// Sincroniza tudo
Future<void> _syncAll() async {
  print('\n🔄 SINCRONIZAÇÃO COMPLETA\n');

  final results = await SyncFirestoreScript.syncTudo();

  print('\n📊 RESULTADOS:');
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
}

/// Sincroniza apenas produtos
Future<void> _syncProdutos() async {
  print('\n📦 SINCRONIZANDO APENAS PRODUTOS\n');

  await SyncFirestoreScript.syncApenasProdutos();

  print('\n✅ Sincronização de produtos concluída!');
}

/// Sincroniza apenas vendas
Future<void> _syncVendas() async {
  print('\n💰 SINCRONIZANDO APENAS VENDAS\n');

  await SyncFirestoreScript.syncApenasVendas();

  print('\n✅ Sincronização de vendas concluída!');
}

/// Mostra estatísticas do Firestore
Future<void> _showStats(String lojaId) async {
  print('\n📊 ESTATÍSTICAS DO FIRESTORE\n');

  final stats = await SyncFirestoreScript.getEstatisticas(lojaId);

  print('Loja: $lojaId\n');
  print('📦 Produtos: ${stats['produtos'] ?? 0}');
  print('👥 Clientes: ${stats['clientes'] ?? 0}');
  print('💰 Vendas: ${stats['vendas'] ?? 0}');
  print('🏷️ Categorias: ${stats['categorias'] ?? 0}');
  print('');
}

/// Mostra ajuda
void _printHelp() {
  print('''
USO:
  dart run scripts/sync_firestore.dart [comando]

COMANDOS:
  all, tudo          Sincroniza TODAS as coleções (padrão)
  produtos           Sincroniza apenas produtos
  vendas             Sincroniza apenas vendas
  stats              Mostra estatísticas do Firestore
  help               Mostra esta ajuda

EXEMPLOS:
  # Sincronizar tudo
  dart run scripts/sync_firestore.dart

  # Sincronizar apenas produtos
  dart run scripts/sync_firestore.dart produtos

  # Ver estatísticas
  dart run scripts/sync_firestore.dart stats

IMPORTANTE:
  - Certifique-se de que o Firebase está configurado
  - Certifique-se de que há dados no Hive para sincronizar
  - A sincronização pode demorar alguns minutos dependendo da quantidade de dados

''');
}
