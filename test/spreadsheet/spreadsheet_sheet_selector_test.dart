import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_entity_aliases.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_sheet_selector.dart';

xls.Excel _buildMultiSheetWorkbook() {
  final excel = xls.Excel.createExcel();
  final instr = excel['Instrucoes'];
  instr.appendRow([
    xls.TextCellValue('Leia antes de importar'),
    xls.TextCellValue('Nome'),
    xls.TextCellValue('Preco'),
  ]);
  instr.appendRow([
    xls.TextCellValue('Preencha os dados na aba Dados'),
    xls.TextCellValue(''),
    xls.TextCellValue(''),
  ]);

  final dados = excel['Dados'];
  dados.appendRow([
    xls.TextCellValue('Nome'),
    xls.TextCellValue('Preco'),
    xls.TextCellValue('Quantidade'),
  ]);
  dados.appendRow([
    xls.TextCellValue('Produto A'),
    xls.TextCellValue('15,50'),
    xls.TextCellValue('10'),
  ]);

  excel.delete('Sheet1');
  return excel;
}

void main() {
  test('selectBestWorksheet prefere aba de dados sobre instrucoes (E8)', () {
    final excel = _buildMultiSheetWorkbook();
    final selection = selectBestWorksheet(
      excel.tables,
      entity: produtoSpreadsheetAliases,
    );

    expect(selection.isAmbiguous, isFalse);
    expect(selection.sheetName, 'Dados');
    expect(selection.issue, isNull);
  });

  test('selectBestWorksheet retorna NO_VALID_SHEET quando vazio', () {
    final excel = xls.Excel.createExcel();
    excel.delete('Sheet1');
    final selection = selectBestWorksheet(
      excel.tables,
      entity: clienteSpreadsheetAliases,
    );
    expect(selection.sheetName, isNull);
    expect(selection.issue?.code.name, 'noValidSheet');
  });
}
