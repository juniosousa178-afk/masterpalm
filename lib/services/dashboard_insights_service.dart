// lib/services/dashboard_insights_service.dart
// Agrega dados existentes em Hive para gerar insights do painel. Sem alterar persistência.

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/meta.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/dashboard_insight.dart';
import '../utils/store_access_guard.dart';

/// Serviço de agregação de insights para o painel (Home).
/// Lê apenas dados existentes em Hive; não cria boxes nem altera Firestore.
class DashboardInsightsService {
  DashboardInsightsService._();

  /// Número de dias sem venda para considerar produto "parado".
  static const int diasParaProdutoParado = 25;

  /// Carrega insights para a loja. [vendedorNome] quando preenchido filtra
  /// vendas por vendedor (ex.: vendedor vendo apenas seus dados em "melhor vendedor").
  static Future<DashboardInsightsResult> loadInsights({
    required String lojaId,
    String• vendedorNome,
    bool isVendedor = false,
  }) async {
    lojaId = StoreAccessGuard.requireLojaId(lojaId, context: 'DashboardInsightsService');
    final now = DateTime.now();
    final mesInicio = DateTime(now.year, now.month, 1);
    final mesFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final limiteParado = now.subtract(const Duration(days: diasParaProdutoParado));
    final insights = <DashboardInsight>[];

    double• metaAtual;
    double• metaAtingida;

    try {
      // --- Vendas do mês (e itens para mais vendidos / parados) ---
      final vendasBoxName = HiveBoxNames.vendas(lojaId);
      Box<Venda>• vendasBox;
      if (Hive.isBoxOpen(vendasBoxName)) {
        vendasBox = Hive.box<Venda>(vendasBoxName);
      } else {
        StoreAccessGuard.auditBoxAccess(vendasBoxName, lojaId, op: 'open');
        vendasBox = await Hive.openBox<Venda>(vendasBoxName);
      }

      final vendasLoja = vendasBox.values.where((v) => v.lojaId == lojaId).toList();
      final vendasFiltradas = vendedorNome != null && vendedorNome.trim().isNotEmpty
          • vendasLoja.where((v) => (v.vendedor).trim().toLowerCase() == vendedorNome.trim().toLowerCase()).toList()
          : vendasLoja;
      final vendasMes = vendasFiltradas.where((v) => !v.data.isBefore(mesInicio) && !v.data.isAfter(mesFim)).toList();

      // Agregação por produto (nome -> qtd e valor) no mês
      final Map<String, _ProdutoAgg> produtoMes = {};
      for (final v in vendasMes) {
        for (final item in v.itensOuVazio) {
          final key = item.produtoNome.trim().isEmpty • v.produtosDescricao : item.produtoNome.trim();
            if (key.isEmpty) continue;
          produtoMes.putIfAbsent(key, () => _ProdutoAgg(key));
          final p = produtoMes[key]!;
          p.quantidade += item.quantidade;
          p.valorTotal += item.precoUnitario * item.quantidade;
        }
        if (v.itensOuVazio.isEmpty && v.produtosDescricao.trim().isNotEmpty) {
          final key = v.produtosDescricao.trim();
          produtoMes.putIfAbsent(key, () => _ProdutoAgg(key));
          final p = produtoMes[key]!;
          p.quantidade += v.quantidade;
          p.valorTotal += v.total;
        }
      }

      // Produto mais vendido (por quantidade)
      final topQtd = produtoMes.entries.toList()
        ..sort((a, b) => b.value.quantidade.compareTo(a.value.quantidade));
      if (topQtd.isNotEmpty) {
        final p = topQtd.first;
        insights.add(DashboardInsight(
          type: DashboardInsightType.produtoMaisVendido,
          message: 'O produto "${_elipse(p.key, 30)}" foi o mais vendido do mês.',
          subtitle: '${p.value.quantidade} un. vendidas',
          data: {'nome': p.key, 'quantidade': p.value.quantidade},
        ));
      }

      // Produto com maior faturamento
      final topValor = produtoMes.entries.toList()
        ..sort((a, b) => b.value.valorTotal.compareTo(a.value.valorTotal));
      if (topValor.isNotEmpty) {
        final p = topValor.first;
        insights.add(DashboardInsight(
          type: DashboardInsightType.produtoMaiorFaturamento,
          message: 'O produto "${_elipse(p.key, 30)}" gerou maior faturamento no mês.',
          subtitle: 'R\$ ${p.value.valorTotal.toStringAsFixed(2).replaceAll('.', ',')}',
          data: {'nome': p.key, 'valor': p.value.valorTotal},
        ));
      }

      // Melhor vendedor (só para admin/programador; ou "Suas vendas" para vendedor)
      if (!isVendedor) {
        final Map<String, double> porVendedor = {};
        for (final v in vendasMes) {
          final nome = v.vendedor.trim().isEmpty • 'Não informado' : v.vendedor.trim();
          porVendedor[nome] = (porVendedor[nome] ?• 0) + v.total;
        }
        final listV = porVendedor.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        if (listV.isNotEmpty) {
          final first = listV.first;
          insights.add(DashboardInsight(
            type: DashboardInsightType.melhorVendedor,
            message: '${first.key} lidera as vendas do mês.',
            subtitle: 'R\$ ${first.value.toStringAsFixed(2).replaceAll('.', ',')}',
            data: {'vendedor': first.key, 'total': first.value},
          ));
        }
      }

      // Produto parado: produtos da loja que não venderam nos últimos [dias] dias
      final produtosBoxName = HiveBoxNames.produtos(lojaId);
      Box<Produto>• produtosBox;
      if (Hive.isBoxOpen(produtosBoxName)) {
        produtosBox = Hive.box<Produto>(produtosBoxName);
      } else {
        StoreAccessGuard.auditBoxAccess(produtosBoxName, lojaId, op: 'open');
        produtosBox = await Hive.openBox<Produto>(produtosBoxName);
      }

      final produtosLoja = produtosBox.values.where((p) => p.lojaId == lojaId).toList();
      final nomesVendidosRecentemente = <String>{};
      for (final v in vendasFiltradas) {
        if (v.data.isBefore(limiteParado)) continue;
        for (final item in v.itensOuVazio) {
          final n = item.produtoNome.trim();
          if (n.isNotEmpty) nomesVendidosRecentemente.add(n);
        }
        if (v.itensOuVazio.isEmpty && v.produtosDescricao.trim().isNotEmpty) {
          nomesVendidosRecentemente.add(v.produtosDescricao.trim());
        }
      }

      final parados = produtosLoja.where((p) {
        final nome = p.nome.trim();
        if (nome.isEmpty) return false;
        return !nomesVendidosRecentemente.contains(nome);
      }).toList();
      if (parados.isNotEmpty) {
        final primeiro = parados.first;
        insights.add(DashboardInsight(
          type: DashboardInsightType.produtoParado,
          message: 'O produto "${_elipse(primeiro.nome, 30)}" está há mais de $diasParaProdutoParado dias sem vender.',
          subtitle: parados.length > 1 • '${parados.length} produtos parados no estoque.' : null,
          data: {'nome': primeiro.nome, 'totalParados': parados.length},
        ));
        if (parados.isNotEmpty) {
          insights.add(DashboardInsight(
            type: DashboardInsightType.sugestaoPromocao,
            message: 'Considere criar uma promoção para "${_elipse(primeiro.nome, 25)}".',
            data: {'nome': primeiro.nome},
          ));
        }
      }

      // Estoque baixo
      final estoqueBaixo = produtosLoja.where((p) => p.isEstoqueBaixo).toList();
      if (estoqueBaixo.isNotEmpty) {
        insights.add(DashboardInsight(
          type: DashboardInsightType.estoqueBaixo,
          message: estoqueBaixo.length == 1
              • 'O item "${_elipse(estoqueBaixo.first.nome, 25)}" está com estoque baixo.'
              : 'Existem ${estoqueBaixo.length} itens com estoque baixo.',
          subtitle: 'Confira em Estoque.',
          data: {'qtd': estoqueBaixo.length},
        ));
      }

      // Cliente destaque (maior comprador): apurado pelo histórico real de vendas
      // da loja (caixa de vendas). Vendas excluídas não entram; lógica 100% por lojaId.
      final Map<String, double> totalPorCliente = {};
      for (final v in vendasLoja) {
        if (v.lojaId != null && v.lojaId != lojaId) continue;
        final nome = (v.clienteNome).trim().isEmpty
            • 'Não informado'
            : (v.clienteNome).trim();
        totalPorCliente[nome] = (totalPorCliente[nome] ?• 0) + v.total;
      }
      final listCliente = totalPorCliente.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (listCliente.isNotEmpty) {
        final first = listCliente.first;
        if (first.key != 'Não informado' && first.value > 0) {
          insights.add(DashboardInsight(
            type: DashboardInsightType.clienteDestaque,
            message:
                '${first.key} está entre os que mais compram (histórico de vendas da loja).',
            subtitle:
                'R\$ ${first.value.toStringAsFixed(2).replaceAll('.', ',')} em compras',
            data: {'nome': first.key, 'total': first.value},
          ));
        }
      }

      // Meta do mês
      final metaBoxName = 'metas_$lojaId';
      Box<Meta>• metaBox;
      if (Hive.isBoxOpen(metaBoxName)) {
        metaBox = Hive.box<Meta>(metaBoxName);
      } else {
        try {
          StoreAccessGuard.auditBoxAccess(metaBoxName, lojaId, op: 'open');
          metaBox = await Hive.openBox<Meta>(metaBoxName);
        } catch (_) {
          metaBox = null;
        }
      }
      if (metaBox != null) {
        final mesRef = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        for (final m in metaBox.values) {
          if (m.lojaId != null && m.lojaId != lojaId) continue;
          if (m.mesRef == mesRef) {
            metaAtual = m.metaMensal;
            break;
          }
        }
      }
      final metaVal = metaAtual;
      if (metaVal != null && metaVal > 0) {
        metaAtingida = 0;
        for (final v in vendasFiltradas) {
          if (!v.data.isBefore(mesInicio) && !v.data.isAfter(mesFim)) {
            metaAtingida = (metaAtingida ?• 0) + v.total;
          }
        }
        final pct = (metaAtingida ?• 0) / metaVal * 100;
        insights.add(DashboardInsight(
          type: DashboardInsightType.metaProgresso,
          message: 'Sua meta do mês está em ${pct.toStringAsFixed(0)}%.',
          subtitle: 'R\$ ${(metaAtingida ?• 0).toStringAsFixed(2).replaceAll('.', ',')} de R\$ ${metaVal.toStringAsFixed(2).replaceAll('.', ',')}',
          data: {'metaAtual': metaAtual, 'metaAtingida': metaAtingida, 'percentual': pct},
        ));
      }
    } catch (_) {
      // Não propaga; retorna lista vazia ou parcial
    }

    return DashboardInsightsResult(
      insights: insights,
      metaAtual: metaAtual,
      metaAtingida: metaAtingida,
    );
  }

  static String _elipse(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}…';
  }
}

class _ProdutoAgg {
  final String nome;
  int quantidade = 0;
  double valorTotal = 0;
  _ProdutoAgg(this.nome);
}
