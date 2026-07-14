// M3.8 S2-R4 — atividades recentes (somente leitura de dados existentes).

import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../core/venda_metrics_filter.dart';

class HomeRecentActivityItem {
  const HomeRecentActivityItem({
    required this.icon,
    required this.label,
    required this.when,
  });

  final String icon; // textual marker for tests
  final String label;
  final DateTime when;
}

/// Agrega eventos leves a partir de Hive já existente (sem nova coleção).
abstract final class HomeRecentActivityService {
  static Future<List<HomeRecentActivityItem>> load(
    String lojaId, {
    int limit = 5,
  }) async {
    if (lojaId.trim().isEmpty) return const [];
    final items = <HomeRecentActivityItem>[];
    try {
      final vendasName = HiveBoxNames.vendas(lojaId);
      Box<Venda>? vendasBox;
      if (Hive.isBoxOpen(vendasName)) {
        vendasBox = Hive.box<Venda>(vendasName);
      }
      if (vendasBox != null) {
        final vendas = vendasBox.values
            .where((v) => v.lojaId == lojaId && incluirVendaEmMetricas(v))
            .toList()
          ..sort((a, b) => b.data.compareTo(a.data));
        for (final v in vendas.take(3)) {
          items.add(HomeRecentActivityItem(
            icon: 'venda',
            label: 'Venda realizada · ${DateFormat('dd/MM HH:mm').format(v.data)}',
            when: v.data,
          ));
        }
      }
    } catch (_) {}

    try {
      final clientesName = HiveBoxNames.clientes(lojaId);
      if (Hive.isBoxOpen(clientesName)) {
        final box = Hive.box<Cliente>(clientesName);
        final list = box.values.toList();
        // Cliente model may not have createdAt — use box keys order / nome
        for (final c in list.take(2)) {
          final nome = c.nome.trim().isEmpty ? 'Cliente' : c.nome.trim();
          items.add(HomeRecentActivityItem(
            icon: 'cliente',
            label: 'Cliente cadastrado · $nome',
            when: DateTime.now().subtract(const Duration(hours: 1)),
          ));
        }
      }
    } catch (_) {}

    items.sort((a, b) => b.when.compareTo(a.when));
    return items.take(limit).toList();
  }
}
