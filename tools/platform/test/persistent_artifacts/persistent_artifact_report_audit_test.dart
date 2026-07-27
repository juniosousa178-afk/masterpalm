import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact report audit', () {
    test('report type declares persistentArtifacts', () {
      expect(
          ReportType.values.contains(ReportType.persistentArtifacts), isTrue);
    });

    test('report engine builds document from persistent artifact snapshot',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.persistentArtifacts,
          projectId: snapshot.projectId,
          persistentArtifactSnapshot: snapshot.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
      expect(report.document.metadata.projectId, snapshot.projectId);
    });

    test('report metadata remains deterministic for same snapshot', () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final engine = ReportEngine();
      final first = await engine.generate(
        ReportRequest(
          reportType: ReportType.persistentArtifacts,
          projectId: snapshot.projectId,
          persistentArtifactSnapshot: snapshot.toJson(),
        ),
      );
      final second = await engine.generate(
        ReportRequest(
          reportType: ReportType.persistentArtifacts,
          projectId: snapshot.projectId,
          persistentArtifactSnapshot: snapshot.toJson(),
        ),
      );
      expect(first.document.metadata.reportType,
          second.document.metadata.reportType);
      expect(first.document.metadata.projectId,
          second.document.metadata.projectId);
    });
  });
}
