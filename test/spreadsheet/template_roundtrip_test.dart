import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_csv_decoder.dart';

void main() {
  test('template estoque csv decodifica cabecalhos', () {
    final bytes = File('web/modelos-importacao/masterpalm-estoque-minimo.csv')
        .readAsBytesSync();
    final matrix = decodeCsvBytes(bytes);
    expect(matrix, isNotEmpty);
    expect(matrix.first.join(';').toLowerCase(), contains('nome'));
  });
}
