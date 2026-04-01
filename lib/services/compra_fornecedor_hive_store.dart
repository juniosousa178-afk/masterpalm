import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/compra_fornecedor.dart';

/// Abertura tolerante a falha — espelha [FinanceiroHiveStore].
class CompraFornecedorHiveStore {
  CompraFornecedorHiveStore._();

  static Future<Box<CompraFornecedor>?> openBox(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return null;
    if (!Hive.isAdapterRegistered(32)) {
      debugPrint(
          '[COMPRAS_FORN] Adapter 32 (CompraFornecedor) não registrado');
      return null;
    }
    if (!Hive.isAdapterRegistered(33)) {
      debugPrint(
          '[COMPRAS_FORN] Adapter 33 (CompraFornecedorItem) não registrado');
      return null;
    }
    final name = HiveBoxNames.comprasFornecedor(id);
    try {
      if (Hive.isBoxOpen(name)) {
        return Hive.box<CompraFornecedor>(name);
      }
      return await Hive.openBox<CompraFornecedor>(name);
    } catch (e) {
      debugPrint(
          '[COMPRAS_FORN] Falha ao abrir $name (type=${e.runtimeType})');
      return null;
    }
  }
}
