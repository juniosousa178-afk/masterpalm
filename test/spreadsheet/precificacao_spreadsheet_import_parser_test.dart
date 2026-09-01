import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_import_result.dart';
import 'package:master_palm/services/spreadsheet/precificacao_spreadsheet_import_parser.dart';

Uint8List _csv(String content) => Uint8List.fromList(content.codeUnits);

void main() {
  final numericCases = <String, double>{
    '15.50': 15.5,
    '15,50': 15.5,
    '1.234,56': 1234.56,
    '1234,56': 1234.56,
    '1234.56': 1234.56,
    'R\$ 1.234,56': 1234.56,
  };

  for (final entry in numericCases.entries) {
    test('precificacao custo ${entry.key}', () {
      final parsed = parsePrecificacaoSpreadsheet(
        _csv('Nome;Custo;Quantidade;Codigo\nItem;${entry.key};1;SKU1\n'),
        fileName: 'preco.csv',
      );
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.first.custo, entry.value);
    });
  }

  test('precificacao reordered columns', () {
    final parsed = parsePrecificacaoSpreadsheet(
      _csv('Custo;Nome;Codigo;Quantidade\n22,00;Colar;SKU2;2\n'),
      fileName: 'preco.csv',
    );
    expect(parsed.rows.first.nome, 'Colar');
    expect(parsed.rows.first.quantidade, 2);
  });

  test('precificacao formula rejected', () {
    final excel = xls.Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([
      xls.TextCellValue('Nome'),
      xls.TextCellValue('Custo'),
      xls.TextCellValue('Quantidade'),
      xls.TextCellValue('Codigo'),
    ]);
    sheet.appendRow([
      xls.TextCellValue('Item'),
      xls.FormulaCellValue('=10+5'),
      xls.TextCellValue('1'),
      xls.TextCellValue(''),
    ]);
    final bytes = Uint8List.fromList(excel.encode()!);
    final parsed = parsePrecificacaoSpreadsheet(bytes, fileName: 'preco.xlsx');
    expect(parsed.rows, isEmpty);
    expect(
      parsed.result.issues.any(
        (i) => i.code == SpreadsheetImportCode.formulaNotSupported,
      ),
      isTrue,
    );
  });

  test('OFFICIAL_TEMPLATE precificacao csv roundtrip', () {
    final template =
        File('web/modelos-importacao/masterpalm-precificacao-minimo.csv')
            .readAsBytesSync();
    final parsed = parsePrecificacaoSpreadsheet(
      Uint8List.fromList(template),
      fileName: 'masterpalm-precificacao-minimo.csv',
    );
    expect(parsed.rows, isNotEmpty);
    expect(parsed.rows.first.custo, closeTo(15.5, 0.001));
  });
}
