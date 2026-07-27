import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import 'builders/architecture_section_builder.dart';
import 'builders/compatibility_section_builder.dart'
    show
        CompatibilitySectionBuilder,
        SourcesSectionBuilder,
        LimitationsSectionBuilder;
import 'builders/coverage_section_builder.dart';
import 'builders/dashboard_section_context.dart';
import 'builders/guardian_section_builder.dart';
import 'builders/history_section_builder.dart';
import 'builders/mes_section_builder.dart';
import 'builders/metrics_section_builder.dart';
import 'builders/observability_section_builder.dart';
import 'builders/quality_gate_section_builder.dart';
import 'builders/release_governance_section_builder.dart';
import 'builders/release_evidence_section_builder.dart';
import 'builders/supply_chain_section_builder.dart';
import 'builders/sbom_section_builder.dart';
import 'builders/compliance_section_builder.dart';
import 'builders/cicd_pipeline_section_builder.dart';
import 'builders/cicd_execution_section_builder.dart';
import 'builders/cicd_deployment_section_builder.dart';
import 'builders/cryptographic_trust_section_builders.dart';
import 'builders/persistent_artifact_section_builders.dart';
import 'builders/overview_section_builder.dart';
import 'builders/score_section_builder.dart';
import 'dashboard_exceptions.dart';

export 'builders/dashboard_section_context.dart' show DashboardSectionBuilder;

/// Registry of dashboard section builders and layouts.
class DashboardRegistry {
  final Map<DashboardSectionType, DashboardSectionBuilder> _builders = {};
  final Map<String, DashboardLayout> _layouts = {};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void registerBuilder(DashboardSectionBuilder builder) {
    if (_frozen) {
      throw DashboardRegistryException('Dashboard registry is frozen');
    }
    if (_builders.containsKey(builder.sectionType)) {
      throw DashboardRegistryException(
        'Duplicate section builder: ${builder.sectionType.wireName}',
      );
    }
    _builders[builder.sectionType] = builder;
  }

  void registerLayout(DashboardLayout layout) {
    if (_frozen) {
      throw DashboardRegistryException('Dashboard registry is frozen');
    }
    if (_layouts.containsKey(layout.layoutId)) {
      throw DashboardRegistryException(
        'Duplicate layout: ${layout.layoutId}',
      );
    }
    _layouts[layout.layoutId] = layout;
  }

  void freeze() => _frozen = true;

  List<DashboardSectionBuilder> get builders {
    final list = _builders.values.toList()
      ..sort(
          (a, b) => a.sectionType.wireName.compareTo(b.sectionType.wireName));
    return list;
  }

  DashboardLayout layout(String layoutId) {
    return _layouts[layoutId] ?? foundationLayoutV1;
  }

  static DashboardLayout get foundationLayoutV1 => const DashboardLayout(
        layoutId: 'dashboard-foundation-v1',
        version: 1,
        sectionOrder: [
          'overview',
          'mes',
          'score',
          'metrics',
          'history',
          'guardian',
          'architecture',
          'coverage',
          'compatibility',
          'sources',
          'limitations',
        ],
        items: [
          DashboardLayoutItem(sectionId: 'overview', order: 0),
          DashboardLayoutItem(sectionId: 'mes', order: 10),
          DashboardLayoutItem(sectionId: 'score', order: 20),
          DashboardLayoutItem(sectionId: 'metrics', order: 30),
          DashboardLayoutItem(sectionId: 'history', order: 40),
          DashboardLayoutItem(sectionId: 'guardian', order: 50),
          DashboardLayoutItem(sectionId: 'architecture', order: 60),
          DashboardLayoutItem(sectionId: 'coverage', order: 70),
          DashboardLayoutItem(sectionId: 'compatibility', order: 80),
          DashboardLayoutItem(sectionId: 'sources', order: 90),
          DashboardLayoutItem(sectionId: 'limitations', order: 100),
        ],
      );

  static void registerFoundation(DashboardRegistry registry) {
    registry.registerBuilder(const OverviewSectionBuilder());
    registry.registerBuilder(const MesSectionBuilder());
    registry.registerBuilder(const ScoreSectionBuilder());
    registry.registerBuilder(const MetricsSectionBuilder());
    registry.registerBuilder(const HistorySectionBuilder());
    registry.registerBuilder(const GuardianSectionBuilder());
    registry.registerBuilder(const ArchitectureSectionBuilder());
    registry.registerBuilder(const CoverageSectionBuilder());
    registry.registerBuilder(const CompatibilitySectionBuilder());
    registry.registerBuilder(const SourcesSectionBuilder());
    registry.registerBuilder(const LimitationsSectionBuilder());
    registry.registerBuilder(const ObservabilitySectionBuilder());
    registry.registerBuilder(const QualityGateSectionBuilder());
    registry.registerBuilder(const ReleaseGovernanceSectionBuilder());
    registry.registerBuilder(const ReleaseEvidenceSectionBuilder());
    registry.registerBuilder(const SupplyChainSectionBuilder());
    registry.registerBuilder(const SbomSectionBuilder());
    registry.registerBuilder(const ComplianceSectionBuilder());
    registry.registerBuilder(const CicdPipelineSectionBuilder());
    registry.registerBuilder(const CicdExecutionSectionBuilder());
    registry.registerBuilder(const CicdDeploymentSectionBuilder());
    registry.registerBuilder(const CryptographicTrustSummarySectionBuilder());
    registry
        .registerBuilder(const CryptographicTrustSignaturesSectionBuilder());
    registry
        .registerBuilder(const CryptographicTrustAttestationsSectionBuilder());
    registry.registerBuilder(const CryptographicTrustChainsSectionBuilder());
    registry.registerBuilder(
      const CryptographicTrustPolicyEvaluationSectionBuilder(),
    );
    registry
        .registerBuilder(const CryptographicTrustRevocationSectionBuilder());
    registry
        .registerBuilder(const CryptographicTrustTransparencySectionBuilder());
    registry.registerBuilder(const PersistentArtifactsSummarySectionBuilder());
    registry.registerLayout(foundationLayoutV1);
    registry.freeze();
  }
}
