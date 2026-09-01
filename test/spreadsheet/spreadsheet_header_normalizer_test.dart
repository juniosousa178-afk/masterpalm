import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_header_normalizer.dart';

void main() {
  test('normalizeSpreadsheetHeader remove acentos e colapsa espacos', () {
    expect(normalizeSpreadsheetHeader('Preço de Venda'), 'preco de venda');
    expect(normalizeSpreadsheetHeader('PREÇO_DE_VENDA'), 'preco de venda');
    expect(normalizeSpreadsheetHeader(' preço  de  venda '), 'preco de venda');
    expect(normalizeSpreadsheetHeader('nome-cliente/ig'), 'nome cliente ig');
    expect(normalizeSpreadsheetHeader('Telefone\u00A0Celular'), 'telefone celular');
  });
}
