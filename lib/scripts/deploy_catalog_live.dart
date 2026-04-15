// Script para fazer deploy completo do catálogo para LIVE
//
// NÃO use o `dart` isolado do PATH (sem Flutter): hive_flutter precisa de dart:ui
// e o compilador acusa Offset/Rect como método inexistente.
//
// Opções (na raiz do projeto):
//   .\scripts\deploy-catalogo.ps1
//   fvm dart run lib/scripts/deploy_catalog_live.dart   // se FVM estiver no PATH
// Ou use o dart.exe do Flutter: ...\flutter\bin\cache\dart-sdk\bin\dart.exe run lib/scripts/deploy_catalog_live.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../services/catalogo_sync_service.dart';
import '../services/store_resolver_facade.dart';
import '../firebase_options.dart';

Future<void> main() async {
  debugPrint('🚀 Iniciando deploy do catálogo para LIVE...\n');

  try {
    // 1. Inicializar Firebase
    debugPrint('📱 Inicializando Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase inicializado!\n');

    // 2. Inicializar Hive
    debugPrint('💾 Inicializando Hive...');
    await Hive.initFlutter();
    Hive.registerAdapter(ProdutoAdapter());
    debugPrint('✅ Hive inicializado!\n');

    // 3. Obter loja ativa
    debugPrint('🏪 Obtendo loja ativa...');
    final lojaId = await StoreResolverFacade.resolveForAdminApp();
    if (lojaId == null || lojaId.isEmpty) {
      throw Exception('❌ Nenhuma loja ativa encontrada!');
    }
    debugPrint('✅ Loja ativa: $lojaId\n');

    // 4. Abrir box de produtos
    debugPrint('📦 Abrindo box de produtos...');
    final boxName = HiveBoxNames.produtos(lojaId);
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<Produto>(boxName);
    }
    final box = Hive.box<Produto>(boxName);
    debugPrint('✅ Box aberto! Total de produtos: ${box.length}\n');

    // 5. Fazer deploy para LIVE
    debugPrint('🚀 Fazendo deploy de todos os produtos para LIVE...');
    debugPrint('⏳ Isso pode levar alguns minutos...\n');

    await CatalogoSyncService.pushAllToLive(lojaIdOverride: lojaId);

    debugPrint('\n✅ Deploy concluído com sucesso!');
    debugPrint('📊 Total de produtos sincronizados: ${box.length}');
    debugPrint('🌐 Catálogo LIVE atualizado!\n');

    // 6. Verificar produtos com variações
    final produtosComVariacoes = box.values.where((p) => p.usaVariacoes).length;
    debugPrint('📋 Produtos com variações (tamanho + cor): $produtosComVariacoes');

    debugPrint('\n🎉 Deploy completo! Todas as modificações foram enviadas para o catálogo online.');

  } catch (e, stackTrace) {
    debugPrint('\n❌ Erro durante o deploy (type=${e.runtimeType})');
    debugPrint('Stack trace: $stackTrace');
    rethrow;
  } finally {
    // Fechar Hive
    await Hive.close();
  }
}
