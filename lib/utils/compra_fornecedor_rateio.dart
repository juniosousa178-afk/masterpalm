// Rateio proporcional de frete, desconto e outras despesas sobre o subtotal base dos itens.
//
// Arredondamento: valores monetários em 2 casas (centavos) por linha, exceto o último item,
// que recebe o restante de frete/desconto/outras para que a soma bata exatamente com os
// totais do cabeçalho. O subtotalFinal do último item é o valor total financeiro alvo menos
// a soma dos subtotais finais já arredondados das linhas anteriores (elimina drift de centavos).
// custoUnitarioFinal = subtotalFinal / quantidade (precisão completa em double; exibição pode usar 4+ casas).

import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_item.dart';

class CompraFornecedorRateio {
  CompraFornecedorRateio._();

  static double _r2(double x) => (x * 100).round() / 100.0;

  /// Recalcula [subtotalBase], participação, rateios e custos finais em cada item.
  /// Não altera [custoUnitario] (custo base digitado). Atualiza [atualizadoEm] da compra.
  static CompraFornecedor aplicar(CompraFornecedor c) {
    final itens = c.itensOuVazio.toList();
    if (itens.isEmpty) {
      return c.copyWith(atualizadoEm: DateTime.now());
    }

    final frete = c.frete;
    final desconto = c.desconto;
    final outras = c.outrasDespesas;

    final bases = itens
        .map((it) => _r2(it.quantidade.clamp(0, 1 << 30) * it.custoUnitario))
        .toList(growable: false);
    var subtotalItensBase = 0.0;
    for (final b in bases) {
      subtotalItensBase += b;
    }
    subtotalItensBase = _r2(subtotalItensBase);

    final valorTotalAlvo =
        _r2((subtotalItensBase + frete + outras - desconto).clamp(0.0, 1e15));

    if (subtotalItensBase <= 1e-9) {
      return _rateioBaseZero(
        c: c,
        itens: itens,
        frete: frete,
        desconto: desconto,
        outras: outras,
        valorTotalAlvo: valorTotalAlvo,
      );
    }

    double sumFrete = 0, sumDesc = 0, sumOut = 0, sumFinalPrev = 0;
    final novos = <CompraFornecedorItem>[];

    for (var i = 0; i < itens.length; i++) {
      final it = itens[i];
      final sb = bases[i];
      final isLast = i == itens.length - 1;
      final pct = sb / subtotalItensBase;

      final double fr;
      final double dr;
      final double ort;
      if (isLast) {
        fr = _r2(frete - sumFrete);
        dr = _r2(desconto - sumDesc);
        ort = _r2(outras - sumOut);
      } else {
        fr = _r2(frete * pct);
        dr = _r2(desconto * pct);
        ort = _r2(outras * pct);
        sumFrete += fr;
        sumDesc += dr;
        sumOut += ort;
      }

      final double subtotalFinal;
      if (isLast) {
        subtotalFinal = _r2(valorTotalAlvo - sumFinalPrev);
      } else {
        final sf = _r2(sb + fr + ort - dr);
        sumFinalPrev += sf;
        subtotalFinal = sf;
      }

      final q = it.quantidade.clamp(1, 1 << 30);
      final cuf = subtotalFinal / q;

      novos.add(
        it.copyWith(
          subtotalBase: sb,
          percentualParticipacao: pct,
          freteRateado: fr,
          descontoRateado: dr,
          outrasDespesasRateadas: ort,
          custoUnitarioFinal: cuf,
          subtotalFinal: subtotalFinal,
        ),
      );
    }

    return c.copyWith(itens: novos, atualizadoEm: DateTime.now());
  }

  /// Quando não há base (todos os subtotais base zero), rateia custos extras igualmente entre linhas.
  static CompraFornecedor _rateioBaseZero({
    required CompraFornecedor c,
    required List<CompraFornecedorItem> itens,
    required double frete,
    required double desconto,
    required double outras,
    required double valorTotalAlvo,
  }) {
    final n = itens.length;
    if (n == 0) return c;

    double sumFrete = 0, sumDesc = 0, sumOut = 0, sumFinalPrev = 0;
    final novos = <CompraFornecedorItem>[];

    for (var i = 0; i < n; i++) {
      final it = itens[i];
      final isLast = i == n - 1;

      final double fr;
      final double dr;
      final double ort;
      if (isLast) {
        fr = _r2(frete - sumFrete);
        dr = _r2(desconto - sumDesc);
        ort = _r2(outras - sumOut);
      } else {
        fr = _r2(frete / n);
        dr = _r2(desconto / n);
        ort = _r2(outras / n);
        sumFrete += fr;
        sumDesc += dr;
        sumOut += ort;
      }

      const sb = 0.0;
      final pct = 1.0 / n;

      final double subtotalFinal;
      if (isLast) {
        subtotalFinal = _r2(valorTotalAlvo - sumFinalPrev);
      } else {
        final sf = _r2(sb + fr + ort - dr);
        sumFinalPrev += sf;
        subtotalFinal = sf;
      }

      final q = it.quantidade.clamp(1, 1 << 30);
      final cuf = subtotalFinal / q;

      novos.add(
        it.copyWith(
          subtotalBase: sb,
          percentualParticipacao: pct,
          freteRateado: fr,
          descontoRateado: dr,
          outrasDespesasRateadas: ort,
          custoUnitarioFinal: cuf,
          subtotalFinal: subtotalFinal,
        ),
      );
    }

    return c.copyWith(itens: novos, atualizadoEm: DateTime.now());
  }
}
