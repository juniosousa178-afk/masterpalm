// Script Flutter para limpar dados locais do Hive
// Execute com: flutter run scripts/clear_local_hive.dart

import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  print('🧹 Limpando dados locais do Hive...\n');

  try {
    // Inicializar Hive
    final appDocDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocDir.path);

    print('📁 Diretório Hive: ${appDocDir.path}\n');

    // Lista de boxes para limpar (exceto configurações essenciais)
    final boxesToClear = [
      'clientes',
      'vendas',
      'produtos',
      'fornecedores',
      'usuarios',
      'catalogos',
      'catalogo_config',
      'fechamentos',
      'cupons',
      'subcategorias',
    ];

    // Boxes que devem ser mantidos mas podem ter dados resetados
    final boxesToReset = [
      'sessao',      // Limpar sessão para forçar novo login
      'licenca',     // Limpar licença
    ];

    // Boxes que NUNCA devem ser tocados
    final boxesToKeep = [
      'config',           // Configurações do app
      'master_config',    // Configurações master
      'store_resolver',   // Resolver de loja
    ];

    print('🗑️  Limpando boxes de dados...');
    for (final boxName in boxesToClear) {
      try {
        if (await Hive.boxExists(boxName)) {
          final box = await Hive.openBox(boxName);
          await box.clear();
          await box.close();
          print('   ✅ $boxName - ${box.length} itens removidos');
        } else {
          print('   ⏭️  $boxName - não existe');
        }
      } catch (e) {
        print('   ❌ $boxName - erro (type=${e.runtimeType})');
      }
    }

    print('\n🔄 Resetando boxes de sessão...');
    for (final boxName in boxesToReset) {
      try {
        if (await Hive.boxExists(boxName)) {
          final box = await Hive.openBox(boxName);
          final itemCount = box.length;
          await box.clear();
          await box.close();
          print('   ✅ $boxName - $itemCount itens removidos');
        } else {
          print('   ⏭️  $boxName - não existe');
        }
      } catch (e) {
        print('   ❌ $boxName - erro (type=${e.runtimeType})');
      }
    }

    print('\n✅ Mantendo boxes essenciais:');
    for (final boxName in boxesToKeep) {
      try {
        if (await Hive.boxExists(boxName)) {
          final box = await Hive.openBox(boxName);
          print('   ✅ $boxName - ${box.length} itens mantidos');
          await box.close();
        } else {
          print('   ⏭️  $boxName - não existe');
        }
      } catch (e) {
        print('   ❌ $boxName - erro (type=${e.runtimeType})');
      }
    }

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('✅ LIMPEZA LOCAL CONCLUÍDA!');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('\n📝 Próximo passo:');
    print('   Reinicie o aplicativo para começar com dados limpos\n');

  } catch (e) {
    print('❌ Erro durante limpeza (type=${e.runtimeType})');
    exit(1);
  }

  exit(0);
}
