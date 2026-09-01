import 'package:excel/excel.dart' as xls;

import 'spreadsheet_number_parser.dart';

enum SpreadsheetCellKind {
  text,
  intValue,
  doubleValue,
  boolValue,
  date,
  dateTime,
  time,
  formula,
  empty,
}

enum FormulaPolicy {
  reject,
  useCachedIfAvailable,
}

class SpreadsheetCellRead {
  const SpreadsheetCellRead({
    required this.kind,
    this.text,
    this.number,
    this.isFormula = false,
    this.hadLeadingZeroRisk = false,
  });

  final SpreadsheetCellKind kind;
  final String? text;
  final double? number;
  final bool isFormula;
  final bool hadLeadingZeroRisk;
}

SpreadsheetCellRead readSpreadsheetCell(
  dynamic value, {
  FormulaPolicy formulaPolicy = FormulaPolicy.reject,
}) {
  if (value == null) {
    return const SpreadsheetCellRead(kind: SpreadsheetCellKind.empty);
  }

  if (value is xls.CellValue) {
    return switch (value) {
      xls.TextCellValue(:final value) => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.text,
          text: value.text ?? value.toString(),
        ),
      xls.IntCellValue(:final value) => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.intValue,
          text: value.toString(),
          number: value.toDouble(),
          hadLeadingZeroRisk: true,
        ),
      xls.DoubleCellValue(:final value) => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.doubleValue,
          text: _formatDouble(value),
          number: value,
          hadLeadingZeroRisk: true,
        ),
      xls.BoolCellValue(:final value) => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.boolValue,
          text: value.toString(),
        ),
      xls.DateCellValue() => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.date,
          text: value.toString(),
        ),
      xls.DateTimeCellValue() => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.dateTime,
          text: value.toString(),
        ),
      xls.TimeCellValue() => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.time,
          text: value.toString(),
        ),
      xls.FormulaCellValue() => SpreadsheetCellRead(
          kind: SpreadsheetCellKind.formula,
          text: value.toString(),
          isFormula: true,
        ),
    };
  }

  if (value is num) {
    return SpreadsheetCellRead(
      kind: value is int
          ? SpreadsheetCellKind.intValue
          : SpreadsheetCellKind.doubleValue,
      text: value.toString(),
      number: value.toDouble(),
      hadLeadingZeroRisk: true,
    );
  }

  final s = value.toString();
  if (s.trim().isEmpty) {
    return const SpreadsheetCellRead(kind: SpreadsheetCellKind.empty);
  }
  return SpreadsheetCellRead(kind: SpreadsheetCellKind.text, text: s);
}

String _formatDouble(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

bool spreadsheetValueIsFormulaLike(dynamic value) {
  final read = readSpreadsheetCell(value);
  if (read.isFormula) return true;
  final text = read.text?.trim();
  return text != null && text.startsWith('=');
}

String? cellToText(
  dynamic value, {
  FormulaPolicy formulaPolicy = FormulaPolicy.reject,
}) {
  final read = readSpreadsheetCell(value, formulaPolicy: formulaPolicy);
  if (read.isFormula && formulaPolicy == FormulaPolicy.reject) return null;
  return read.text?.trim();
}

double? cellToNumber(
  dynamic value, {
  FormulaPolicy formulaPolicy = FormulaPolicy.reject,
}) {
  final read = readSpreadsheetCell(value, formulaPolicy: formulaPolicy);
  if (read.isFormula && formulaPolicy == FormulaPolicy.reject) return null;
  if (read.number != null) return read.number;
  return parseSpreadsheetNumber(read.text);
}

/// Extrai valor primitivo compatível com pipeline legado de produtos.
dynamic cellValueToObject(dynamic value) {
  final read = readSpreadsheetCell(value);
  if (read.kind == SpreadsheetCellKind.empty) return null;
  if (read.kind == SpreadsheetCellKind.intValue) {
    return int.tryParse(read.text ?? '') ?? read.number?.toInt();
  }
  if (read.kind == SpreadsheetCellKind.doubleValue) {
    return read.number;
  }
  if (read.kind == SpreadsheetCellKind.boolValue) {
    return read.text;
  }
  if (read.isFormula) return read.text;
  return read.text;
}
