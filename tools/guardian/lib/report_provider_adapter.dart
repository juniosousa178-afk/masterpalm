import 'package:masterpalm_platform/masterpalm_platform.dart';

import 'models/guardian_result.dart';

/// Optional adapter for future migration from [ReportGenerator] to [ReportProvider].
///
/// Not wired into the Guardian CLI in Sprint 02.2 — legacy [ReportGenerator]
/// remains the production path until structural equivalence is validated.
class GuardianReportProviderAdapter {
  const GuardianReportProviderAdapter(this._reportProvider);

  final ReportProvider _reportProvider;

  Future<ReportResult> fromGuardianResult({
    required GuardianResult result,
    required String projectId,
    ReportFormat format = ReportFormat.markdown,
  }) {
    return _reportProvider.generate(
      ReportRequest(
        reportType: ReportType.guardianAnalysis,
        projectId: projectId,
        format: format,
        guardianAnalysis: result.toJson(),
      ),
    );
  }
}
