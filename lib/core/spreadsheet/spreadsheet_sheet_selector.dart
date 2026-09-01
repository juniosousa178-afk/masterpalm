import 'package:excel/excel.dart' as xls;

import 'spreadsheet_column_mapper.dart';
import 'spreadsheet_entity_aliases.dart';
import 'spreadsheet_header_normalizer.dart';
import 'spreadsheet_import_result.dart';

class SpreadsheetSheetSelection {
  const SpreadsheetSheetSelection({
    required this.sheetName,
    required this.score,
    this.isAmbiguous = false,
    this.issue,
  });

  final String? sheetName;
  final int score;
  final bool isAmbiguous;
  final SpreadsheetImportIssue? issue;
}

class SpreadsheetSheetSelectorException implements Exception {
  SpreadsheetSheetSelectorException(this.message, {this.code});

  final String message;
  final SpreadsheetImportCode? code;

  @override
  String toString() => message;
}

SpreadsheetSheetSelection selectBestWorksheet(
  Map<String, xls.Sheet> tables, {
  required SpreadsheetEntityAliases entity,
  int minDataRows = 1,
  int maxDataRowsScore = 20,
}) {
  if (tables.isEmpty) {
    return SpreadsheetSheetSelection(
      sheetName: null,
      score: 0,
      issue: const SpreadsheetImportIssue(
        rowNumber: 0,
        code: SpreadsheetImportCode.noValidSheet,
        message: 'Nenhuma aba encontrada',
      ),
    );
  }

  final candidates = <_SheetCandidate>[];

  for (final entry in tables.entries) {
    final sheetName = entry.key;
    final table = entry.value;
    if (table.rows.isEmpty) continue;

    final rawRows = table.rows
        .map((r) => r.map((c) => c?.value).toList())
        .toList();

    final columnMap = buildColumnMap(rawRows, entity);
    final matchedRequired = columnMap.fieldToColumnIndex.keys
        .where((f) => entity.requiredFields().contains(f))
        .length;
    final matchedOptional = columnMap.fieldToColumnIndex.length -
        matchedRequired;

    var dataRows = 0;
    for (var r = columnMap.headerRowIndex + 1; r < rawRows.length; r++) {
      if (rowHasUsefulData(rawRows[r])) dataRows++;
    }

    if (matchedRequired == 0 && dataRows == 0) continue;

    final instructionPenalty = _instructionPenalty(sheetName);
    final dataScore = dataRows.clamp(0, maxDataRowsScore);
    final score = matchedRequired * 10 +
        matchedOptional * 2 +
        dataScore -
        instructionPenalty;

    candidates.add(
      _SheetCandidate(
        name: sheetName,
        score: score,
        matchedRequired: matchedRequired,
        dataRows: dataRows,
        instructionPenalty: instructionPenalty,
      ),
    );
  }

  if (candidates.isEmpty) {
    return SpreadsheetSheetSelection(
      sheetName: null,
      score: 0,
      issue: const SpreadsheetImportIssue(
        rowNumber: 0,
        code: SpreadsheetImportCode.noValidSheet,
        message: 'Nenhuma aba com dados válidos',
      ),
    );
  }

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byRequired = b.matchedRequired.compareTo(a.matchedRequired);
    if (byRequired != 0) return byRequired;
    final byData = b.dataRows.compareTo(a.dataRows);
    if (byData != 0) return byData;
    final byDataName = _dataNameScore(b.name).compareTo(_dataNameScore(a.name));
    if (byDataName != 0) return byDataName;
    return a.name.compareTo(b.name);
  });

  final best = candidates.first;
  final tied = candidates.where((c) =>
      c.score == best.score &&
      c.matchedRequired == best.matchedRequired &&
      c.dataRows == best.dataRows &&
      _dataNameScore(c.name) == _dataNameScore(best.name));

  if (tied.length > 1 && best.matchedRequired > 0) {
    return SpreadsheetSheetSelection(
      sheetName: null,
      score: best.score,
      isAmbiguous: true,
      issue: SpreadsheetImportIssue(
        rowNumber: 0,
        code: SpreadsheetImportCode.ambiguousSheet,
        message:
            'Múltiplas abas com mesmo score: ${tied.map((e) => e.name).join(', ')}',
      ),
    );
  }

  if (best.dataRows < minDataRows && best.matchedRequired == 0) {
    return SpreadsheetSheetSelection(
      sheetName: null,
      score: best.score,
      issue: const SpreadsheetImportIssue(
        rowNumber: 0,
        code: SpreadsheetImportCode.noValidSheet,
        message: 'Nenhuma aba com cabeçalhos obrigatórios',
      ),
    );
  }

  return SpreadsheetSheetSelection(
    sheetName: best.name,
    score: best.score,
  );
}

class _SheetCandidate {
  const _SheetCandidate({
    required this.name,
    required this.score,
    required this.matchedRequired,
    required this.dataRows,
    required this.instructionPenalty,
  });

  final String name;
  final int score;
  final int matchedRequired;
  final int dataRows;
  final int instructionPenalty;
}

int _instructionPenalty(String sheetName) {
  final n = normalizeSpreadsheetHeader(sheetName);
  if (RegExp(r'instruc|readme|ajuda|modelo|info|sobre').hasMatch(n)) {
    return 50;
  }
  return 0;
}

int _dataNameScore(String sheetName) {
  final n = normalizeSpreadsheetHeader(sheetName);
  if (RegExp(r'dados|produtos|clientes|fornecedor|estoque|sheet').hasMatch(n)) {
    return 1;
  }
  return 0;
}
