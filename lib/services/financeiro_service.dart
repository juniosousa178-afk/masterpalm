// lib/services/financeiro_service.dart
// Cálculos do módulo financeiro — regras alinhadas a:
// - Lucro operacional de vendas (só vendas + taxas/custos; sem lançamentos manuais).
// - Resultado gerencial = lucro op. − (gasto fixo + variável + despesa legada + equipe) + ajustes.
// - Fluxo de caixa = recebimentos (formas) + entradas extras − todas saídas + ajustes.

import 'package:hive/hive.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/lancamento_financeiro.dart';

/// Totais agregados para relatórios / complemento de fechamento.
class ResumoFinanceiroModulo {
  final double totalEntradasExtras;
  final double totalAjustes;
  /// Apenas tipo [FinanceiroTipoLancamento.despesaOperacional] (legado).
  final double totalDespesasOperacionais;
  final double totalGastosFixos;
  final double totalGastosVariaveis;
  final double totalCompraMercadoria;
  final double totalInvestimentos;
  final double totalPagamentosEquipe;
  final double totalRetiradas;
  final int quantidadeLancamentosPagos;

  const ResumoFinanceiroModulo({
    this.totalEntradasExtras = 0,
    this.totalAjustes = 0,
    this.totalDespesasOperacionais = 0,
    this.totalGastosFixos = 0,
    this.totalGastosVariaveis = 0,
    this.totalCompraMercadoria = 0,
    this.totalInvestimentos = 0,
    this.totalPagamentosEquipe = 0,
    this.totalRetiradas = 0,
    this.quantidadeLancamentosPagos = 0,
  });

  /// Soma dos três tipos que compõem “despesas operacionais reais” no resultado gerencial.
  double get totalDespesasResultadoGerencial =>
      totalGastosFixos + totalGastosVariaveis + totalDespesasOperacionais;

  /// Alias semântico: mesmo que [totalDespesasOperacionais] (só legado).
  double get totalDespesasOperacionaisLegado => totalDespesasOperacionais;

  /// Todas as saídas explícitas (inclui compra, investimento, equipe, retirada).
  double get totalSaidasExplicitas =>
      totalDespesasResultadoGerencial +
      totalCompraMercadoria +
      totalInvestimentos +
      totalPagamentosEquipe +
      totalRetiradas;

  /// Despesas que reduzem o **resultado gerencial** (fixo + variável + legado + folha/pró-labore).
  double get despesasParaResultadoGerencial =>
      totalDespesasResultadoGerencial + totalPagamentosEquipe;

  /// Impacto líquido dos lançamentos no **caixa** (visão módulo): entradas − saídas + ajustes.
  double get impactoLiquidoModulo =>
      totalEntradasExtras - totalSaidasExplicitas + totalAjustes;

  /// Legado interno — não usar em UI nova.
  double get impactoLiquidoModuloParaLucro =>
      totalEntradasExtras -
      (totalDespesasResultadoGerencial +
          totalInvestimentos +
          totalPagamentosEquipe) +
      totalAjustes;

  bool get temAlgumDado =>
      quantidadeLancamentosPagos > 0 &&
      (totalEntradasExtras.abs() +
              totalAjustes.abs() +
              totalSaidasExplicitas >
          1e-9);
}

class FinanceiroService {
  FinanceiroService._();

  static bool _noPeriodo(
    LancamentoFinanceiro l,
    DateTime inicio,
    DateTime fim,
  ) {
    if (!FinanceiroStatusLancamento.statusLiquidado(l.status)) return false;
    final d = l.dataEfetivaPagamentoOuLancamento;
    if (d.isBefore(inicio)) return false;
    if (d.isAfter(fim)) return false;
    return true;
  }

  static Iterable<LancamentoFinanceiro> lancamentosPagosNoPeriodo(
    Box<LancamentoFinanceiro> box,
    String lojaId,
    DateTime inicio,
    DateTime fim,
  ) {
    final id = lojaId.trim();
    return box.values.where(
      (l) => l.lojaId == id && _noPeriodo(l, inicio, fim),
    );
  }

  static ResumoFinanceiroModulo resumoPeriodo({
    required Box<LancamentoFinanceiro> box,
    required String lojaId,
    required DateTime inicio,
    required DateTime fim,
  }) {
    double entradas = 0, ajustes = 0;
    double despLegado = 0,
        gFixo = 0,
        gVar = 0,
        compra = 0,
        invest = 0,
        equipe = 0,
        retiradas = 0;
    var qtd = 0;

    for (final l in lancamentosPagosNoPeriodo(box, lojaId, inicio, fim)) {
      qtd++;
      final v = l.valor.abs();
      switch (l.tipo) {
        case FinanceiroTipoLancamento.entradaExtra:
          entradas += l.valor;
          break;
        case FinanceiroTipoLancamento.ajusteFinanceiro:
          ajustes += l.valor;
          break;
        case FinanceiroTipoLancamento.despesaOperacional:
          despLegado += v;
          break;
        case FinanceiroTipoLancamento.gastoFixo:
          gFixo += v;
          break;
        case FinanceiroTipoLancamento.gastoVariavel:
          gVar += v;
          break;
        case FinanceiroTipoLancamento.compraMercadoria:
          compra += v;
          break;
        case FinanceiroTipoLancamento.investimento:
          invest += v;
          break;
        case FinanceiroTipoLancamento.pagamentoFuncionario:
        case FinanceiroTipoLancamento.proLabore:
          equipe += v;
          break;
        case FinanceiroTipoLancamento.retirada:
          retiradas += v;
          break;
        default:
          despLegado += v;
      }
    }

    return ResumoFinanceiroModulo(
      totalEntradasExtras: entradas,
      totalAjustes: ajustes,
      totalDespesasOperacionais: despLegado,
      totalGastosFixos: gFixo,
      totalGastosVariaveis: gVar,
      totalCompraMercadoria: compra,
      totalInvestimentos: invest,
      totalPagamentosEquipe: equipe,
      totalRetiradas: retiradas,
      quantidadeLancamentosPagos: qtd,
    );
  }

  static ResumoFinanceiroModulo resumoMesCalendario({
    required Box<LancamentoFinanceiro> box,
    required String lojaId,
    required int ano,
    required int mes,
  }) {
    final inicio = DateTime(ano, mes, 1);
    final fim = DateTime(ano, mes + 1, 0, 23, 59, 59, 999);
    return resumoPeriodo(
      box: box,
      lojaId: lojaId,
      inicio: inicio,
      fim: fim,
    );
  }

  static double resultadoGerencialComModulo({
    required double lucroOperacionalVendas,
    required ResumoFinanceiroModulo modulo,
  }) {
    return lucroOperacionalVendas -
        modulo.despesasParaResultadoGerencial +
        modulo.totalAjustes;
  }

  static double lucroEstimadoComModulo({
    required double lucroVendasTaxasCustos,
    required ResumoFinanceiroModulo modulo,
  }) {
    return resultadoGerencialComModulo(
      lucroOperacionalVendas: lucroVendasTaxasCustos,
      modulo: modulo,
    );
  }

  static double fluxoCaixaComVendas({
    required double somaFormasPagamentoVendas,
    required ResumoFinanceiroModulo modulo,
  }) {
    return somaFormasPagamentoVendas +
        modulo.totalEntradasExtras -
        modulo.totalSaidasExplicitas +
        modulo.totalAjustes;
  }
}
