import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/conta_pagar.dart';

class ContaPagarHiveStore {
  ContaPagarHiveStore._();

  static void ensureAdapterRegistered() {
    if (!Hive.isAdapterRegistered(35)) {
      Hive.registerAdapter(ContaPagarAdapter());
    }
  }

  static Future<Box<ContaPagar>?> openBox(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return null;
    ensureAdapterRegistered();
    if (!Hive.isAdapterRegistered(35)) {
      debugPrint('[CP-HIVE] Adapter 35 (ContaPagar) não registrado');
      return null;
    }
    final name = HiveBoxNames.contasPagar(id);
    try {
      if (Hive.isBoxOpen(name)) {
        return Hive.box<ContaPagar>(name);
      }
      return await Hive.openBox<ContaPagar>(name);
    } catch (e) {
      debugPrint('[CP-HIVE] Falha ao abrir $name (type=${e.runtimeType})');
      return null;
    }
  }
}
