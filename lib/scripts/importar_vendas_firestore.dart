// lib/scripts/importar_vendas_firestore.dart
//
// Script para importar vendas do Firestore para o Hive
// SEM duplicar e SEM recalcular as já existentes.
// Importa APENAS as vendas que não estão no aparelho.
//
// Execute de dentro do app (ex: menu ou botão) ou:
//   dart run lib/scripts/importar_vendas_firestore.dart
//   dart run lib/scripts/importar_vendas_firestore.dart padrao
//
// Argumentos: [lojaId] - opcional, padrão 'padrao'

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/hive_box_names.dart';
import '../firebase_options.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/importar_vendas_firestore_service.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main(List<String> args) async {
  // OBRIGATÓRIO: primeiro comando - Firebase precisa dos bindings
  WidgetsFlutterBinding.ensureInitialized();

  final lojaId = args.isNotEmpty ? args[0] : 'padrao';

  debugPrint('');
  debugPrint('📥 [IMPORT-VENDAS] Importando vendas do Firestore (loja: $lojaId)');
  debugPrint('   → Sem duplicar | Sem recalcular existentes | Apenas novas');
  debugPrint('');

  try {
    // 1. Inicializar Firebase (só se ainda não foi inicializado)
    if (Firebase.apps.isEmpty) {
      debugPrint('📡 Inicializando Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase inicializado');
    } else {
      debugPrint('✅ Firebase já estava inicializado');
    }

    // 3. Inicializar Hive
    debugPrint('💾 Inicializando Hive...');
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());

    debugPrint('✅ Hive inicializado');

    // 4. Abrir box de vendas
    final vendasBoxName = HiveBoxNames.vendas(lojaId);
    if (!Hive.isBoxOpen(vendasBoxName)) {
      await Hive.openBox<Venda>(vendasBoxName);
    }
    final vendasBox = Hive.box<Venda>(vendasBoxName);

    debugPrint('📦 Vendas locais antes: ${vendasBox.length}');
    debugPrint('');

    // 5. Importar (sem duplicar)
    final resultado = await ImportarVendasFirestoreService.importar(
      lojaId: lojaId,
      vendasBox: vendasBox,
    );

    debugPrint('');
    debugPrint('═══════════════════════════════════════');
    debugPrint('📊 RESULTADO DA IMPORTAÇÃO');
    debugPrint('═══════════════════════════════════════');
    debugPrint('   Total no Firestore: ${resultado.totalNoFirestore}');
    debugPrint('   Já existiam (puladas): ${resultado.jaExistentes}');
    debugPrint('   Novas importadas: ${resultado.importadas}');
    debugPrint('   Erros: ${resultado.erros}');
    debugPrint('   Vendas locais agora: ${vendasBox.length}');
    debugPrint('═══════════════════════════════════════');
    debugPrint('');
    debugPrint('✅ Importação concluída!');
    debugPrint('');
  } catch (e, st) {
    debugPrint('');
    debugPrint('❌ [IMPORT-VENDAS] Erro (type=${e.runtimeType})');
    debugPrint('   $e');
    debugPrint('');
    debugPrint('Stack trace:');
    debugPrint(st.toString());
    rethrow;
  } finally {
    await Hive.close();
  }
}
