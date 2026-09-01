import 'dart:convert';

import 'package:csv/csv.dart';

import 'spreadsheet_header_normalizer.dart';

/// Decodifica bytes CSV em matriz de strings (sem converter números).
List<List<String>> decodeCsvBytes(
  List<int> bytes, {
  bool stripBom = true,
}) {
  String text;
  try {
    text = utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    text = latin1.decode(bytes);
  }

  if (stripBom && text.startsWith('\uFEFF')) {
    text = text.substring(1);
  }

  if (text.trim().isEmpty) return [];

  final firstLine = text.split('\n').first;
  final semicolons = ';'.allMatches(firstLine).length;
  final commas = ','.allMatches(firstLine).length;
  final delimiter = semicolons > commas ? ';' : ',';

  List<List<dynamic>> rows;
  if (delimiter == ';') {
    rows = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => _splitCsvLine(l, ';'))
        .toList();
  } else {
    rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text);
  }

  return rows
      .map((row) => row.map((c) => (c ?? '').toString()).toList())
      .toList();
}

List<String> _splitCsvLine(String line, String delimiter) {
  final out = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == delimiter && !inQuotes) {
      out.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  out.add(buffer.toString());
  return out;
}

List<List<dynamic>> csvMatrixToDynamicRows(List<List<String>> matrix) {
  return matrix.map((r) => r.map<dynamic>((c) => c).toList()).toList();
}

List<String> normalizeCsvHeaders(List<String> headers) {
  return headers.map(normalizeSpreadsheetHeader).toList();
}
