// Diagnóstico read-only: compras com saldo em aberto sem contas a pagar geradas.

import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';
import 'compra_fornecedor_hive_store.dart';
import 'conta_pagar_hive_store.dart';
import 'conta_pagar_service.dart';

class CompraSemContasPagarDiagnostico {
  CompraSemContasPagarDiagnostico({
    required this.compraId,
    required this.fornecedorNome,
    required this.valorTotal,
    required this.valorEmAberto,
    required this.dataCompra,
    required this.statusPagamento,
  });

  final String compraId;
  final String fornecedorNome;
  final double valorTotal;
  final double valorEmAberto;
  final DateTime dataCompra;
  final String statusPagamento;
}

abstract final class ContaPagarMigracaoDiagnosticoService {
  ContaPagarMigracaoDiagnosticoService._();

  /// Não altera dados — apenas lista candidatos à migração manual futura.
  static Future<List<CompraSemContasPagarDiagnostico>> listarComprasSemParcelas({
    required String lojaId,
  }) async {
    final compraBox = await CompraFornecedorHiveStore.openBox(lojaId);
    final cpBox = await ContaPagarHiveStore.openBox(lojaId);
    if (compraBox == null) return [];

    final out = <CompraSemContasPagarDiagnostico>[];
    for (final c in compraBox.values) {
      if (c.lojaId.trim() != lojaId.trim()) continue;
      if (c.statusCompra != CompraFornecedorStatusCompra.confirmada) continue;
      if (c.valorEmAberto <= 0.009) continue;
      if (cpBox != null &&
          ContaPagarService.existeParcelasParaCompra(cpBox, c.id)) {
        continue;
      }
      out.add(
        CompraSemContasPagarDiagnostico(
          compraId: c.id,
          fornecedorNome: c.fornecedorNome,
          valorTotal: c.valorTotalFinanceiro,
          valorEmAberto: c.valorEmAberto,
          dataCompra: c.dataCompra,
          statusPagamento: c.statusPagamento,
        ),
      );
    }
    out.sort((a, b) => b.dataCompra.compareTo(a.dataCompra));
    return out;
  }
}
