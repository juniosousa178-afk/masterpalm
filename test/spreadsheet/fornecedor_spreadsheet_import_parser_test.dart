import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/spreadsheet/fornecedor_spreadsheet_import_parser.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_import_result.dart';

Uint8List _csv(String content) => Uint8List.fromList(content.codeUnits);

void main() {
  test('fornecedor happy path csv', () {
    final parsed = parseFornecedorSpreadsheet(
      _csv(
        'Nome;Telefone;E-mail;Instagram;WhatsApp\n'
        'Fornecedor A;5511977777777;a@exemplo.com;ig;5511977777777\n',
      ),
      fileName: 'fornecedores.csv',
    );
    expect(parsed.rows, hasLength(1));
    expect(parsed.rows.first.nome, 'Fornecedor A');
  });

  test('fornecedor reordered columns', () {
    final parsed = parseFornecedorSpreadsheet(
      _csv(
        'WhatsApp;Telefone;Nome;Instagram;E-mail\n'
        '5511977777777;5511977777777;Fornecedor B;ig;b@exemplo.com\n',
      ),
      fileName: 'fornecedores.csv',
    );
    expect(parsed.rows.first.nome, 'Fornecedor B');
    expect(parsed.rows.first.email, 'b@exemplo.com');
  });

  test('fornecedor missing required rejected', () {
    final parsed = parseFornecedorSpreadsheet(
      _csv('Nome;Telefone\n;5511977777777\n'),
      fileName: 'fornecedores.csv',
    );
    expect(parsed.rows, isEmpty);
    expect(
      parsed.result.issues.any(
        (i) => i.code == SpreadsheetImportCode.missingRequiredField,
      ),
      isTrue,
    );
  });

  test('OFFICIAL_TEMPLATE fornecedores csv roundtrip', () {
    final template = File('web/modelos-importacao/masterpalm-fornecedores-minimo.csv')
        .readAsBytesSync();
    final parsed = parseFornecedorSpreadsheet(
      Uint8List.fromList(template),
      fileName: 'masterpalm-fornecedores-minimo.csv',
    );
    expect(parsed.rows, isNotEmpty);
  });
}
