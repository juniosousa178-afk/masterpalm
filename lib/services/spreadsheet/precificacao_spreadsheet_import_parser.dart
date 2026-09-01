import 'dart:typed_data';

import '../../core/spreadsheet/spreadsheet_cell_reader.dart';
import '../../core/spreadsheet/spreadsheet_column_mapper.dart';
import '../../core/spreadsheet/spreadsheet_entity_aliases.dart';
import '../../core/spreadsheet/spreadsheet_import_result.dart';
import '../../core/spreadsheet/spreadsheet_number_parser.dart';
import '../../core/spreadsheet/spreadsheet_workbook_decoder.dart';

class PrecificacaoImportRow {
  const PrecificacaoImportRow({
    required this.nome,
    required this.custo,
    required this.quantidade,
    required this.codigoProduto,
    required this.sourceRowNumber,
  });

  final String nome;
  final double custo;
  final int quantidade;
  final String codigoProduto;
  final int sourceRowNumber;
}

class PrecificacaoSpreadsheetParseResult {
  const PrecificacaoSpreadsheetParseResult({
    required this.rows,
    required this.result,
  });

  final List<PrecificacaoImportRow> rows;
  final SpreadsheetImportResult result;
}

PrecificacaoSpreadsheetParseResult parsePrecificacaoSpreadsheet(
  Uint8List bytes, {
  String? fileName,
}) {
  final decode = decodeSpreadsheetToMatrix(
    bytes,
    entity: precificacaoSpreadsheetAliases,
    fileName: fileName,
  );

  final issues = <SpreadsheetImportIssue>[...decode.issues];
  if (decode.rows.isEmpty) {
    return PrecificacaoSpreadsheetParseResult(
      rows: const [],
      result: SpreadsheetImportResult(issues: issues),
    );
  }

  final columnMap = buildSpreadsheetColumnMap(
    decode.rows,
    precificacaoSpreadsheetAliases,
  );
  issues.addAll(
    validateRequiredColumns(columnMap, precificacaoSpreadsheetAliases),
  );

  final missingRequired =
      columnMap.missingRequiredFields(precificacaoSpreadsheetAliases);
  if (missingRequired.isNotEmpty) {
    return PrecificacaoSpreadsheetParseResult(
      rows: const [],
      result: SpreadsheetImportResult(issues: issues),
    );
  }

  final parsed = <PrecificacaoImportRow>[];
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
    if (nome == null || nome.isEmpty) {
      rejected++;
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: rowNumber,
          code: SpreadsheetImportCode.missingRequiredField,
          field: 'nome',
          message: 'Nome é obrigatório',
        ),
      );
      continue;
    }

    final custo = _readNumber(mapped['custo'], rowNumber, 'custo', issues);
    if (custo == null || custo <= 0) {
      rejected++;
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: rowNumber,
          field: 'custo',
          code: SpreadsheetImportCode.invalidNumber,
          message: 'Custo inválido ou ausente',
        ),
      );
      continue;
    }

    final qtdRaw = _readText(mapped['quantidade'], rowNumber, 'quantidade', issues);
    final quantidade = (int.tryParse(qtdRaw ?? '') ?? 1).clamp(1, 999999);

    final codigo =
        _readText(mapped['codigoProduto'], rowNumber, 'codigoProduto', issues) ??
            '';

    _warnIdentifierNumeric(
      mapped['codigoProduto'],
      rowNumber,
      'codigoProduto',
      issues,
    );

    parsed.add(
      PrecificacaoImportRow(
        nome: nome,
        custo: custo,
        quantidade: quantidade,
        codigoProduto: codigo,
        sourceRowNumber: rowNumber,
      ),
    );
  }

  return PrecificacaoSpreadsheetParseResult(
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

double? _readNumber(
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
  return parseSpreadsheetNumber(read.number ?? read.text);
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
