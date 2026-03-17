// Script para limpar cache local de loja (forçar reload do Firestore)
// Execute com: flutter run scripts/clear_local_store_cache.dart

import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  print('🧹 Limpando cache local de loja...\n');

  try {
    // Inicializar Hive
    final appDocDir = await getApplicationDocumentsDirectory();
    Hive.init(appDocDir.path);

    print('📁 Diretório Hive: ${appDocDir.path}\n');

    // Limpar store_id do Hive sessao
    try {
      final sessao = await Hive.openBox('sessao');
      final storeIdAntigo = sessao.get('store_id');

      if (storeIdAntigo != null) {
        print('🗑️  Removendo store_id antigo da sessão: $storeIdAntigo');
        await sessao.delete('store_id');
        print('✅ store_id removido de sessao');
      } else {
        print('ℹ️  Nenhum store_id encontrado em sessao');
      }

      await sessao.close();
    } catch (e) {
      print('⚠️  Erro ao limpar sessao (type=${e.runtimeType})');
    }

    // Limpar store_id do Hive config
    try {
      final config = await Hive.openBox('config');
      final storeIdAntigo = config.get('store_id');
      final lastLojaAntigo = config.get('last_loja_id');

      if (storeIdAntigo != null) {
        print('🗑️  Removendo store_id antigo de config: $storeIdAntigo');
        await config.delete('store_id');
        print('✅ store_id removido de config');
      }

      if (lastLojaAntigo != null) {
        print('🗑️  Removendo last_loja_id antigo de config: $lastLojaAntigo');
        await config.delete('last_loja_id');
        print('✅ last_loja_id removido de config');
      }

      await config.close();
    } catch (e) {
      print('⚠️  Erro ao limpar config (type=${e.runtimeType})');
    }

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('✅ CACHE LIMPO COM SUCESSO!');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('\n📝 Próximo passo:');
    print('   1. Reinicie o aplicativo');
    print('   2. Faça login novamente');
    print('   3. O app irá buscar a loja correta do Firestore');
    print('   4. A loja com logo e banners será carregada\n');

  } catch (e) {
    print('❌ Erro durante limpeza (type=${e.runtimeType})');
    exit(1);
  }

  exit(0);
}
