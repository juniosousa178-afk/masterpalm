// lib/services/financeiro_hive_store.dart
// Abertura tolerante a falha — não quebra o app se box/adapter falhar.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/gasto_fixo_mensal.dart';
import '../models/lancamento_financeiro.dart';

class FinanceiroHiveStore {
  FinanceiroHiveStore._();

  static Future<Box<LancamentoFinanceiro>?> openLancamentosBox(
      String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return null;
    if (!Hive.isAdapterRegistered(30)) {
      debugPrint(
          '[FINANCEIRO_HIVE] Adapter 30 (LancamentoFinanceiro) não registrado');
      return null;
    }
    final name = HiveBoxNames.lancamentosFinanceiros(id);
    try {
      if (Hive.isBoxOpen(name)) {
        return Hive.box<LancamentoFinanceiro>(name);
      }
      return await Hive.openBox<LancamentoFinanceiro>(name);
    } catch (e) {
      debugPrint(
          '[FINANCEIRO_HIVE] Falha ao abrir $name (type=${e.runtimeType})');
      return null;
    }
  }

  static Future<Box<GastoFixoMensal>?> openGastosFixosBox(String lojaId) async {
    final id = lojaId.trim();
    if (id.isEmpty) return null;
    if (!Hive.isAdapterRegistered(31)) {
      debugPrint(
          '[FINANCEIRO_HIVE] Adapter 31 (GastoFixoMensal) não registrado');
      return null;
    }
    final name = HiveBoxNames.gastosFixosMensais(id);
    try {
      if (Hive.isBoxOpen(name)) {
        return Hive.box<GastoFixoMensal>(name);
      }
      return await Hive.openBox<GastoFixoMensal>(name);
    } catch (e) {
      debugPrint(
          '[FINANCEIRO_HIVE] Falha ao abrir $name (type=${e.runtimeType})');
      return null;
    }
  }
}
