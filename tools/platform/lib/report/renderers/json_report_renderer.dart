import 'dart:convert';

import '../../models/report/report_document.dart';
import '../../models/report/report_format.dart';
import 'report_renderer.dart';

/// JSON renderer with stable round-trip support.
class JsonReportRenderer implements ReportRenderer {
  const JsonReportRenderer();

  @override
  ReportFormat get format => ReportFormat.json;

  @override
  String render(ReportDocument document) {
    return const JsonEncoder.withIndent('  ').convert(document.toJson());
  }
}
