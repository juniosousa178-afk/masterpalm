import 'package:masterpalm_platform/dashboard/builders/dashboard_section_context.dart';
import 'package:masterpalm_platform/dashboard/builders/quality_gate_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:test/test.dart';

import 'support/quality_gate_snapshot_fixtures.dart';

void main() {
  group('Dashboard × Quality Gate integration', () {
    test('section builder uses injected snapshot', () {
      final snapshot = QualityGateSnapshotFixtures.minimal(
        decision: QualityGateDecision.error,
      );
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
      expect(section.type, DashboardSectionType.qualityGate);
      expect(section.availability, DashboardAvailability.available);
      expect(
        section.widgets.any((w) => w.widgetId == 'qualityGate.decision'),
        isTrue,
      );
    });

    test('missing snapshot yields unavailable section', () {
      const builder = QualityGateSectionBuilder();
      final section = builder.build(
        DashboardSectionBuildContext(
          request: DashboardRequest(
            projectId: 'demo-project',
            createdAt: '2026-01-01T00:00:00.000Z',
            referenceTime: '2026-01-01T00:00:01.000Z',
            includeUnavailable: true,
          ),
          sources: DashboardResolvedSources(),
          compatibility: DashboardCompatibility.unknown,
          freshness: DashboardFreshness.unknown,
        ),
      );
      expect(section.availability, DashboardAvailability.unavailable);
    });

    test('foundation registry registers quality gate builder', () {
      final registry = DashboardRegistry();
      DashboardRegistry.registerFoundation(registry);
      expect(
        registry.builders
            .map((b) => b.sectionType)
            .contains(DashboardSectionType.qualityGate),
        isTrue,
      );
    });
  });
}
