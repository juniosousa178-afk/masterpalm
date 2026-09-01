import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_cell_reader.dart';

void main() {
  test('cellToText preserva texto e rejeita formula', () {
    expect(
      cellToText(xls.TextCellValue('5511987654321')),
      '5511987654321',
    );
    expect(cellToText(xls.FormulaCellValue('=A1')), isNull);
  });

  test('cellToNumber parseia int e double', () {
    expect(cellToNumber(xls.IntCellValue(15)), 15);
    expect(cellToNumber(xls.DoubleCellValue(15.5)), 15.5);
    expect(cellToNumber(xls.TextCellValue('15,50')), 15.5);
    expect(cellToNumber(xls.FormulaCellValue('=B2')), isNull);
  });
}
