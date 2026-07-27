// Example: evaluate Quality Gate with injected source artifacts (no publish).
//
// Run from tools/platform:
//   dart run example/quality_gate/evaluate_injected_sources.dart

import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';

import '../../test/quality_gate/support/quality_gate_test_helpers.dart';

Future<void> main() async {
  final core = PlatformBootstrap.forRepo(Directory.current.path);
  final request = await QualityGateTestHelpers.passingRequest();
  final result = await core.qualityGateEvaluate(request);

  final snapshot = result.snapshot;
  if (snapshot == null) {
    stderr.writeln('No snapshot produced (status=${result.status.wireName})');
    exit(1);
  }

  stdout.writeln('Policy: ${snapshot.metadata.policyId}');
  stdout.writeln('Decision: ${snapshot.decision.wireName}');
  stdout.writeln('Fingerprint: ${snapshot.metadata.qualityGateFingerprint}');
  stdout.writeln('QG011 status: '
      '${snapshot.evaluations.firstWhere((e) => e.ruleId == 'QG011').status.wireName}');
}
