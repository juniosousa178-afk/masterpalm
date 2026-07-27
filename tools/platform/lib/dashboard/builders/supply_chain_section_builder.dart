import '../../models/dashboard/dashboard_enums.dart';
import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/release_supply_chain/release_supply_chain_enums.dart';
import 'dashboard_section_context.dart';
import 'dashboard_widget_helpers.dart';

/// Builds dashboard supply chain section from optional injected snapshot.
///
/// Consumes published snapshot only — never executes evaluate.
class SupplyChainSectionBuilder implements DashboardSectionBuilder {
  const SupplyChainSectionBuilder();

  @override
  DashboardSectionType get sectionType => DashboardSectionType.supplyChain;

  @override
  DashboardSection build(DashboardSectionBuildContext context) {
    final snapshot = context.sources.releaseSupplyChain ??
        context.request.releaseSupplyChainSnapshot;
    final supplyChain = snapshot?.supplyChain;
    if (snapshot == null || supplyChain == null) {
      return buildSection(
        type: sectionType,
        title: 'Supply Chain',
        order: 140,
        widgets: context.request.includeUnavailable
            ? [unavailableWidget('supplyChain.status', 'Supply Chain')]
            : [],
        availability: DashboardAvailability.unavailable,
        limitations: const ['Supply chain snapshot unavailable'],
      );
    }

    final meta = snapshot.metadata;
    return buildSection(
      type: sectionType,
      title: 'Supply Chain',
      order: 140,
      availability: DashboardAvailability.available,
      widgets: [
        statusWidget(
          widgetId: 'supplyChain.status',
          title: 'Status',
          status: supplyChain.status.wireName,
        ),
        statusWidget(
          widgetId: 'supplyChain.release',
          title: 'Release',
          status: '${meta.releaseId ?? '-'}@${meta.commitId ?? '-'}',
          order: 1,
        ),
        scalarWidget(
          widgetId: 'supplyChain.stage-count',
          title: 'Stages',
          value: supplyChain.stages.length.toDouble(),
          order: 2,
        ),
        scalarWidget(
          widgetId: 'supplyChain.node-count',
          title: 'Nodes',
          value: supplyChain.nodes.length.toDouble(),
          order: 3,
        ),
        scalarWidget(
          widgetId: 'supplyChain.edge-count',
          title: 'Edges',
          value: supplyChain.edges.length.toDouble(),
          order: 4,
        ),
        scalarWidget(
          widgetId: 'supplyChain.evidence-count',
          title: 'Evidence',
          value: supplyChain.evidence.length.toDouble(),
          order: 5,
        ),
        statusWidget(
          widgetId: 'supplyChain.policy',
          title: 'Policy',
          status:
              '${meta.supplyChainPolicyId}@${meta.supplyChainPolicyVersion}',
          order: 6,
        ),
        statusWidget(
          widgetId: 'supplyChain.releaseEvidence',
          title: 'Release Evidence ref',
          status: meta.releaseEvidenceBundleId ?? '-',
          order: 7,
        ),
      ],
      limitations: [
        ...meta.limitations,
        ...supplyChain.limitations,
        ...snapshot.limitations,
      ],
    );
  }
}
