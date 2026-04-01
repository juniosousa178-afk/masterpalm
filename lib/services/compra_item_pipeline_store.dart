import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/compra_item_pipeline.dart';

class CompraItemPipelineStore {
  CompraItemPipelineStore._();

  static Future<Box<CompraItemPipeline>?> openBox(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return null;
    if (!Hive.isAdapterRegistered(34)) {
      debugPrint('[PIPELINE] Adapter 34 (CompraItemPipeline) não registrado');
      return null;
    }
    final name = HiveBoxNames.compraItemPipeline(id);
    try {
      if (Hive.isBoxOpen(name)) {
        return Hive.box<CompraItemPipeline>(name);
      }
      return await Hive.openBox<CompraItemPipeline>(name);
    } catch (e) {
      debugPrint('[PIPELINE] Falha ao abrir $name (type=${e.runtimeType})');
      return null;
    }
  }
}
