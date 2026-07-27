// Example: generate a Release Governance report from an evaluated snapshot.
//
// Run from tools/platform:
//   dart run example/release_governance/generate_release_report.dart

import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../../test/release_governance/support/release_governance_test_fixtures.dart';

Future<void> main() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final evaluation = await core.releaseGovernanceEvaluate(
    ReleaseGovernanceTestFixtures.passingRequest(),
  );
  final snapshot = evaluation.snapshot;
  if (snapshot == null) {
    stderr.writeln('Evaluation did not produce a snapshot.');
    exit(1);
  }

  final report = await core.report().generate(
    ReportRequest(
      reportType: ReportType.releaseGovernance,
      projectId: snapshot.metadata.projectId,
      releaseDecisionSnapshot: snapshot.toJson(),
    ),
  );

  stdout.writeln('Report: ${report.document.metadata.reportId}');
  stdout.writeln('Sections: ${report.document.sections.length}');
  stdout.writeln('Status: ${report.status.wireName}');
}
