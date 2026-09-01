import 'dart:typed_data';

import '../../core/spreadsheet/spreadsheet_cell_reader.dart';
import '../../core/spreadsheet/spreadsheet_column_mapper.dart';
import '../../core/spreadsheet/spreadsheet_entity_aliases.dart';
import '../../core/spreadsheet/spreadsheet_import_result.dart';
import '../../core/spreadsheet/spreadsheet_workbook_decoder.dart';

class FornecedorImportRow {
  const FornecedorImportRow({
    required this.nome,
    required this.telefone,
    required this.email,
    required this.instagram,
    required this.whatsapp,
    required this.sourceRowNumber,
  });

  final String nome;
  final String telefone;
  final String email;
  final String instagram;
  final String whatsapp;
  final int sourceRowNumber;
}

class FornecedorSpreadsheetParseResult {
  const FornecedorSpreadsheetParseResult({
    required this.rows,
    required this.result,
  });

  final List<FornecedorImportRow> rows;
  final SpreadsheetImportResult result;
}

FornecedorSpreadsheetParseResult parseFornecedorSpreadsheet(
  Uint8List bytes, {
  String? fileName,
}) {
  final decode = decodeSpreadsheetToMatrix(
    bytes,
    entity: fornecedorSpreadsheetAliases,
    fileName: fileName,
  );

  final issues = <SpreadsheetImportIssue>[...decode.issues];
  if (decode.rows.isEmpty) {
    return FornecedorSpreadsheetParseResult(
      rows: const [],
      result: SpreadsheetImportResult(issues: issues),
    );
  }

  final columnMap = buildSpreadsheetColumnMap(
    decode.rows,
    fornecedorSpreadsheetAliases,
  );
  issues.addAll(
    validateRequiredColumns(columnMap, fornecedorSpreadsheetAliases),
  );

  final missingRequired =
      columnMap.missingRequiredFields(fornecedorSpreadsheetAliases);
  if (missingRequired.isNotEmpty) {
    return FornecedorSpreadsheetParseResult(
      rows: const [],
      result: SpreadsheetImportResult(issues: issues),
    );
  }

  final parsed = <FornecedorImportRow>[];
  var totalRows = 0;
  var rejected = 0;
  var skipped = 0;

  for (var r = columnMap.headerRowIndex + 1; r < decode.rows.length; r++) {
    final row = decode.rows[r];
    if (!rowHasUsefulData(row)) {
      skipped++;
      continue;
    }
    totalRows++;

    final mapped = mapRowByField(row, columnMap);
    final rowNumber = r + 1;

    final nome = _readText(mapped['nome'], rowNumber, 'nome', issues);
    final telefone = _readText(mapped['telefone'], rowNumber, 'telefone', issues);

    if (nome == null || nome.isEmpty || telefone == null || telefone.isEmpty) {
      rejected++;
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: rowNumber,
          code: SpreadsheetImportCode.missingRequiredField,
          field: 'nome/telefone',
          message: 'Nome e telefone são obrigatórios',
        ),
      );
      continue;
    }

    _warnIdentifierNumeric(mapped['telefone'], rowNumber, 'telefone', issues);
    _warnIdentifierNumeric(mapped['whatsapp'], rowNumber, 'whatsapp', issues);

    parsed.add(
      FornecedorImportRow(
        nome: nome,
        telefone: telefone,
        email: _readText(mapped['email'], rowNumber, 'email', issues) ?? '',
        instagram:
            _readText(mapped['instagram'], rowNumber, 'instagram', issues) ??
                '',
        whatsapp:
            _readText(mapped['whatsapp'], rowNumber, 'whatsapp', issues) ?? '',
        sourceRowNumber: rowNumber,
      ),
    );
  }

  return FornecedorSpreadsheetParseResult(
    rows: parsed,
    result: SpreadsheetImportResult(
      totalRows: totalRows,
      importedRows: parsed.length,
      rejectedRows: rejected,
      skippedRows: skipped,
      issues: issues,
    ),
  );
}

String? _readText(
  dynamic cell,
  int rowNumber,
  String field,
  List<SpreadsheetImportIssue> issues,
) {
  if (spreadsheetValueIsFormulaLike(cell)) {
    issues.add(
      SpreadsheetImportIssue(
        rowNumber: rowNumber,
        field: field,
        code: SpreadsheetImportCode.formulaNotSupported,
        message: 'Fórmula não suportada em $field',
      ),
    );
    return null;
  }
  final read = readSpreadsheetCell(cell);
  return read.text?.trim();
}

void _warnIdentifierNumeric(
  dynamic cell,
  int rowNumber,
  String field,
  List<SpreadsheetImportIssue> issues,
) {
  final read = readSpreadsheetCell(cell);
  if (read.hadLeadingZeroRisk && read.kind != SpreadsheetCellKind.text) {
    issues.add(
      SpreadsheetImportIssue(
        rowNumber: rowNumber,
        field: field,
        code: SpreadsheetImportCode.identifierNumericCell,
        message:
            'Célula numérica pode ter perdido zeros à esquerda em $field',
      ),
    );
  }
}
