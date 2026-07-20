// M3.9 SPRINT4-R2 — meta/comissão pessoal (cálculos puros, sem engine financeiro).

import '../models/gestao_comercial.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'access_scope_service.dart';
import 'venda_metrics_filter.dart';

/// Estoque vendável: soma células com qtd > 0 (variações / grade / simples).
int gestaoEstoqueDisponivelParaVenda(Produto p) {
  return gestaoEstoqueDisponivelRaw(
    quantidade: p.quantidade,
    usaVariacoes: p.usaVariacoes,
    variacoes: p.variacoes,
    estoquePorTamanho: p.estoquePorTamanho,
  );
}

int gestaoEstoqueDisponivelRaw({
  required int quantidade,
  required bool usaVariacoes,
  Map<String, dynamic>? variacoes,
  Map<String, int> estoquePorTamanho = const {},
}) {
  if (usaVariacoes && variacoes != null && variacoes.isNotEmpty) {
    var total = 0;
    for (final mapaTamanho in variacoes.values) {
      if (mapaTamanho is! Map) continue;
      for (final qtd in mapaTamanho.values) {
        final n = _celulaQtd(qtd);
        if (n > 0) total += n;
      }
    }
    return total;
  }
  if (estoquePorTamanho.isNotEmpty) {
    var total = 0;
    for (final qtd in estoquePorTamanho.values) {
      if (qtd > 0) total += qtd;
    }
    return total;
  }
  return quantidade > 0 ? quantidade : 0;
}

int _celulaQtd(dynamic qtd) {
  if (qtd is int) return qtd;
  if (qtd is num) return qtd.toInt();
  if (qtd is Map) {
    final n = qtd['qtd'] ?? qtd['quantidade'] ?? qtd['qty'];
    if (n is num) return n.toInt();
  }
  return int.tryParse(qtd?.toString() ?? '') ?? 0;
}

/// Progresso de meta pessoal (nunca usa meta da loja).
class MetaPessoalProgresso {
  const MetaPessoalProgresso({
    required this.configurada,
    required this.metaMensal,
    required this.metaDiaria,
    required this.metaAnual,
    required this.realizadoMensal,
    required this.qtdVendasMensal,
    required this.mensagem,
  });

  final bool configurada;
  final double metaMensal;
  final double metaDiaria;
  final double metaAnual;
  final double realizadoMensal;
  final int qtdVendasMensal;
  final String mensagem;

  /// null se meta não configurada (não mostrar 0% falso).
  double? get percentualMensal {
    if (!configurada || metaMensal <= 0) return null;
    return (realizadoMensal / metaMensal) * 100;
  }

  static MetaPessoalProgresso naoConfigurada() => const MetaPessoalProgresso(
        configurada: false,
        metaMensal: 0,
        metaDiaria: 0,
        metaAnual: 0,
        realizadoMensal: 0,
        qtdVendasMensal: 0,
        mensagem: 'Meta ainda não configurada pelo administrador.',
      );
}

MetaPessoalProgresso calcularMetaPessoal({
  required GestaoVendedorConfig config,
  required AccessScopeIdentity identity,
  required Iterable<Venda> vendas,
  required String lojaId,
  DateTime? agora,
  Set<String> tombstonesExclusao = const {},
}) {
  final now = agora ?? DateTime.now();
  final metaM = config.metaMensal;
  final metaD = config.metaDiaria;
  final metaA = config.metaAnual;
  if (metaM <= 0 && metaD <= 0 && metaA <= 0) {
    return MetaPessoalProgresso.naoConfigurada();
  }

  final mesInicio = DateTime(now.year, now.month, 1);
  final mesFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  var realizado = 0.0;
  var qtd = 0;
  for (final v in vendas) {
    if (lojaId.isNotEmpty && v.lojaId != null && v.lojaId != lojaId) continue;
    if (!incluirVendaEmMetricas(v, tombstonesExclusao: tombstonesExclusao)) {
      continue;
    }
    if (!AccessScopeService.sellerOwnsSale(v, identity)) continue;
    if (v.data.isBefore(mesInicio) || v.data.isAfter(mesFim)) continue;
    realizado += v.total;
    qtd++;
  }

  return MetaPessoalProgresso(
    configurada: true,
    metaMensal: metaM,
    metaDiaria: metaD,
    metaAnual: metaA,
    realizadoMensal: realizado,
    qtdVendasMensal: qtd,
    mensagem: metaM > 0 ? 'Meta mensal ativa' : 'Meta parcial configurada',
  );
}

/// Resultado de comissão pessoal (base = líquido da venda = `venda.total`).
class ComissaoPessoalResultado {
  const ComissaoPessoalResultado({
    required this.acumulada,
    required this.pendente,
    required this.paga,
    required this.regraAplicada,
    required this.faixaAtingidaLabel,
    required this.qtdVendasBase,
  });

  final double acumulada;
  final double pendente;
  final double paga;
  final String regraAplicada;
  final String faixaAtingidaLabel;
  final int qtdVendasBase;
}

/// Comissão só sobre vendas próprias elegíveis.
ComissaoPessoalResultado calcularComissaoPessoal({
  required GestaoVendedorConfig config,
  required AccessScopeIdentity identity,
  required Iterable<Venda> vendas,
  required String lojaId,
  DateTime? agora,
  double comissaoJaPaga = 0,
  Set<String> tombstonesExclusao = const {},
}) {
  final now = agora ?? DateTime.now();
  final mesInicio = DateTime(now.year, now.month, 1);
  final mesFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

  final proprias = <Venda>[];
  var faturamento = 0.0;
  for (final v in vendas) {
    if (lojaId.isNotEmpty && v.lojaId != null && v.lojaId != lojaId) continue;
    if (!incluirVendaEmMetricas(v, tombstonesExclusao: tombstonesExclusao)) {
      continue;
    }
    if (!AccessScopeService.sellerOwnsSale(v, identity)) continue;
    if (v.data.isBefore(mesInicio) || v.data.isAfter(mesFim)) continue;
    proprias.add(v);
    faturamento += v.total;
  }

  double acumulada = 0;
  var regra = 'Sem regra';
  var faixaLabel = '—';

  switch (config.comissaoTipo) {
    case ComissaoTipo.percentual:
      final pct = config.comissaoPercentual ?? 0;
      acumulada = faturamento * (pct / 100);
      regra = 'Percentual ${pct.toStringAsFixed(1)}% sobre líquido próprio';
    case ComissaoTipo.valorFixo:
      final fixo = config.comissaoValorFixo ?? 0;
      acumulada = fixo * proprias.length;
      regra = 'Valor fixo R\$ ${fixo.toStringAsFixed(2)} por venda própria';
    case ComissaoTipo.escalonada:
      final faixas = [...config.comissaoFaixas]
        ..sort((a, b) => a.de.compareTo(b.de));
      var pct = 0.0;
      for (final f in faixas) {
        if (faturamento >= f.de && (f.ate <= 0 || faturamento <= f.ate)) {
          pct = f.percentual;
          faixaLabel =
              'R\$ ${f.de.toStringAsFixed(0)}–${f.ate <= 0 ? '∞' : f.ate.toStringAsFixed(0)} → ${f.percentual}%';
          break;
        }
      }
      if (pct == 0 && faixas.isNotEmpty) {
        for (final f in faixas.reversed) {
          if (faturamento >= f.de) {
            pct = f.percentual;
            faixaLabel = 'R\$ ${f.de.toStringAsFixed(0)}+ → ${f.percentual}%';
            break;
          }
        }
      }
      acumulada = faturamento * (pct / 100);
      regra = 'Escalonada sobre líquido próprio';
  }

  final paga = comissaoJaPaga.clamp(0.0, acumulada);
  final pendente = (acumulada - paga).clamp(0.0, acumulada);

  return ComissaoPessoalResultado(
    acumulada: acumulada,
    pendente: pendente,
    paga: paga,
    regraAplicada: regra,
    faixaAtingidaLabel: faixaLabel,
    qtdVendasBase: proprias.length,
  );
}
