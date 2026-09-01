import 'spreadsheet_import_result.dart';

String formatSpreadsheetImportSummary(SpreadsheetImportResult result) {
  final parts = <String>[];
  if (result.importedRows > 0) {
    parts.add('${result.importedRows} importado(s)');
  }
  if (result.rejectedRows > 0) {
    parts.add('${result.rejectedRows} rejeitado(s)');
  }
  if (result.skippedRows > 0) {
    parts.add('${result.skippedRows} ignorado(s)');
  }
  if (parts.isEmpty) return 'Nenhum registro importado';
  return parts.join(' · ');
}

String spreadsheetIssueDetail(SpreadsheetImportIssue issue) {
  final field = issue.field != null ? ' (${issue.field})' : '';
  final msg = issue.message ?? issue.codeLabel;
  return 'Linha ${issue.rowNumber}$field: $msg';
}

List<String> topSpreadsheetIssues(
  List<SpreadsheetImportIssue> issues, {
  int max = 5,
}) {
  return issues.take(max).map(spreadsheetIssueDetail).toList();
}
