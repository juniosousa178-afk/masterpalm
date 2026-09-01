import 'spreadsheet_entity_aliases.dart';
import 'spreadsheet_header_normalizer.dart';

class SpreadsheetColumnMap {
  const SpreadsheetColumnMap({
    required this.headerRowIndex,
    required this.fieldToColumnIndex,
    this.unknownHeaders = const [],
  });

  final int headerRowIndex;
  final Map<String, int> fieldToColumnIndex;
  final List<String> unknownHeaders;

  List<String> missingRequiredFields(SpreadsheetEntityAliases entity) {
    final required = entity.requiredFields();
    return required
        .where((f) => !fieldToColumnIndex.containsKey(f))
        .toList();
  }
}

int findBestHeaderRowIndex(
  List<List<dynamic>> rows,
  SpreadsheetEntityAliases entity, {
  int maxScan = 30,
}) {
  final limit = rows.length < maxScan ? rows.length : maxScan;
  var bestIndex = 0;
  var bestScore = -1;

  for (var r = 0; r < limit; r++) {
    final score = _headerRowScore(rows[r], entity);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = r;
    }
  }

  if (bestScore <= 0) return 0;
  return bestIndex;
}

int _headerRowScore(List<dynamic> row, SpreadsheetEntityAliases entity) {
  var score = 0;
  for (final cell in row) {
    final raw = (cell ?? '').toString();
    if (fieldForHeader(raw, entity) != null) score++;
  }
  return score;
}

SpreadsheetColumnMap buildColumnMap(
  List<List<dynamic>> rows,
  SpreadsheetEntityAliases entity, {
  int maxScan = 30,
}) {
  if (rows.isEmpty) {
    return const SpreadsheetColumnMap(
      headerRowIndex: 0,
      fieldToColumnIndex: {},
    );
  }

  final headerRowIndex = findBestHeaderRowIndex(rows, entity, maxScan: maxScan);
  final headerRow = rows[headerRowIndex];
  final fieldToColumn = <String, int>{};
  final unknown = <String>[];

  for (var c = 0; c < headerRow.length; c++) {
    final raw = (headerRow[c] ?? '').toString();
    final normalized = normalizeSpreadsheetHeader(raw);
    if (normalized.isEmpty) continue;

    final field = fieldForHeader(raw, entity);
    if (field != null) {
      fieldToColumn.putIfAbsent(field, () => c);
    } else {
      unknown.add(raw);
    }
  }

  return SpreadsheetColumnMap(
    headerRowIndex: headerRowIndex,
    fieldToColumnIndex: fieldToColumn,
    unknownHeaders: unknown,
  );
}

Map<String, dynamic> mapRowByField(
  List<dynamic> row,
  SpreadsheetColumnMap columnMap,
) {
  final out = <String, dynamic>{};
  for (final entry in columnMap.fieldToColumnIndex.entries) {
    final idx = entry.value;
    out[entry.key] = idx < row.length ? row[idx] : null;
  }
  return out;
}

bool rowHasUsefulData(List<dynamic> row) {
  for (final c in row) {
    final v = (c ?? '').toString().trim();
    if (v.isNotEmpty) return true;
  }
  return false;
}
