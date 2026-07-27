import '../models/report/report_document.dart';
import '../models/report/report_format.dart';
import '../models/report/report_request.dart';

/// Contract for engineering report generation through Platform Core.
abstract class ReportProvider {
  Future<ReportResult> generate(ReportRequest request);

  Future<String> render(
    ReportDocument document,
    ReportFormat format,
  );

  Set<ReportFormat> get supportedFormats;
}
