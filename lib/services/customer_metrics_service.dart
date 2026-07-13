// Agrega métricas de cliente a partir de vendas Hive (somente leitura).
// Não altera engines de venda/sync.

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/venda_metrics_filter.dart';
import '../models/venda.dart';
import '../utils/store_access_guard.dart';

class CustomerMetrics {
  const CustomerMetrics({
    required this.quantidadePedidos,
    required this.valorTotalComprado,
    required this.ticketMedio,
    this.ultimaCompra,
    this.clienteDesde,
    this.vip = false,
    this.recorrente = false,
  });

  final int quantidadePedidos;
  final double valorTotalComprado;
  final double ticketMedio;
  final DateTime? ultimaCompra;
  final DateTime? clienteDesde;
  final bool vip;
  final bool recorrente;

  static const empty = CustomerMetrics(
    quantidadePedidos: 0,
    valorTotalComprado: 0,
    ticketMedio: 0,
  );
}

/// Serviço isolado — não modifica Venda nem Sync.
class CustomerMetricsService {
  /// Agrega vendas do [clienteNome] e/ou [clienteId] na loja.
  static CustomerMetrics fromVendasList(
    Iterable<Venda> vendas, {
    String? clienteNome,
    String? clienteId,
    String? clienteTelefone,
    double vipMinTotal = 1000,
  }) {
    final nomeNorm = (clienteNome ?? '').trim().toLowerCase();
    final idNorm = (clienteId ?? '').trim();

    final matched = <Venda>[];
    for (final v in vendas) {
      if (!incluirVendaEmMetricas(v)) continue;
      final vn = v.clienteNome.trim().toLowerCase();
      final byName = nomeNorm.isNotEmpty && vn == nomeNorm;
      final byId = idNorm.isNotEmpty &&
          (v.clienteId ?? '').trim().isNotEmpty &&
          (v.clienteId ?? '').trim() == idNorm;
      if (byName || byId) matched.add(v);
    }

    if (matched.isEmpty) return CustomerMetrics.empty;

    matched.sort((a, b) => a.data.compareTo(b.data));
    final total = matched.fold<double>(0, (s, v) => s + v.total);
    final qtd = matched.length;
    return CustomerMetrics(
      quantidadePedidos: qtd,
      valorTotalComprado: total,
      ticketMedio: qtd > 0 ? total / qtd : 0,
      ultimaCompra: matched.last.data,
      clienteDesde: matched.first.data,
      vip: total >= vipMinTotal,
      recorrente: qtd >= 2,
    );
  }

  static Future<CustomerMetrics> loadForCliente({
    required String lojaId,
    String? clienteNome,
    String? clienteTelefone,
    String? clienteId,
  }) async {
    if (lojaId.isEmpty) return CustomerMetrics.empty;
    try {
      lojaId =
          StoreAccessGuard.requireLojaId(lojaId, context: 'CustomerMetrics');
      final boxName = HiveBoxNames.vendas(lojaId);
      Box<Venda> box;
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<Venda>(boxName);
      } else {
        StoreAccessGuard.auditBoxAccess(boxName, lojaId, op: 'open');
        box = await Hive.openBox<Venda>(boxName);
      }
      return fromVendasList(
        box.values.where((v) => v.lojaId == null || v.lojaId == lojaId),
        clienteNome: clienteNome,
        clienteId: clienteId,
      );
    } catch (_) {
      return CustomerMetrics.empty;
    }
  }
}
