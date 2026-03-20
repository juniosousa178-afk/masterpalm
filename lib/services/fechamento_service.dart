// lib/services/fechamento_service.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/venda.dart';
import '../models/fechamento_mensal.dart';
import 'fechamento_firestore_service.dart';

class FechamentoService {
  // ----------------- Utils de data -----------------
  static bool _sameMonth(DateTime d, int ano, int mes) =>
      d.year == ano && d.month == mes;

  // ----------------- Parsing de valores -----------------
  static double _parseValor(String s) {
    // Extrai números, aceita vírgula como decimal (pt-BR)
    final numStr = s
        .replaceAll(RegExp(r'[^0-9,.\-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(numStr) ?? 0.0;
  }

  // Lê pagamentos da venda (prioriza campos numéricos; se 0, tenta a string)
  static ({double dinheiro, double pix, double cartao}) _pagamentosDoMes(
      Iterable<Venda> vendas) {
    double dinheiro = 0, pix = 0, cartao = 0;

    for (final v in vendas) {
      double d = (v.pagamentoDinheiro).abs();
      double p = (v.pagamentoPix).abs();
      double c = (v.pagamentoCartao).abs();

      // fallback: tenta inferir do texto formasPagamento
      if ((d + p + c) == 0) {
        final linhas = (v.formasPagamento.isNotEmpty ? v.formasPagamento : '')
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty);
        for (final l in linhas) {
          final low = l.toLowerCase();
          final val = _parseValor(l);
          if (val <= 0) continue;

          if (low.contains('dinheiro')) {
            d += val;
          } else if (low.contains('pix')) {
            p += val;
          } else if (low.contains('cart') ||
              low.contains('cartão') ||
              low.contains('cartao')) {
            c += val;
          }
        }
      }

      dinheiro += d;
      pix += p;
      cartao += c;
    }

    return (dinheiro: dinheiro, pix: pix, cartao: cartao);
  }

  // ----------------- API principal -----------------

  /// Calcula e salva/atualiza o fechamento do mês *para uma loja*.
  static Future<FechamentoMensal> fecharMes({
    required int ano,
    required int mes,
    required String lojaId,
    required Box<Venda> vendasBox,
    required Box<FechamentoMensal> fechamentosBox,
  }) async {
    // 🔥 só vendas da loja + mês informado
    final vendasMes = vendasBox.values.where(
      (v) => v.lojaId == lojaId && _sameMonth(v.data, ano, mes),
    );

    double vendaTotal = 0, custoTotal = 0, taxasTotal = 0;
    for (final v in vendasMes) {
      vendaTotal += v.total;
      custoTotal += v.custoProdutos;
      taxasTotal += v.taxas;
    }
    final lucroTotal = vendaTotal - (custoTotal + taxasTotal);
    final porForma = _pagamentosDoMes(vendasMes);

    // procura existente para o (loja, ano, mes) e reaproveita o mesmo registro
    final existente = fechamentosBox.values.firstWhere(
      (f) => f.lojaId == lojaId && f.ano == ano && f.mes == mes,
      orElse: () => FechamentoMensal(
        lojaId: lojaId,
        ano: ano,
        mes: mes,
        totalDinheiro: 0,
        totalPix: 0,
        totalCartao: 0,
        vendaTotal: 0,
        custoTotal: 0,
        taxasTotal: 0,
        lucroTotal: 0,
        fechadoEm: DateTime.now(),
      ),
    );

    existente
      ..totalDinheiro = porForma.dinheiro
      ..totalPix = porForma.pix
      ..totalCartao = porForma.cartao
      ..vendaTotal = vendaTotal
      ..custoTotal = custoTotal
      ..taxasTotal = taxasTotal
      ..lucroTotal = lucroTotal
      ..fechadoEm = DateTime.now();

    if (existente.isInBox) {
      await existente.save();
    } else {
      await fechamentosBox.add(existente);
    }

    // ✅ SINCRONIZAR com Firestore
    try {
      await FechamentoFirestoreService.syncFechamento(
        existente,
        lojaId: lojaId,
      );
    } catch (e) {
      debugPrint('⚠️ Erro ao sincronizar fechamento com Firestore (type=${e.runtimeType})');
    }

    return existente;
  }

  /// Fecha (ou recalcula) o mês atual para uma loja.
  static Future<FechamentoMensal> fecharMesAtual({
    required String lojaId,
    required Box<Venda> vendasBox,
    required Box<FechamentoMensal> fechamentosBox,
  }) {
    final now = DateTime.now();
    return fecharMes(
      ano: now.year,
      mes: now.month,
      lojaId: lojaId,
      vendasBox: vendasBox,
      fechamentosBox: fechamentosBox,
    );
  }

  /// Recalcula um intervalo de meses (útil para histórico) de uma loja.
  static Future<void> fecharIntervalo({
    required String lojaId,
    required int anoInicio,
    required int mesInicio,
    required int anoFim,
    required int mesFim,
    required Box<Venda> vendasBox,
    required Box<FechamentoMensal> fechamentosBox,
  }) async {
    var a = anoInicio, m = mesInicio;
    while (a < anoFim || (a == anoFim && m <= mesFim)) {
      await fecharMes(
        ano: a,
        mes: m,
        lojaId: lojaId,
        vendasBox: vendasBox,
        fechamentosBox: fechamentosBox,
      );
      // avança mês/ano
      if (m == 12) {
        m = 1;
        a++;
      } else {
        m++;
      }
    }
  }

  /// Retorna um resumo simples (sem salvar) para um mês de uma loja.
  static ({
    double venda,
    double custo,
    double taxas,
    double lucro,
    double dinheiro,
    double pix,
    double cartao
  }) resumoMes({
    required int ano,
    required int mes,
    required String lojaId,
    required Box<Venda> vendasBox,
  }) {
    final vendasMes = vendasBox.values.where(
      (v) => v.lojaId == lojaId && _sameMonth(v.data, ano, mes),
    );

    double venda = 0, custo = 0, taxas = 0;
    for (final v in vendasMes) {
      venda += v.total;
      custo += v.custoProdutos;
      taxas += v.taxas;
    }
    final lucro = venda - (custo + taxas);
    final p = _pagamentosDoMes(vendasMes);

    return (
      venda: venda,
      custo: custo,
      taxas: taxas,
      lucro: lucro,
      dinheiro: p.dinheiro,
      pix: p.pix,
      cartao: p.cartao,
    );
  }
}