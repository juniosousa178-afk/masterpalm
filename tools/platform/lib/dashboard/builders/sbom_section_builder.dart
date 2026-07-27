import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard SBOM section from optional injected snapshot.
///
/// Consumes published snapshot only — never executes evaluate.
class SbomSectionBuilder implements DashboardSectionBuilder {
  const SbomSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.sbom;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.releaseSupplyChain ??
        context.request.releaseSupplyChainSnapshot;
    final sbom = snapshot?.sbom;
    if (snapshot == null || sbom == null) {
      return buildSection(
        type: sectionType,
        title: 'SBOM',
        order: 150,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('sbom.status', 'SBOM')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['SBOM unavailable in supply chain snapshot'],
      );
    }

    final meta = sbom.metadata;
    return buildSection(
      type: sectionType,
      title: 'SBOM',
      order: 150,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'sbom.status',
          title: 'Status',
          status: meta.status.wireName,
        ),
        statusWidget(
          widgetId: 'sbom.id',
          title: 'SBOM ID',
          status: meta.sbomId,
          order: 1,
        ),
        scalarWidget(
          widgetId: 'sbom.component-count',
          title: 'Components',
          value: meta.componentCount.toDouble(),
          order: 2,
        ),
        scalarWidget(
          widgetId: 'sbom.dependency-count',
          title: 'Dependencies',
          value: meta.dependencyCount.toDouble(),
          order: 3,
        ),
        statusWidget(
          widgetId: 'sbom.release',
          title: 'Release',
          status: '${meta.releaseId ?? '-'}@${meta.commitId ?? '-'}',
          order: 4,
        ),
      ],
      limitations: [
        ...meta.limitations,
        ...sbom.limitations,
        ...snapshot.limitations,
      ],
    );
  }
}
