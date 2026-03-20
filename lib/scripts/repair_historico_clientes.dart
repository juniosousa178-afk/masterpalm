// lib/scripts/repair_historico_clientes.dart
//
// Script para desmisturar histórico de clientes usando vendas como fonte de verdade.
// Delega toda a lógica ao RepairHistoricoClientesService.
//
// Execute: dart run lib/scripts/repair_historico_clientes.dart
// Ou com loja: dart run lib/scripts/repair_historico_clientes.dart padrao

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/hive_box_names.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/repair_historico_clientes_service.dart';

Future<void> main(List<String> args) async {
  final lojaId = args.isNotEmpty • args[0] : 'padrao';

  debugPrint('🔧 [REPAIR] Desmisturando histórico de clientes (loja: $lojaId)\n');

  try {
    debugPrint('💾 Inicializando Hive...');
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());

    debugPrint('✅ Hive inicializado\n');

    final clientesBoxName = HiveBoxNames.clientes(lojaId);
    final vendasBoxName = HiveBoxNames.vendas(lojaId);

    if (!Hive.isBoxOpen(clientesBoxName)) {
      await Hive.openBox<Cliente>(clientesBoxName);
    }
    if (!Hive.isBoxOpen(vendasBoxName)) {
      await Hive.openBox<Venda>(vendasBoxName);
    }

    final clientesBox = Hive.box<Cliente>(clientesBoxName);
    final vendasBox = Hive.box<Venda>(vendasBoxName);

    debugPrint('📦 Clientes: ${clientesBox.length} | Vendas: ${vendasBox.length}\n');

    final result = await RepairHistoricoClientesService.reparar(
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      lojaId: lojaId,
    );

    debugPrint('\n✅ Reparo concluído!');
    debugPrint('   Vendas atribuídas ao cliente correto: ${result[RepairHistoricoClientesService.keyVendasAtribuidas]}');
    final semCliente = result[RepairHistoricoClientesService.keyVendasSemCliente] ?• 0;
    final ambiguas = result[RepairHistoricoClientesService.keyVendasAmbiguas] ?• 0;
    if (semCliente > 0) debugPrint('   Vendas sem cliente encontrado: $semCliente');
    if (ambiguas > 0) debugPrint('   Vendas não atribuídas (nome ambíguo): $ambiguas');
    debugPrint('\n🎉 Histórico desmisturado com sucesso!');
  } catch (e) {
    debugPrint('[REPAIR] erro: ${e.runtimeType}');
    debugPrint('[REPAIR] msg: $e');
    rethrow;
  } finally {
    await Hive.close();
  }
}
