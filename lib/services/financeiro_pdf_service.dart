// Relatórios financeiros em PDF — apenas agrega dados já calculados na UI (sem alterar fórmulas).

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../financeiro/financeiro_constants.dart';
import '../models/lancamento_financeiro.dart';
import '../models/venda.dart';
import 'financeiro_service.dart';

/// Tipos de relatório disponíveis para exportação em PDF.
enum FinanceiroPdfTipo {
  resumoFinanceiro,
  vendasPorPeriodo,
  lucroOperacional,
  gastosDespesas,
  compraMercadoria,
  contasReceber,
  fluxoCaixa,
  dreGerencial,
}

class FinanceiroPdfVendaLinha {
  const FinanceiroPdfVendaLinha({
    required this.data,
    required this.descricao,
    required this.total,
  });

  final DateTime data;
  final String descricao;
  final double total;
}

/// Dados pré-calculados pelo ecrã (mesmas regras que a UI).
class FinanceiroPdfPayload {
  const FinanceiroPdfPayload({
    required this.nomeLoja,
    required this.lojaId,
    required this.periodoInicio,
    required this.periodoFim,
    required this.modulo,
    required this.totalVendido,
    required this.custoProdutos,
    required this.taxas,
    required this.lucroOperacionalVendas,
    required this.totalDinheiro,
    required this.totalPix,
    required this.totalCartao,
    required this.totalContasReceberAberto,
    this.lancamentosDetalhe = const [],
    this.vendasDetalhe = const [],
  });

  final String nomeLoja;
  final String lojaId;
  final DateTime periodoInicio;
  final DateTime periodoFim;
  final ResumoFinanceiroModulo modulo;
  final double totalVendido;
  final double custoProdutos;
  final double taxas;
  final double lucroOperacionalVendas;
  final double totalDinheiro;
  final double totalPix;
  final double totalCartao;
  final double totalContasReceberAberto;
  final List<LancamentoFinanceiro> lancamentosDetalhe;
  final List<FinanceiroPdfVendaLinha> vendasDetalhe;
}

class FinanceiroPdfService {
  FinanceiroPdfService._();

  /// Rótulo para menus da UI.
  static String nomeTipo(FinanceiroPdfTipo tipo) => _titulo(tipo);

  static String _titulo(FinanceiroPdfTipo tipo) {
    switch (tipo) {
      case FinanceiroPdfTipo.resumoFinanceiro:
        return 'Resumo financeiro';
      case FinanceiroPdfTipo.vendasPorPeriodo:
        return 'Vendas por período';
      case FinanceiroPdfTipo.lucroOperacional:
        return 'Lucro operacional';
      case FinanceiroPdfTipo.gastosDespesas:
        return 'Gastos e despesas';
      case FinanceiroPdfTipo.compraMercadoria:
        return 'Compra de mercadoria';
      case FinanceiroPdfTipo.contasReceber:
        return 'Contas a receber';
      case FinanceiroPdfTipo.fluxoCaixa:
        return 'Fluxo de caixa';
      case FinanceiroPdfTipo.dreGerencial:
        return 'DRE gerencial';
    }
  }

  static String _fmtValor(NumberFormat moeda, double v) => moeda.format(v);

  static String _periodoTexto(FinanceiroPdfPayload p) {
    final i = DateFormat('dd/MM/yyyy').format(p.periodoInicio);
    final f = DateFormat('dd/MM/yyyy').format(p.periodoFim);
    return '$i a $f';
  }

  static Future<void> gerar({
    required FinanceiroPdfTipo tipo,
    required FinanceiroPdfPayload payload,
  }) async {
    final p = payload;
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final geradoEm =
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now().toLocal());
    final somaFormas = p.totalDinheiro + p.totalPix + p.totalCartao;
    final entrouSimples = somaFormas + p.modulo.totalEntradasExtras;
    final resultadoGerencial = FinanceiroService.resultadoGerencialComModulo(
      lucroOperacionalVendas: p.lucroOperacionalVendas,
      modulo: p.modulo,
    );
    final fluxo = FinanceiroService.fluxoCaixaComVendas(
      somaFormasPagamentoVendas: somaFormas,
      modulo: p.modulo,
    );

    final pdf = pw.Document();

    Iterable<LancamentoFinanceiro> lancFiltrados() sync* {
      for (final l in p.lancamentosDetalhe) {
        switch (tipo) {
          case FinanceiroPdfTipo.gastosDespesas:
            if (l.tipo == FinanceiroTipoLancamento.despesaOperacional ||
                l.tipo == FinanceiroTipoLancamento.gastoFixo ||
                l.tipo == FinanceiroTipoLancamento.gastoVariavel ||
                l.tipo == FinanceiroTipoLancamento.pagamentoFuncionario ||
                l.tipo == FinanceiroTipoLancamento.proLabore) {
              yield l;
            }
            break;
          case FinanceiroPdfTipo.compraMercadoria:
            if (l.tipo == FinanceiroTipoLancamento.compraMercadoria) {
              yield l;
            }
            break;
          default:
            yield l;
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) {
          final linhas = <pw.Widget>[
            pw.Text(
              p.nomeLoja.isEmpty ? 'Loja' : p.nomeLoja,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _titulo(tipo),
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Período: ${_periodoTexto(p)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'Gerado em: $geradoEm',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 16),
          ];

          void addCard(String rotulo, String valor) {
            linhas.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(rotulo, style: const pw.TextStyle(fontSize: 10))),
                    pw.Text(valor,
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            );
          }

          switch (tipo) {
            case FinanceiroPdfTipo.resumoFinanceiro:
              addCard('Quanto entrou (vendas + entradas extras)',
                  _fmtValor(moeda, entrouSimples));
              addCard('Quanto saiu (lançamentos pagos)',
                  _fmtValor(moeda, p.modulo.totalSaidasExplicitas));
              addCard('Quanto sobrou (fluxo de caixa)',
                  _fmtValor(moeda, fluxo));
              addCard('Lucro das vendas (operacional)',
                  _fmtValor(moeda, p.lucroOperacionalVendas));
              addCard('Gastos com mercadoria (módulo)',
                  _fmtValor(moeda, p.modulo.totalCompraMercadoria));
              addCard('Despesas (fixas + variáveis + legado + equipe)',
                  _fmtValor(moeda, p.modulo.despesasParaResultadoGerencial));
              addCard('Contas a receber (pendentes, saldo atual)',
                  _fmtValor(moeda, p.totalContasReceberAberto));
              addCard('Taxas pagas (período)',
                  _fmtValor(moeda, p.taxas));
              break;
            case FinanceiroPdfTipo.vendasPorPeriodo:
              addCard('Total vendido', _fmtValor(moeda, p.totalVendido));
              addCard('Quantidade de linhas no detalhe',
                  '${p.vendasDetalhe.length}');
              break;
            case FinanceiroPdfTipo.lucroOperacional:
              addCard('Vendas', _fmtValor(moeda, p.totalVendido));
              addCard('Custo produtos (CMV)', _fmtValor(moeda, p.custoProdutos));
              addCard('Taxas', _fmtValor(moeda, p.taxas));
              addCard('Lucro operacional de vendas',
                  _fmtValor(moeda, p.lucroOperacionalVendas));
              break;
            case FinanceiroPdfTipo.gastosDespesas:
              addCard('Gastos fixos', _fmtValor(moeda, p.modulo.totalGastosFixos));
              addCard('Gastos variáveis',
                  _fmtValor(moeda, p.modulo.totalGastosVariaveis));
              addCard('Despesas (legado)',
                  _fmtValor(moeda, p.modulo.totalDespesasOperacionais));
              addCard('Equipe / pró-labore',
                  _fmtValor(moeda, p.modulo.totalPagamentosEquipe));
              addCard(
                  'Total despesas (resultado gerencial)',
                  _fmtValor(
                      moeda, p.modulo.despesasParaResultadoGerencial));
              break;
            case FinanceiroPdfTipo.compraMercadoria:
              addCard('Total compra mercadoria',
                  _fmtValor(moeda, p.modulo.totalCompraMercadoria));
              break;
            case FinanceiroPdfTipo.contasReceber:
              addCard('Saldo pendente (contas a receber)',
                  _fmtValor(moeda, p.totalContasReceberAberto));
              linhas.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    'O detalhamento por cliente fica no app em Contas a receber.',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
              );
              break;
            case FinanceiroPdfTipo.fluxoCaixa:
              addCard('Dinheiro + Pix + Cartão (vendas)',
                  _fmtValor(moeda, somaFormas));
              addCard('Entradas extras', _fmtValor(moeda, p.modulo.totalEntradasExtras));
              addCard('Saídas (todas)', _fmtValor(moeda, p.modulo.totalSaidasExplicitas));
              addCard('Ajustes', _fmtValor(moeda, p.modulo.totalAjustes));
              addCard('Fluxo de caixa', _fmtValor(moeda, fluxo));
              break;
            case FinanceiroPdfTipo.dreGerencial:
              addCard('Lucro operacional de vendas',
                  _fmtValor(moeda, p.lucroOperacionalVendas));
              addCard('Despesas (resultado gerencial)',
                  _fmtValor(moeda, p.modulo.despesasParaResultadoGerencial));
              addCard('Ajustes', _fmtValor(moeda, p.modulo.totalAjustes));
              addCard('Resultado gerencial',
                  _fmtValor(moeda, resultadoGerencial));
              addCard('Fluxo de caixa (referência)',
                  _fmtValor(moeda, fluxo));
              break;
          }

          if (tipo == FinanceiroPdfTipo.vendasPorPeriodo &&
              p.vendasDetalhe.isNotEmpty) {
            linhas.add(pw.SizedBox(height: 12));
            linhas.add(pw.Text('Detalhe de vendas',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)));
            linhas.add(pw.SizedBox(height: 6));
            linhas.add(
              pw.Table.fromTextArray(
                headers: const ['Data', 'Descrição', 'Total'],
                cellAlignment: pw.Alignment.centerLeft,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                data: p.vendasDetalhe
                    .map(
                      (v) => [
                        DateFormat('dd/MM/yy').format(v.data),
                        v.descricao,
                        _fmtValor(moeda, v.total),
                      ],
                    )
                    .toList(),
              ),
            );
            final sumV =
                p.vendasDetalhe.fold<double>(0, (s, v) => s + v.total);
            linhas.add(pw.SizedBox(height: 8));
            linhas.add(pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Soma do detalhe: ${_fmtValor(moeda, sumV)}',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ));
          }

          final lancList = lancFiltrados().toList();
          if (lancList.isNotEmpty &&
              (tipo == FinanceiroPdfTipo.gastosDespesas ||
                  tipo == FinanceiroPdfTipo.compraMercadoria ||
                  tipo == FinanceiroPdfTipo.resumoFinanceiro ||
                  tipo == FinanceiroPdfTipo.fluxoCaixa ||
                  tipo == FinanceiroPdfTipo.dreGerencial)) {
            if (tipo != FinanceiroPdfTipo.resumoFinanceiro) {
              linhas.add(pw.SizedBox(height: 12));
              linhas.add(pw.Text('Lançamentos (amostra)',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)));
              linhas.add(pw.SizedBox(height: 6));
            } else {
              linhas.add(pw.SizedBox(height: 12));
              linhas.add(pw.Text('Lançamentos do período',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)));
              linhas.add(pw.SizedBox(height: 6));
            }
            final amostra = lancList.length > 80 ? lancList.sublist(0, 80) : lancList;
            linhas.add(
              pw.Table.fromTextArray(
                headers: const ['Data', 'Tipo', 'Descrição', 'Valor'],
                cellAlignment: pw.Alignment.centerLeft,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                data: amostra
                    .map(
                      (l) => [
                        DateFormat('dd/MM/yy')
                            .format(l.dataEfetivaPagamentoOuLancamento),
                        FinanceiroTipoLancamento.legivel(l.tipo),
                        l.descricao.isEmpty ? '—' : l.descricao,
                        _fmtValor(moeda, l.valor),
                      ],
                    )
                    .toList(),
              ),
            );
            if (lancList.length > 80) {
              linhas.add(pw.SizedBox(height: 6));
              linhas.add(pw.Text(
                'Mostrando 80 de ${lancList.length} lançamentos.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ));
            }
          }

          linhas.add(pw.SizedBox(height: 16));
          linhas.add(pw.Text(
            'Totais conferem com os indicadores do app para o mesmo período e filtros.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ));

          return linhas;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  /// Monta linhas de vendas a partir de modelos [Venda] (sem recalcular totais).
  static List<FinanceiroPdfVendaLinha> vendasParaPdf(Iterable<Venda> vendas) {
    final out = <FinanceiroPdfVendaLinha>[];
    for (final v in vendas) {
      final nome = v.clienteNome.trim().isEmpty ? 'Venda' : v.clienteNome.trim();
      out.add(FinanceiroPdfVendaLinha(
        data: v.data,
        descricao: nome,
        total: v.total,
      ));
    }
    return out;
  }
}
