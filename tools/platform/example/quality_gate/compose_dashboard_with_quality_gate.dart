// Example: compose dashboard section from injected Quality Gate snapshot.
//
// Run from tools/platform:
//   dart run example/quality_gate/compose_dashboard_with_quality_gate.dart

import 'package:masterpalm_platform/dashboard/builders/dashboard_section_context.dart';
import 'package:masterpalm_platform/dashboard/builders/quality_gate_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';

import '../../test/quality_gate/support/quality_gate_snapshot_fixtures.dart';

void main() {
  final snapshot = QualityGateSnapshotFixtures.minimal();
  const builder = QualityGateSectionBuilder();
  final section = builder.build(
    DashboardSectionBuildContext(
      request: DashboardRequest(
        projectId: snapshot.metadata.projectId,
        createdAt: '2026-01-01T00:00:00.000Z',
        referenceTime: '2026-01-01T00:00:01.000Z',
        qualityGateSnapshot: snapshot,
      ),
      sources: DashboardResolvedSources(qualityGate: snapshot),
      compatibility: DashboardCompatibility.compatible,
      freshness: DashboardFreshness.current,
    ),
  );

  // ignore: avoid_print
  print(
      'Dashboard section ${section.type.wireName} widgets=${section.widgets.length}');
}
