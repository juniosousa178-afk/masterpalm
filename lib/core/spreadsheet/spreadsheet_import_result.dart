/// Resultado estruturado de importação de planilha.
library;

enum SpreadsheetImportCode {
  missingRequiredField,
  invalidPhone,
  duplicatePhoneInFile,
  duplicatePhoneInDatabase,
  invalidNumber,
  formulaNotSupported,
  ambiguousSheet,
  noValidSheet,
  unknownHeader,
  identifierNumericCell,
  blankRow,
  fileReadError,
  parseError,
}

class SpreadsheetImportIssue {
  const SpreadsheetImportIssue({
    required this.rowNumber,
    required this.code,
    this.field,
    this.message,
    this.rawValue,
  });

  final int rowNumber;
  final SpreadsheetImportCode code;
  final String? field;
  final String? message;
  final String? rawValue;

  String get codeLabel => switch (code) {
        SpreadsheetImportCode.missingRequiredField => 'MISSING_REQUIRED_FIELD',
        SpreadsheetImportCode.invalidPhone => 'INVALID_PHONE',
        SpreadsheetImportCode.duplicatePhoneInFile => 'DUPLICATE_PHONE_IN_FILE',
        SpreadsheetImportCode.duplicatePhoneInDatabase =>
          'DUPLICATE_PHONE_IN_DATABASE',
        SpreadsheetImportCode.invalidNumber => 'INVALID_NUMBER',
        SpreadsheetImportCode.formulaNotSupported => 'FORMULA_NOT_SUPPORTED',
        SpreadsheetImportCode.ambiguousSheet => 'AMBIGUOUS_SHEET',
        SpreadsheetImportCode.noValidSheet => 'NO_VALID_SHEET',
        SpreadsheetImportCode.unknownHeader => 'UNKNOWN_HEADER',
        SpreadsheetImportCode.identifierNumericCell => 'IDENTIFIER_NUMERIC_CELL',
        SpreadsheetImportCode.blankRow => 'BLANK_ROW',
        SpreadsheetImportCode.fileReadError => 'FILE_READ_ERROR',
        SpreadsheetImportCode.parseError => 'PARSE_ERROR',
      };
}

class SpreadsheetImportResult {
  const SpreadsheetImportResult({
    this.totalRows = 0,
    this.importedRows = 0,
    this.rejectedRows = 0,
    this.skippedRows = 0,
    this.issues = const [],
  });

  final int totalRows;
  final int importedRows;
  final int rejectedRows;
  final int skippedRows;
  final List<SpreadsheetImportIssue> issues;

  SpreadsheetImportResult merge(SpreadsheetImportResult other) {
    return SpreadsheetImportResult(
      totalRows: totalRows + other.totalRows,
      importedRows: importedRows + other.importedRows,
      rejectedRows: rejectedRows + other.rejectedRows,
      skippedRows: skippedRows + other.skippedRows,
      issues: [...issues, ...other.issues],
    );
  }

  SpreadsheetImportResult copyWith({
    int? totalRows,
    int? importedRows,
    int? rejectedRows,
    int? skippedRows,
    List<SpreadsheetImportIssue>? issues,
  }) {
    return SpreadsheetImportResult(
      totalRows: totalRows ?? this.totalRows,
      importedRows: importedRows ?? this.importedRows,
      rejectedRows: rejectedRows ?? this.rejectedRows,
      skippedRows: skippedRows ?? this.skippedRows,
      issues: issues ?? this.issues,
    );
  }
}
