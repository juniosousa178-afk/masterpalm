// Example: evaluate and publish a release governance snapshot.
//
// Run from tools/platform:
//   dart run example/release_governance/evaluate_and_publish_release.dart

import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';

import '../../test/release_governance/support/release_governance_test_fixtures.dart';

Future<void> main() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final result = await core.releaseGovernanceAndPublish(
    ReleaseGovernanceTestFixtures.passingRequest(publish: true),
  );
  final snapshot = result.snapshot;
  if (snapshot == null) {
    stderr.writeln('Evaluation did not produce a snapshot.');
    exit(1);
  }
  stdout.writeln('Published snapshot: ${snapshot.metadata.snapshotId}');
  stdout.writeln('Publication: ${result.publicationStatus ?? 'n/a'}');
  stdout.writeln('Decision: ${snapshot.decision.wireName}');
}
