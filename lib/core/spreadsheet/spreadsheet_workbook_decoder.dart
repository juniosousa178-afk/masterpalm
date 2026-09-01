import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import 'spreadsheet_cell_reader.dart';
import 'spreadsheet_column_mapper.dart';
import 'spreadsheet_csv_decoder.dart';
import 'spreadsheet_entity_aliases.dart';
import 'spreadsheet_file_reader.dart';
import 'spreadsheet_import_result.dart';
import 'spreadsheet_sheet_selector.dart';

class SpreadsheetMatrixDecodeResult {
  const SpreadsheetMatrixDecodeResult({
    required this.rows,
    this.sheetName,
    this.issues = const [],
  });

  final List<List<dynamic>> rows;
  final String? sheetName;
  final List<SpreadsheetImportIssue> issues;
}

SpreadsheetMatrixDecodeResult decodeSpreadsheetToMatrix(
  Uint8List bytes, {
  required SpreadsheetEntityAliases entity,
  String? fileName,
  int headerScanMax = 30,
}) {
  final issues = <SpreadsheetImportIssue>[];

  if (isCsvFileName(fileName)) {
    final matrix = decodeCsvBytes(bytes);
    return SpreadsheetMatrixDecodeResult(
      rows: csvMatrixToDynamicRows(matrix),
      sheetName: 'csv',
    );
  }

  final excel = xls.Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) {
    return SpreadsheetMatrixDecodeResult(
      rows: const [],
      issues: [
        const SpreadsheetImportIssue(
          rowNumber: 0,
          code: SpreadsheetImportCode.noValidSheet,
          message: 'Arquivo sem abas',
        ),
      ],
    );
  }

  final selection = selectBestWorksheet(excel.tables, entity: entity);
  if (selection.issue != null) {
    issues.add(selection.issue!);
  }
  if (selection.sheetName == null) {
    return SpreadsheetMatrixDecodeResult(rows: const [], issues: issues);
  }

  final table = excel.tables[selection.sheetName]!;
  final rows = table.rows
      .map(
        (r) => r.map((c) => cellValueToObject(c?.value)).toList(),
      )
      .toList();

  return SpreadsheetMatrixDecodeResult(
    rows: rows,
    sheetName: selection.sheetName,
    issues: issues,
  );
}

SpreadsheetColumnMap buildSpreadsheetColumnMap(
  List<List<dynamic>> rows,
  SpreadsheetEntityAliases entity, {
  int maxScan = 30,
}) {
  return buildColumnMap(rows, entity, maxScan: maxScan);
}

List<SpreadsheetImportIssue> validateRequiredColumns(
  SpreadsheetColumnMap columnMap,
  SpreadsheetEntityAliases entity,
) {
  final missing = columnMap.missingRequiredFields(entity);
  if (missing.isEmpty) return const [];
  return [
    SpreadsheetImportIssue(
      rowNumber: columnMap.headerRowIndex + 1,
      code: SpreadsheetImportCode.missingRequiredField,
      field: missing.join(', '),
      message: 'Colunas obrigatórias não encontradas: ${missing.join(', ')}',
    ),
  ];
}
