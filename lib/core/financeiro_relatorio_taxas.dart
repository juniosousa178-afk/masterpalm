// lib/core/financeiro_relatorio_taxas.dart
// Cálculo unificado de "taxas de relatório" (Relatório Financeiro, Relatórios+Metas, Fechamento).
//
// Regra: % de cartão (Loja Config) incide só sobre o valor pago em cartão; MEI e custos fixos
// continuam sobre o total da venda; embalagem por quantidade de itens no ramo estimado.
//
// Papel em relação ao módulo financeiro (lançamentos reais): estas taxas permanecem o fallback
// principal sobre vendas quando não há substituição por motor alternativo; lançamentos reais
// entram como camada complementar na UI — evitar dupla contagem semântica (mesmo gasto em % e
// em lançamento). Meses passados com [FechamentoMensal] salvo não são recalculados em
// [FechamentoService.fecharMes] (snapshot congelado).

import 'package:hive/hive.dart';

import '../models/venda.dart';
import 'hive_box_names.dart';

/// Parâmetros de taxas lidos de `relatorio_financeiro` (draft_config / config).
class RelatorioTaxasConfig {
  final double taxaCartaoPercent;
  final double taxaMEIPercent;
  final double custosFixosPercent;
  final double custoEmbalagemUnit;

  const RelatorioTaxasConfig({
    this.taxaCartaoPercent = 5.0,
    this.taxaMEIPercent = 3.5,
    this.custosFixosPercent = 10.0,
    this.custoEmbalagemUnit = 3.0,
  });

  static const RelatorioTaxasConfig defaults = RelatorioTaxasConfig();

  static Future<RelatorioTaxasConfig> loadForLoja(String lojaId) async {
    if (lojaId.trim().isEmpty) return defaults;
    try {
      final configBox = await Hive.openBox(HiveBoxNames.relatorioFinanceiro(lojaId));
      final config = configBox.get('draft_config') ?? configBox.get('config');
      if (config is! Map) return defaults;
      final taxas = config['taxas'];
      if (taxas is! Map) return defaults;
      return RelatorioTaxasConfig(
        taxaCartaoPercent: _toDouble(taxas['cartao'], defaults.taxaCartaoPercent),
        taxaMEIPercent: _toDouble(taxas['mei'], defaults.taxaMEIPercent),
        custosFixosPercent: _toDouble(taxas['custosFixos'], defaults.custosFixosPercent),
        custoEmbalagemUnit: _toDouble(taxas['embalagem'], defaults.custoEmbalagemUnit),
      );
    } catch (_) {
      return defaults;
    }
  }

  static double _toDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }
}

abstract final class FinanceiroRelatorioTaxas {
  /// Taxa operacional usada em relatório/fechamento (mesmo conceito em todo o app).
  /// Alias semântico de [taxasParaVenda] — mantido para leitura explícita no código.
  static double taxaOperacionalParaVenda(Venda v, RelatorioTaxasConfig cfg) =>
      taxasParaVenda(v, cfg);

  /// Lucro operacional da venda: `total − custoProdutos − taxa operacional`.
  /// Base: [v.total] (como fechamento/relatório), não `recebidoTotal`.
  /// Taxa: [taxasParaVenda] — se `v.taxas > 0` usa gravado; se zero, estima pela [cfg].
  static double lucroOperacionalVenda(Venda v, RelatorioTaxasConfig cfg) {
    return v.total - v.custoProdutos - taxasParaVenda(v, cfg);
  }

  /// Valor discriminado por forma (campos da venda ou parsing de `formasPagamento`).
  static double valorPorForma(Venda v, String forma) {
    if (forma == 'dinheiro') {
      if (v.pagamentoDinheiro > 0) return v.pagamentoDinheiro;
    } else if (forma == 'pix') {
      if (v.pagamentoPix > 0) return v.pagamentoPix;
    } else if (forma == 'cartao') {
      if (v.pagamentoCartao > 0) return v.pagamentoCartao;
    }
    final soma = v.pagamentoDinheiro + v.pagamentoPix + v.pagamentoCartao;
    if (soma > 0) return 0;
    final linhas = (v.formasPagamento.isNotEmpty ? v.formasPagamento : '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty);
    for (final l in linhas) {
      final low = l.toLowerCase();
      final numStr = l
          .replaceAll(RegExp(r'[^0-9,.\-]'), '')
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final val = double.tryParse(numStr) ?? 0.0;
      if (val <= 0) continue;
      if (forma == 'dinheiro' && low.contains('dinheiro')) return val;
      if (forma == 'pix' && low.contains('pix')) return val;
      if (forma == 'cartao' && (low.contains('cart') || low.contains('cartão'))) {
        return val;
      }
    }
    return 0;
  }

  /// Taxas agregadas para uma venda (mesma regra em todas as telas / fechamento).
  static double taxasParaVenda(Venda v, RelatorioTaxasConfig cfg) {
    if (v.taxas > 0) {
      return v.taxas;
    }
    final valorCartao = valorPorForma(v, 'cartao');
    double taxas = 0;
    if (valorCartao > 0) {
      taxas += valorCartao * (cfg.taxaCartaoPercent / 100);
    }
    taxas += v.total * (cfg.taxaMEIPercent / 100);
    taxas += v.total * (cfg.custosFixosPercent / 100);
    final qtdItens = v.itens?.length ?? 1;
    taxas += qtdItens * cfg.custoEmbalagemUnit;
    return taxas;
  }
}

/// Lucro operacional alinhado a relatório/fechamento (requer [RelatorioTaxasConfig] da loja).
extension VendaLucroOperacionalFinanceiro on Venda {
  double lucroOperacional(RelatorioTaxasConfig cfg) =>
      FinanceiroRelatorioTaxas.lucroOperacionalVenda(this, cfg);
}
