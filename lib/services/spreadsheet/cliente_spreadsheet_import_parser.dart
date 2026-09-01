import 'dart:typed_data';

import '../../core/spreadsheet/spreadsheet_cell_reader.dart';
import '../../core/spreadsheet/spreadsheet_column_mapper.dart';
import '../../core/spreadsheet/spreadsheet_entity_aliases.dart';
import '../../core/spreadsheet/spreadsheet_import_result.dart';
import '../../core/spreadsheet/spreadsheet_workbook_decoder.dart';

class ClienteImportRow {
  const ClienteImportRow({
    required this.nome,
    required this.telefoneE164,
    required this.instagram,
    required this.cep,
    required this.cidade,
    required this.sourceRowNumber,
  });

  final String nome;
  final String telefoneE164;
  final String instagram;
  final String cep;
  final String cidade;
  final int sourceRowNumber;
}

class ClienteSpreadsheetParseResult {
  const ClienteSpreadsheetParseResult({
    required this.rows,
    required this.result,
  });

  final List<ClienteImportRow> rows;
  final SpreadsheetImportResult result;
}

ClienteSpreadsheetParseResult parseClienteSpreadsheet(
  Uint8List bytes, {
  String? fileName,
}) {
  final decode = decodeSpreadsheetToMatrix(
    bytes,
    entity: clienteSpreadsheetAliases,
    fileName: fileName,
  );

  final issues = <SpreadsheetImportIssue>[...decode.issues];
  if (decode.rows.isEmpty) {
    return ClienteSpreadsheetParseResult(
      rows: const [],
      result: SpreadsheetImportResult(issues: issues),
    );
  }

  final columnMap = buildSpreadsheetColumnMap(
    decode.rows,
    clienteSpreadsheetAliases,
  );
  issues.addAll(validateRequiredColumns(columnMap, clienteSpreadsheetAliases));

  final missingRequired = columnMap.missingRequiredFields(clienteSpreadsheetAliases);
  if (missingRequired.isNotEmpty) {
    return ClienteSpreadsheetParseResult(
      rows: const [],
      result: SpreadsheetImportResult(issues: issues),
    );
  }

  final parsed = <ClienteImportRow>[];
  final phonesInFile = <String>{};
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

    final nome = _readTextField(mapped['nome'], rowNumber, 'nome', issues);
    final telefoneRaw =
        _readTextField(mapped['telefone'], rowNumber, 'telefone', issues);

    if (nome == null || nome.isEmpty || telefoneRaw == null || telefoneRaw.isEmpty) {
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

    final e164 = _normalizePhoneE164(telefoneRaw);
    if (e164.length < 10) {
      rejected++;
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: rowNumber,
          field: 'telefone',
          code: SpreadsheetImportCode.invalidPhone,
          message: 'Telefone curto após normalização',
          rawValue: telefoneRaw,
        ),
      );
      continue;
    }

    if (phonesInFile.contains(e164)) {
      rejected++;
      issues.add(
        SpreadsheetImportIssue(
          rowNumber: rowNumber,
          field: 'telefone',
          code: SpreadsheetImportCode.duplicatePhoneInFile,
          message: 'Telefone duplicado no arquivo',
          rawValue: e164,
        ),
      );
      continue;
    }
    phonesInFile.add(e164);

    _warnIdentifierNumeric(mapped['telefone'], rowNumber, 'telefone', issues);
    _warnIdentifierNumeric(mapped['cep'], rowNumber, 'cep', issues);

    parsed.add(
      ClienteImportRow(
        nome: nome,
        telefoneE164: e164,
        instagram: _readTextField(mapped['instagram'], rowNumber, 'instagram', issues) ?? '',
        cep: _readTextField(mapped['cep'], rowNumber, 'cep', issues) ?? '',
        cidade: _readTextField(mapped['cidade'], rowNumber, 'cidade', issues) ?? '',
        sourceRowNumber: rowNumber,
      ),
    );
  }

  return ClienteSpreadsheetParseResult(
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

String _normalizePhoneE164(String telefone) {
  final limpo = telefone.replaceAll(RegExp(r'\D'), '');
  return limpo.startsWith('55') ? limpo : '55$limpo';
}

String? _readTextField(
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
