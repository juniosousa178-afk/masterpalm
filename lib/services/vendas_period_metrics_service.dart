// Métricas de vendas por período (hoje / mês / ano) — bruto, líquido, descontos, lucro.
// Reutiliza incluirVendaEmMetricas. Não altera engine de venda nem financeiro.

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/venda_metrics_filter.dart';
import '../models/venda.dart';
import '../utils/store_access_guard.dart';

class VendasPeriodMetrics {
  const VendasPeriodMetrics({
    required this.bruto,
    required this.liquido,
    required this.descontos,
    required this.lucro,
    required this.quantidade,
  });

  final double bruto;
  final double liquido;
  final double descontos;
  final double lucro;
  final int quantidade;

  double get ticketMedio => quantidade > 0 ? liquido / quantidade : 0;

  static const zero = VendasPeriodMetrics(
    bruto: 0,
    liquido: 0,
    descontos: 0,
    lucro: 0,
    quantidade: 0,
  );
}

class VendasPeriodMetricsBundle {
  const VendasPeriodMetricsBundle({
    required this.hoje,
    required this.mes,
    required this.ano,
  });

  final VendasPeriodMetrics hoje;
  final VendasPeriodMetrics mes;
  final VendasPeriodMetrics ano;
}

/// Desconto absoluto de uma venda (somente leitura de campos existentes).
double descontoAbsolutoVenda(Venda v) {
  if (v.descontoValor > 0) return v.descontoValor;
  // Legado: só % — estima a partir do líquido aproximado.
  if (v.desconto > 0 && v.desconto < 100) {
    final fator = 1 - (v.desconto / 100);
    if (fator > 0) {
      final brutoEst = v.total / fator;
      final d = brutoEst - v.total;
      return d > 0 ? d : 0;
    }
  }
  return 0;
}

/// Lucro simples a partir de campos já persistidos na venda (sem engine financeiro).
double lucroSimplesVenda(Venda v) {
  return v.total - v.custoProdutos - v.taxas;
}

VendasPeriodMetrics agregarVendasPeriodo(
  Iterable<Venda> vendas, {
  required DateTime inicio,
  required DateTime fimExclusivo,
  String? lojaId,
}) {
  double liquido = 0;
  double descontos = 0;
  double lucro = 0;
  var qtd = 0;
  for (final v in vendas) {
    if (lojaId != null && lojaId.isNotEmpty) {
      if (v.lojaId != null && v.lojaId != lojaId) continue;
    }
    if (!incluirVendaEmMetricas(v)) continue;
    if (v.data.isBefore(inicio) || !v.data.isBefore(fimExclusivo)) continue;
    liquido += v.total;
    descontos += descontoAbsolutoVenda(v);
    lucro += lucroSimplesVenda(v);
    qtd++;
  }
  return VendasPeriodMetrics(
    bruto: liquido + descontos,
    liquido: liquido,
    descontos: descontos,
    lucro: lucro,
    quantidade: qtd,
  );
}

class VendasPeriodMetricsService {
  static Future<VendasPeriodMetricsBundle> load(String lojaId) async {
    if (lojaId.isEmpty) {
      return const VendasPeriodMetricsBundle(
        hoje: VendasPeriodMetrics.zero,
        mes: VendasPeriodMetrics.zero,
        ano: VendasPeriodMetrics.zero,
      );
    }
    lojaId = StoreAccessGuard.requireLojaId(
      lojaId,
      context: 'VendasPeriodMetrics',
    );
    final now = DateTime.now();
    final hojeInicio = DateTime(now.year, now.month, now.day);
    final amanha = hojeInicio.add(const Duration(days: 1));
    final mesInicio = DateTime(now.year, now.month, 1);
    final proxMes = DateTime(now.year, now.month + 1, 1);
    final anoInicio = DateTime(now.year, 1, 1);
    final proxAno = DateTime(now.year + 1, 1, 1);

    try {
      final boxName = HiveBoxNames.vendas(lojaId);
      Box<Venda> box;
      if (Hive.isBoxOpen(boxName)) {
        box = Hive.box<Venda>(boxName);
      } else {
        StoreAccessGuard.auditBoxAccess(boxName, lojaId, op: 'open');
        box = await Hive.openBox<Venda>(boxName);
      }
      final values = box.values;
      return VendasPeriodMetricsBundle(
        hoje: agregarVendasPeriodo(
          values,
          inicio: hojeInicio,
          fimExclusivo: amanha,
          lojaId: lojaId,
        ),
        mes: agregarVendasPeriodo(
          values,
          inicio: mesInicio,
          fimExclusivo: proxMes,
          lojaId: lojaId,
        ),
        ano: agregarVendasPeriodo(
          values,
          inicio: anoInicio,
          fimExclusivo: proxAno,
          lojaId: lojaId,
        ),
      );
    } catch (_) {
      return const VendasPeriodMetricsBundle(
        hoje: VendasPeriodMetrics.zero,
        mes: VendasPeriodMetrics.zero,
        ano: VendasPeriodMetrics.zero,
      );
    }
  }
}
