import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:excel/excel.dart';
import '../models/venda.dart';
import 'dart:typed_data';

Future<void> exportarParaExcelComDialog(
  BuildContext context,
  List<Venda> vendas,
) async {
  var status = await Permission.storage.request();
  if (!status.isGranted) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permissão negada para salvar o arquivo.')),
    );
    return;
  }

  final excel = Excel.createExcel();
  final sheet = excel['Histórico'];

  sheet.appendRow([
    TextCellValue('Cliente'),
    TextCellValue('Produto'),
    TextCellValue('Tamanho'),
    TextCellValue('Quantidade'),
    TextCellValue('Preço Unitário'),
    TextCellValue('Desconto'),
    TextCellValue('Total'),
    TextCellValue('Forma de Pagamento'),
    TextCellValue('Data'),
  ]);

  for (var venda in vendas) {
    final itens = venda.itensOuVazio;
    if (itens.isNotEmpty) {
      for (var item in itens) {
        final subtotal = item.precoUnitario * item.quantidade;
        final variacao = [item.tamanho, item.cor].where((s) => s.isNotEmpty).join(' / ');
        sheet.appendRow([
          TextCellValue(venda.clienteNome),
          TextCellValue(item.produtoNome),
          TextCellValue(variacao),
          IntCellValue(item.quantidade),
          TextCellValue(item.precoUnitario.toStringAsFixed(2)),
          TextCellValue(venda.desconto.toStringAsFixed(2)),
          TextCellValue(subtotal.toStringAsFixed(2)),
          TextCellValue(venda.formasPagamentoDiscriminado),
          TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(venda.data)),
        ]);
      }
    } else {
      sheet.appendRow([
        TextCellValue(venda.clienteNome),
        TextCellValue(venda.produtosDescricao),
        TextCellValue(venda.tamanho),
        IntCellValue(venda.quantidade),
        TextCellValue(venda.preco.toStringAsFixed(2)),
        TextCellValue(venda.desconto.toStringAsFixed(2)),
        TextCellValue(venda.total.toStringAsFixed(2)),
        TextCellValue(venda.formasPagamentoDiscriminado),
        TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(venda.data)),
      ]);
    }
  }

  final bytes = excel.encode();
  if (bytes == null) return;

  final fileName =
      'historico_clientes_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

  final params = SaveFileDialogParams(
    data: Uint8List.fromList(bytes),
    fileName: fileName,
    mimeTypesFilter: [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ],
  );

  final savedPath = await FlutterFileDialog.saveFile(params: params);

  if (!context.mounted) return;

  if (savedPath != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Arquivo salvo em: $savedPath')));
    await OpenFilex.open(savedPath);
  } else {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Exportação cancelada.')));
  }
}
