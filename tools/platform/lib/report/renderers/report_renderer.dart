import '../../models/report/report_document.dart';
import '../../models/report/report_format.dart';

/// Transforms a [ReportDocument] into a final string representation.
abstract class ReportRenderer {
  ReportFormat get format;

  String render(ReportDocument document);
}
