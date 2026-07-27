import '../../interfaces/report_provider.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/report/report_document.dart';
import '../../models/report/report_format.dart';
import '../../models/report/report_request.dart';
import 'telemetry_instrumentation.dart';

/// Observable decorator for [ReportProvider].
class ObservableReportProvider implements ReportProvider {
  ObservableReportProvider({
    required ReportProvider delegate,
    required TelemetryInstrumentation instrumentation,
  })  : _delegate = delegate,
        _instrumentation = instrumentation;

  final ReportProvider _delegate;
  final TelemetryInstrumentation _instrumentation;

  @override
  Set<ReportFormat> get supportedFormats => _delegate.supportedFormats;

  @override
  Future<ReportResult> generate(ReportRequest request) {
    return _instrumentation.observe(
      component: TelemetryComponent.report,
      operation: TelemetryOperation.generate,
      projectId: request.projectId,
      action: () => _delegate.generate(request),
      resultingArtifactIds: (result) => [result.document.metadata.reportId],
    );
  }

  @override
  Future<String> render(ReportDocument document, ReportFormat format) {
    return _instrumentation.observe(
      component: TelemetryComponent.report,
      operation: TelemetryOperation.compose,
      projectId: document.metadata.projectId,
      action: () => _delegate.render(document, format),
    );
  }
}
