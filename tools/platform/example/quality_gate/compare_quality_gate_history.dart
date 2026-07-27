// Example: compare two Quality Gate snapshots via History mapper.
//
// Run from tools/platform:
//   dart run example/quality_gate/compare_quality_gate_history.dart

import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/history/mappers/quality_gate_history_mapper.dart';
import 'package:masterpalm_platform/models/history/history_change_type.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';

import '../../test/quality_gate/support/quality_gate_snapshot_fixtures.dart';
import '../../test/quality_gate/support/quality_gate_test_helpers.dart';

Future<void> main() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final before = (await core
          .qualityGateEvaluate(await QualityGateTestHelpers.passingRequest()))
      .snapshot!;
  final after = QualityGateSnapshotFixtures.minimal(
    id: before.metadata.qualityGateSnapshotId,
    fingerprint: before.metadata.qualityGateFingerprint,
    decision: QualityGateDecision.failed,
  );

  const mapper = QualityGateHistoryMapper();
  final changes = mapper.compare(before, after);
  stdout.writeln('History changes: ${changes.length}');
  for (final change in changes) {
    stdout.writeln('- ${change.subjectId}: ${change.changeType.wireName}');
  }
}
