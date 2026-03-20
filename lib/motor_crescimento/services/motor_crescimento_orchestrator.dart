// lib/motor_crescimento/services/motor_crescimento_orchestrator.dart
// Etapa 1: Orquestrador do Motor de Crescimento IA. Carrega painel (oportunidades + ticket médio).

import '../models/oportunidade_crescimento.dart';
import 'motor_crescimento_detector_service.dart';

/// Resultado do painel para o Motor de Crescimento IA (Etapa 1).
class MotorCrescimentoPainel {
  final List<OportunidadeCrescimento> oportunidades;
  final double ticketMedio;
  final int totalProdutosParados;
  final int totalEstoqueBaixo;

  const MotorCrescimentoPainel({
    required this.oportunidades,
    required this.ticketMedio,
    required this.totalProdutosParados,
    required this.totalEstoqueBaixo,
  });
}

/// Orquestrador único para o painel do Motor de Crescimento IA.
/// Etapa 1: apenas carrega oportunidades e ticket médio.
class MotorCrescimentoOrchestrator {
  MotorCrescimentoOrchestrator._();

  /// Carrega o painel: oportunidades (parados + estoque baixo) e ticket médio.
  /// [limit] opcional: retorna no máximo N oportunidades (ex.: 50 para abrir a tela rápido).
  static Future<MotorCrescimentoPainel> carregarPainel(
    String lojaId, {
    int• limit,
  }) async {
    if (lojaId.trim().isEmpty) {
      return const MotorCrescimentoPainel(
        oportunidades: [],
        ticketMedio: 0.0,
        totalProdutosParados: 0,
        totalEstoqueBaixo: 0,
      );
    }

    final oportunidades = await MotorCrescimentoDetectorService.detectarOportunidades(
      lojaId,
      limit: limit,
    );
    final ticketMedio =
        await MotorCrescimentoDetectorService.calcularTicketMedio(lojaId);

    final parados = oportunidades
        .where((o) => o.tipo == TipoOportunidade.produtoParado)
        .length;
    final estoqueBaixo = oportunidades
        .where((o) => o.tipo == TipoOportunidade.estoqueBaixo)
        .length;

    return MotorCrescimentoPainel(
      oportunidades: oportunidades,
      ticketMedio: ticketMedio,
      totalProdutosParados: parados,
      totalEstoqueBaixo: estoqueBaixo,
    );
  }
}
