import '../../models/report/report_block.dart';
import '../../models/report/report_document.dart';
import '../../models/report/report_format.dart';
import '../../models/report/report_finding.dart';
import '../../models/report/report_severity.dart';
import '../../models/report/report_type.dart';
import '../../models/report/report_table.dart';
import 'report_renderer.dart';

/// Offline HTML renderer without external dependencies.
class HtmlReportRenderer implements ReportRenderer {
  const HtmlReportRenderer();

  @override
  ReportFormat get format => ReportFormat.html;

  @override
  String render(ReportDocument document) {
    final buf = StringBuffer();
    buf.writeln('<!DOCTYPE html>');
    buf.writeln('<html lang="pt">');
    buf.writeln('<head>');
    buf.writeln('<meta charset="utf-8">');
    buf.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
    );
    buf.writeln(
      '<title>${_escape(document.metadata.reportType.wireName)}</title>',
    );
    buf.writeln(
      '<style>body{font-family:system-ui,sans-serif;margin:2rem;line-height:1.5}'
      'table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:.5rem}'
      'pre{background:#f5f5f5;padding:1rem;overflow:auto}'
      '.finding{border-left:4px solid #c00;padding-left:1rem;margin:1rem 0}'
      '.decision{font-weight:bold;font-size:1.2rem}</style>',
    );
    buf.writeln('</head>');
    buf.writeln('<body>');
    buf.writeln(
      '<header><h1>${_escape(document.metadata.reportType.wireName)}</h1>'
      '<p>Project: ${_escape(document.metadata.projectId)}</p></header>',
    );
    for (final section in document.sections) {
      buf.writeln('<section id="${_escape(section.id)}">');
      buf.writeln('<h2>${_escape(section.title)}</h2>');
      for (final block in section.blocks) {
        _renderBlock(buf, block);
      }
      buf.writeln('</section>');
    }
    buf.writeln('</body>');
    buf.writeln('</html>');
    return buf.toString();
  }

  void _renderBlock(StringBuffer buf, ReportBlock block) {
    switch (block) {
      case HeadingBlock(:final level, :final text):
        final tag = 'h${level.clamp(1, 6)}';
        buf.writeln('<$tag>${_escape(text)}</$tag>');
      case TextBlock(:final text):
        buf.writeln('<p>${_escape(text)}</p>');
      case ListBlock(:final items, :final ordered):
        final tag = ordered ? 'ol' : 'ul';
        buf.writeln('<$tag>');
        for (final item in items) {
          buf.writeln('<li>${_escape(item)}</li>');
        }
        buf.writeln('</$tag>');
      case TableBlock(:final table):
        _renderTable(buf, table);
      case CodeBlock(:final code, :final language):
        final lang = language != null ? ' class="${_escape(language)}"' : '';
        buf.writeln('<pre><code$lang>${_escape(code)}</code></pre>');
      case FindingBlock(:final finding):
        _renderFinding(buf, finding);
      case SummaryBlock(:final text):
        buf.writeln('<p><strong>Resumo:</strong> ${_escape(text)}</p>');
      case DecisionBlock(:final decision, :final simulationOnly):
        buf.writeln(
          '<p class="decision">Decisão: ${_escape(decision.toUpperCase())} '
          '(simulação: $simulationOnly)</p>',
        );
    }
  }

  void _renderTable(StringBuffer buf, ReportTable table) {
    if (table.columns.isEmpty) return;
    buf.writeln('<table>');
    buf.writeln('<thead><tr>');
    for (final col in table.columns) {
      buf.writeln('<th>${_escape(col.label)}</th>');
    }
    buf.writeln('</tr></thead><tbody>');
    for (final row in table.rows) {
      buf.writeln('<tr>');
      for (final cell in row.cells) {
        buf.writeln('<td>${_escape(cell)}</td>');
      }
      buf.writeln('</tr>');
    }
    buf.writeln('</tbody></table>');
  }

  void _renderFinding(StringBuffer buf, ReportFinding finding) {
    buf.writeln('<article class="finding">');
    buf.writeln(
      '<h3>${_escape(finding.code)} — ${_escape(finding.severity.wireName)}</h3>',
    );
    buf.writeln('<p>${_escape(finding.message)}</p>');
    if (finding.source != null) {
      buf.writeln('<p>Ficheiro: <code>${_escape(finding.source!)}</code></p>');
    }
    buf.writeln('</article>');
  }

  String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
