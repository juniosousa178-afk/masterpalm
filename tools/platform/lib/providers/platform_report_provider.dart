import '../interfaces/report_provider.dart';
import '../models/report/report_document.dart';
import '../models/report/report_format.dart';
import '../models/report/report_metadata.dart';
import '../models/report/report_request.dart';
import '../models/report/report_status.dart';
import '../report/report_engine.dart';
import '../report/report_exceptions.dart';
import '../models/report/report_type.dart';

/// Platform implementation of [ReportProvider] backed by [ReportEngine].
class PlatformReportProvider implements ReportProvider {
  PlatformReportProvider({required ReportEngine engine}) : _engine = engine;

  final ReportEngine _engine;

  @override
  Set<ReportFormat> get supportedFormats => _engine.supportedFormats;

  @override
  Future<ReportResult> generate(ReportRequest request) async {
    try {
      return await _engine.generate(request);
    } on ReportSourceException catch (e) {
      return ReportResult(
        status: ReportStatus.error,
        document: _emptyDocument(request),
        errors: [e.message],
        warnings: const [],
      );
    } on ReportException catch (e) {
      return ReportResult(
        status: ReportStatus.error,
        document: _emptyDocument(request),
        errors: [e.message],
        warnings: const [],
      );
    }
  }

  @override
  Future<String> render(ReportDocument document, ReportFormat format) {
    return Future.value(_engine.render(document, format));
  }

  ReportDocument _emptyDocument(ReportRequest request) {
    return ReportDocument(
      metadata: ReportMetadata(
        reportId:
            'report:${request.projectId}:${request.reportType.wireName}:error',
        reportType: request.reportType,
        reportSchemaVersion: ReportMetadata.currentSchemaVersion,
        projectId: request.projectId,
        generatorVersion: ReportMetadata.defaultGeneratorVersion,
      ),
      sections: const [],
    );
  }
}
