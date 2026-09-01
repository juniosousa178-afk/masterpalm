import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/spreadsheet/cliente_spreadsheet_import_parser.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_import_result.dart';

Uint8List _xlsxBytes(void Function(xls.Sheet sheet) fill) {
  final excel = xls.Excel.createExcel();
  final sheet = excel['Sheet1'];
  fill(sheet);
  final bytes = excel.encode();
  return Uint8List.fromList(bytes!);
}

Uint8List _csvBytes(String content) => Uint8List.fromList(content.codeUnits);

void main() {
  test('C-HAPPY importa ordem oficial', () {
    final bytes = _csvBytes(
      'Nome;Telefone;Instagram;CEP;Cidade\n'
      'Maria Silva;5511987654321;mariasilva;01310100;Sao Paulo\n',
    );
    final parsed = parseClienteSpreadsheet(bytes, fileName: 'clientes.csv');
    expect(parsed.rows, hasLength(1));
    expect(parsed.rows.first.nome, 'Maria Silva');
    expect(parsed.rows.first.telefoneE164, '5511987654321');
  });

  test('C-REORDER mantem mapeamento semantico', () {
    final bytes = _csvBytes(
      'Telefone;Nome;Cidade;Instagram;CEP\n'
      '5511987654321;Maria Silva;Sao Paulo;mariasilva;01310100\n',
    );
    final parsed = parseClienteSpreadsheet(bytes, fileName: 'clientes.csv');
    expect(parsed.rows.first.nome, 'Maria Silva');
    expect(parsed.rows.first.cidade, 'Sao Paulo');
  });

  test('C-PHONE-EMPTY rejeita com motivo', () {
    final bytes = _csvBytes(
      'Nome;Telefone\n'
      'Sem Tel;\n',
    );
    final parsed = parseClienteSpreadsheet(bytes, fileName: 'clientes.csv');
    expect(parsed.rows, isEmpty);
    expect(
      parsed.result.issues.any(
        (i) => i.code == SpreadsheetImportCode.missingRequiredField,
      ),
      isTrue,
    );
  });

  test('C-PHONE-SHORT rejeita com INVALID_PHONE', () {
    final bytes = _csvBytes(
      'Nome;Telefone\n'
      'Curto;123\n',
    );
    final parsed = parseClienteSpreadsheet(bytes, fileName: 'clientes.csv');
    expect(parsed.rows, isEmpty);
    expect(
      parsed.result.issues.any((i) => i.code == SpreadsheetImportCode.invalidPhone),
      isTrue,
    );
  });

  test('C-PHONE-DUP-IN-FILE rejeita duplicado', () {
    final bytes = _csvBytes(
      'Nome;Telefone\n'
      'A;5511987654321\n'
      'B;5511987654321\n',
    );
    final parsed = parseClienteSpreadsheet(bytes, fileName: 'clientes.csv');
    expect(parsed.rows, hasLength(1));
    expect(
      parsed.result.issues.any(
        (i) => i.code == SpreadsheetImportCode.duplicatePhoneInFile,
      ),
      isTrue,
    );
  });

  test('C-MULTISHEET usa aba de dados', () {
    final excel = xls.Excel.createExcel();
    final instr = excel['Instrucoes'];
    instr.appendRow([
      xls.TextCellValue('Nome'),
      xls.TextCellValue('Telefone'),
    ]);
    final dados = excel['Dados'];
    dados.appendRow([
      xls.TextCellValue('Nome'),
      xls.TextCellValue('Telefone'),
      xls.TextCellValue('Instagram'),
      xls.TextCellValue('CEP'),
      xls.TextCellValue('Cidade'),
    ]);
    dados.appendRow([
      xls.TextCellValue('Joao'),
      xls.TextCellValue('5511999999999'),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue('SP'),
    ]);
    excel.delete('Sheet1');
    final bytes = Uint8List.fromList(excel.encode()!);
    final parsed = parseClienteSpreadsheet(bytes, fileName: 'clientes.xlsx');
    expect(parsed.rows, hasLength(1));
    expect(parsed.rows.first.nome, 'Joao');
  });

  test('OFFICIAL_TEMPLATE clientes csv roundtrip', () {
    final template = File('web/modelos-importacao/masterpalm-clientes-minimo.csv')
        .readAsBytesSync();
    final parsed = parseClienteSpreadsheet(
      Uint8List.fromList(template),
      fileName: 'masterpalm-clientes-minimo.csv',
    );
    expect(parsed.rows, isNotEmpty);
  });
}
