// lib/services/pedido_venda_pdf_service.dart
// Gera PDF de pedido de venda com itens resolvidos (Hive ou fallback da descrição).

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import 'migracao_vendas_itens_service.dart';

class PedidoVendaPdfService {
  /// Monta e abre o diálogo de impressão/PDF do pedido.
  static Future<void> imprimir({
    required Venda venda,
    required String lojaId,
    Cliente? cliente,
  }) async {
    final itens = MigracaoVendasItensService.resolverItens(venda);
    final subtotalReal = itens.isNotEmpty
        ? itens.fold<double>(0.0, (s, i) => s + i.precoUnitario * i.quantidade)
        : venda.preco;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'PEDIDO DE VENDA',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Loja: $lojaId',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Data: ${DateFormat('dd/MM/yyyy – HH:mm').format(venda.data)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Divider(thickness: 2),
          pw.SizedBox(height: 16),
          pw.Text(
            'DADOS DO CLIENTE',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Nome: ${venda.clienteNome}'),
          if (cliente != null) ...[
            if (cliente.telefone.isNotEmpty)
              pw.Text('Telefone: ${cliente.telefone}'),
            if ((cliente.email ?? '').isNotEmpty)
              pw.Text('Email: ${cliente.email}'),
            if ((cliente.endereco ?? '').isNotEmpty)
              pw.Text('Endereço: ${cliente.endereco}'),
            if (cliente.cep.isNotEmpty) pw.Text('CEP: ${cliente.cep}'),
            if (cliente.cidade.isNotEmpty)
              pw.Text('Cidade: ${cliente.cidade}'),
          ],
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 16),
          pw.Text(
            'PRODUTOS',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.4),
              1: const pw.FlexColumnWidth(0.9),
              2: const pw.FlexColumnWidth(0.9),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(0.6),
              5: const pw.FlexColumnWidth(1.0),
              6: const pw.FlexColumnWidth(1.0),
            },
            children: [
              _headerRow(),
              ..._linhasItens(itens, venda),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 16),
          pw.Text(
            'RESUMO FINANCEIRO',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Subtotal:'),
              pw.Text('R\$ ${subtotalReal.toStringAsFixed(2)}'),
            ],
          ),
          if (venda.frete > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Frete:'),
                pw.Text('R\$ ${venda.frete.toStringAsFixed(2)}'),
              ],
            ),
          if (venda.desconto > 0)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Desconto:'),
                pw.Text(
                  '-R\$ ${(subtotalReal * venda.desconto / 100).toStringAsFixed(2)} (${venda.desconto.toStringAsFixed(1)}%)',
                ),
              ],
            ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL:',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'R\$ ${venda.total.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.SizedBox(height: 16),
          pw.Text(
            'PAGAMENTO E ENTREGA',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Forma de Pagamento: ${venda.formasPagamentoDiscriminado}',
          ),
          if (venda.frete > 0)
            pw.Text(
              'Tipo de Entrega: Com frete (R\$ ${venda.frete.toStringAsFixed(2)})',
            )
          else
            pw.Text('Tipo de Entrega: Retirada na loja'),
          pw.SizedBox(height: 8),
          pw.Text('Vendedor: ${venda.vendedor}'),
          if (venda.observacao.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 16),
            pw.Text(
              'OBSERVAÇÕES',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(venda.observacao),
          ],
          pw.SizedBox(height: 24),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              'Documento gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'Pedido_${venda.clienteNome}_${DateFormat('ddMMyyyy_HHmm').format(venda.data)}.pdf',
    );
  }

  static pw.TableRow _headerRow() {
    pw.Widget cell(String label) => pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        );
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        cell('Produto'),
        cell('Tamanho'),
        cell('Cor'),
        cell('Variação'),
        cell('Qtd'),
        cell('Valor Unit.'),
        cell('Total'),
      ],
    );
  }

  static List<pw.TableRow> _linhasItens(List<VendaItem> itens, Venda venda) {
    if (itens.isNotEmpty) {
      return itens.map((item) {
        final totalItem = item.precoUnitario * item.quantidade;
        return pw.TableRow(
          children: [
            _pad(item.produtoNome),
            _pad(item.tamanho.isNotEmpty ? item.tamanho : '-'),
            _pad(item.cor.isNotEmpty ? item.cor : '-'),
            _pad(
              item.variacaoExtraResumo.isNotEmpty
                  ? item.variacaoExtraResumo
                  : '-',
            ),
            _pad(item.quantidade.toString()),
            _pad('R\$ ${item.precoUnitario.toStringAsFixed(2)}'),
            _pad('R\$ ${totalItem.toStringAsFixed(2)}'),
          ],
        );
      }).toList();
    }

    final desc = venda.produtosDescricao.trim();
    return [
      pw.TableRow(
        children: [
          _pad(desc.isNotEmpty ? desc : '—'),
          _pad('-'),
          _pad('-'),
          _pad('-'),
          _pad(venda.quantidade.toString()),
          _pad('R\$ ${venda.preco.toStringAsFixed(2)}'),
          _pad('R\$ ${venda.total.toStringAsFixed(2)}'),
        ],
      ),
    ];
  }

  static pw.Widget _pad(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text),
      );
}
