import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_number_parser.dart';

void main() {
  final cases = <String, double>{
    '15': 15,
    '15.5': 15.5,
    '15.50': 15.5,
    '15,5': 15.5,
    '15,50': 15.5,
    '1.234,56': 1234.56,
    '1234,56': 1234.56,
    '1,234.56': 1234.56,
    '1234.56': 1234.56,
    'R\$ 1.234,56': 1234.56,
    'R\$1234,56': 1234.56,
  };

  for (final entry in cases.entries) {
    test('parseSpreadsheetNumber ${entry.key}', () {
      expect(parseSpreadsheetNumber(entry.key), entry.value);
    });
  }
}
