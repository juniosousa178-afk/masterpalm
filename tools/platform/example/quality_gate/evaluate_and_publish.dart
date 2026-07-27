// Example: evaluate and publish Quality Gate snapshot to the in-memory store.
//
// Run from tools/platform:
//   dart run example/quality_gate/evaluate_and_publish.dart

import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';

import '../../test/quality_gate/support/quality_gate_test_helpers.dart';

Future<void> main() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final request = await QualityGateTestHelpers.passingRequest();
  final result = await core.qualityGateAndPublish(request);
  final id = result.snapshot?.metadata.qualityGateSnapshotId;
  stdout.writeln('Published snapshot: $id');
}
