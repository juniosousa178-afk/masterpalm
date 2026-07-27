// Example: generate a Quality Gate report from an evaluated snapshot.
//
// Run from tools/platform:
//   dart run example/quality_gate/generate_quality_gate_report.dart

import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';

import '../../test/quality_gate/support/quality_gate_test_helpers.dart';

Future<void> main() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final evaluation = await core
      .qualityGateEvaluate(await QualityGateTestHelpers.passingRequest());
  final snapshot = evaluation.snapshot;
  if (snapshot == null) {
    stderr.writeln('Evaluation did not produce a snapshot.');
    exit(1);
  }

  final report = await ReportEngine().generate(
    ReportRequest(
      reportType: ReportType.qualityGate,
      projectId: snapshot.metadata.projectId,
      qualityGateSnapshot: snapshot.toJson(),
    ),
  );

  stdout.writeln('Report: ${report.document.metadata.reportId}');
  stdout.writeln('Sections: ${report.document.sections.length}');
}
