import 'package:masterpalm_platform/history/mappers/persistent_artifact_history_mapper.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact cross-module audit', () {
    test('provider output is consumable by report engine', () async {
      final evaluation = await evaluatePassingSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.persistentArtifacts,
          projectId: evaluation.projectId,
          persistentArtifactSnapshot: evaluation.snapshot!.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
    });

    test('provider output is consumable by history mapper', () async {
      final evaluation = await evaluatePassingSnapshot();
      final artifact = const PersistentArtifactHistoryMapper().fromMap(
        evaluation.snapshot!.toJson(),
      );
      expect(artifact.fingerprint, isNotEmpty);
      expect(artifact.artifactId, isNotEmpty);
    });

    test('platform core exposes persistent artifact provider', () {
      final registry = ProviderRegistry()
        ..registerInstance<PersistentArtifactProvider>(
            createTestStack().provider);
      final core = PlatformCore(
        config: PlatformConfig.forRepo('.'),
        registry: registry,
      );
      expect(core.persistentArtifacts(), isA<PersistentArtifactProvider>());
    });
  });
}
