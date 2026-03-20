// lib/motor_crescimento/services/motor_crescimento_resumo_service.dart
// Gera resumo de crescimento (parados, estoque baixo, top vendas, carrinhos abandonados, ticket, meta).
// Reutiliza Hive, MotorCrescimentoOrchestrator e CarrinhoAbandonadoService. Sem queries pesadas.

import 'package:hive/hive.dart';

import '../../core/hive_box_names.dart';
import '../../models/meta.dart';
import '../../models/venda.dart';
import '../../services/carrinho_abandonado_service.dart';
import '../../utils/store_access_guard.dart';
import '../models/crescimento_resumo.dart';
import 'motor_crescimento_orchestrator.dart';

/// Quantidade de produtos a considerar como "top vendas" no resumo.
const int _topVendasCount = 5;

/// Serviço que agrega dados existentes para o Painel de Crescimento.
class MotorCrescimentoResumoService {
  MotorCrescimentoResumoService._();

  /// Gera resumo da loja reutilizando dados já carregados (Hive, motor, carrinhos abandonados).
  static Future<CrescimentoResumo> gerarResumo(String lojaId) async {
    if (lojaId.trim().isEmpty) {
      return const CrescimentoResumo();
    }

    try {
      final painel = await MotorCrescimentoOrchestrator.carregarPainel(lojaId);
      final carrinhos = await CarrinhoAbandonadoService.listarCarrinhosAbandonadosCatalogo(
        lojaId: lojaId,
        minutosAbandono: CarrinhoAbandonadoService.minutosAbandonoCatalogo,
      );
      final ticketMedio = painel.ticketMedio;
      final produtosParados = painel.totalProdutosParados;
      final estoqueBaixo = painel.totalEstoqueBaixo;

      int produtosTopVenda = 0;
      double metaMes = 0.0;

      try {
        final vendasBoxName = HiveBoxNames.vendas(lojaId);
        Box<Venda>? vendasBox;
        if (Hive.isBoxOpen(vendasBoxName)) {
          vendasBox = Hive.box<Venda>(vendasBoxName);
        } else {
          StoreAccessGuard.auditBoxAccess(vendasBoxName, lojaId, op: 'open');
          vendasBox = await Hive.openBox<Venda>(vendasBoxName);
        }
        final vendasLoja = vendasBox.values.where((v) => v.lojaId == lojaId).toList();
        final now = DateTime.now();
        final mesInicio = DateTime(now.year, now.month, 1);
        final mesFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        final vendasMes = vendasLoja.where((v) => !v.data.isBefore(mesInicio) && !v.data.isAfter(mesFim)).toList();

        final Map<String, int> qtdPorProduto = {};
        for (final v in vendasMes) {
          for (final item in v.itensOuVazio) {
            final nome = item.produtoNome.trim();
            if (nome.isEmpty) continue;
            qtdPorProduto[nome] = (qtdPorProduto[nome] ?? 0) + item.quantidade;
          }
          if (v.itensOuVazio.isEmpty && v.produtosDescricao.trim().isNotEmpty) {
            final nome = v.produtosDescricao.trim();
            qtdPorProduto[nome] = (qtdPorProduto[nome] ?? 0) + v.quantidade;
          }
        }
        final ordenados = qtdPorProduto.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        produtosTopVenda = ordenados.take(_topVendasCount).length;
      } catch (_) {}

      try {
        final metaBoxName = 'metas_$lojaId';
        Box<Meta>? metaBox;
        if (Hive.isBoxOpen(metaBoxName)) {
          metaBox = Hive.box<Meta>(metaBoxName);
        } else {
          StoreAccessGuard.auditBoxAccess(metaBoxName, lojaId, op: 'open');
          metaBox = await Hive.openBox<Meta>(metaBoxName);
        }
        final mesRef = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
        for (final m in metaBox.values) {
          if (m.lojaId != null && m.lojaId != lojaId) continue;
          if (m.mesRef == mesRef) {
            metaMes = m.metaMensal;
            break;
          }
        }
      } catch (_) {}

      return CrescimentoResumo(
        produtosParados: produtosParados,
        estoqueBaixo: estoqueBaixo,
        produtosTopVenda: produtosTopVenda,
        carrinhosAbandonados: carrinhos.length,
        ticketMedio: ticketMedio,
        metaMes: metaMes,
      );
    } catch (_) {
      return const CrescimentoResumo();
    }
  }
}
