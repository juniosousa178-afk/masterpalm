import '../../models/report/report_block.dart';
import '../../models/report/report_document.dart';
import '../../models/report/report_format.dart';
import '../../models/report/report_finding.dart';
import '../../models/report/report_severity.dart';
import '../../models/report/report_section.dart';
import '../../models/report/report_table.dart';
import 'report_renderer.dart';

/// Deterministic Markdown renderer for [ReportDocument].
class MarkdownReportRenderer implements ReportRenderer {
  const MarkdownReportRenderer();

  @override
  ReportFormat get format => ReportFormat.markdown;

  @override
  String render(ReportDocument document) {
    final buf = StringBuffer();
    for (final section in document.sections) {
      _renderSection(buf, section);
    }
    var output = buf.toString();
    output = output.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    output = output.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (!output.endsWith('\n')) {
      output = '$output\n';
    }
    return output;
  }

  void _renderSection(StringBuffer buf, ReportSection section) {
    for (final block in section.blocks) {
      _renderBlock(buf, block);
    }
  }

  void _renderBlock(StringBuffer buf, ReportBlock block) {
    switch (block) {
      case HeadingBlock(:final level, :final text):
        buf.writeln('${'#' * level.clamp(1, 6)} $text');
        buf.writeln();
      case TextBlock(:final text):
        buf.writeln(text);
        buf.writeln();
      case ListBlock(:final items, :final ordered):
        for (var i = 0; i < items.length; i++) {
          final prefix = ordered ? '${i + 1}. ' : '- ';
          buf.writeln('$prefix${items[i]}');
        }
        buf.writeln();
      case TableBlock(:final table):
        _renderTable(buf, table);
      case CodeBlock(:final code, :final language):
        buf.writeln('```${language ?? ''}');
        buf.writeln(code);
        buf.writeln('```');
        buf.writeln();
      case FindingBlock(:final finding):
        _renderFinding(buf, finding);
      case SummaryBlock(:final text):
        buf.writeln(text);
        buf.writeln();
      case DecisionBlock(:final decision, :final simulationOnly):
        buf.writeln('**Decisão:** `${decision.toUpperCase()}`');
        buf.writeln('**Modo simulação:** $simulationOnly');
        buf.writeln();
    }
  }

  void _renderTable(StringBuffer buf, ReportTable table) {
    if (table.columns.isEmpty) return;
    final headers = table.columns.map((c) => _escapeCell(c.label)).join(' | ');
    buf.writeln('| $headers |');
    buf.writeln('|${' --- |' * table.columns.length}');
    for (final row in table.rows) {
      final cells = row.cells.map(_escapeCell).join(' | ');
      buf.writeln('| $cells |');
    }
    buf.writeln();
  }

  void _renderFinding(StringBuffer buf, ReportFinding finding) {
    buf.writeln('### ${finding.code} — ${finding.severity.wireName}');
    buf.writeln('- **Mensagem:** ${finding.message}');
    if (finding.source != null) {
      buf.writeln('- **Ficheiro:** `${finding.source}`');
    }
    for (final entry in finding.details.entries) {
      buf.writeln('- **${entry.key}:** ${entry.value}');
    }
    buf.writeln();
  }

  String _escapeCell(String value) {
    return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
  }
}
