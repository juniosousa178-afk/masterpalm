import 'dart:convert';

import '../models/graph/project_graph.dart';
import '../models/history/history_artifact.dart';
import '../models/history/history_artifact_type.dart';
import '../models/history/history_change_type.dart';
import '../models/history/history_compatibility.dart';
import '../models/history/history_diff.dart';
import '../models/history/history_snapshot.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import '../models/metrics/metric_availability.dart';
import '../models/metrics/metric_unit.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/metrics/metric_record.dart';
import '../models/metrics/metric_value.dart';
import '../models/report/report_document.dart';
import '../models/report/report_severity.dart';
import '../models/report/report_block.dart';
import '../models/report/report_finding.dart';
import '../models/report/report_section.dart';
import '../models/observability/telemetry_snapshot.dart';
import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import '../observability/telemetry_history_mapper.dart';
import 'mappers/quality_gate_history_mapper.dart';
import 'mappers/release_governance_history_mapper.dart';
import 'mappers/release_evidence_history_mapper.dart';
import 'mappers/release_supply_chain_history_mapper.dart';
import 'mappers/cicd_integration_history_mapper.dart';
import 'mappers/cryptographic_trust_history_mapper.dart';
import 'mappers/persistent_artifact_history_mapper.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_supply_chain/release_supply_chain_snapshot.dart';
import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import 'history_compatibility_checker.dart';

/// Produces neutral structural diffs between history snapshots.
class HistoryComparator {
  const HistoryComparator({
    HistoryCompatibilityChecker? compatibilityChecker,
  }) : _compatibilityChecker =
            compatibilityChecker ?? const HistoryCompatibilityChecker();

  final HistoryCompatibilityChecker _compatibilityChecker;

  HistoryDiff compare(HistorySnapshot from, HistorySnapshot to) {
    final changes = <HistoryChange>[];
    final warnings = <String>[];
    final compatibilities = <HistoryCompatibility>[];

    final fromByType = _indexByType(from.artifacts);
    final toByType = _indexByType(to.artifacts);
    final allTypes = {...fromByType.keys, ...toByType.keys}.toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));

    for (final type in allTypes) {
      final fromArtifact = fromByType[type];
      final toArtifact = toByType[type];

      if (fromArtifact == null && toArtifact != null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.artifactAdded,
            category: HistoryChangeCategory.artifact,
            subjectId: toArtifact.artifactId,
            description: 'Artifact ${type.wireName} added',
          ),
        );
        _compareArtifactDetail(
            null, toArtifact, changes, warnings, compatibilities);
        continue;
      }
      if (fromArtifact != null && toArtifact == null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.artifactRemoved,
            category: HistoryChangeCategory.artifact,
            subjectId: fromArtifact.artifactId,
            description: 'Artifact ${type.wireName} removed',
          ),
        );
        continue;
      }
      if (fromArtifact != null && toArtifact != null) {
        final compatibility =
            _compatibilityChecker.betweenSameType(fromArtifact, toArtifact);
        compatibilities.add(compatibility);

        if (fromArtifact.fingerprint == toArtifact.fingerprint) {
          changes.add(
            HistoryChange(
              changeType: HistoryChangeType.artifactUnchanged,
              category: HistoryChangeCategory.artifact,
              subjectId: fromArtifact.artifactId,
            ),
          );
        } else {
          changes.add(
            HistoryChange(
              changeType: HistoryChangeType.artifactChanged,
              category: HistoryChangeCategory.artifact,
              subjectId: fromArtifact.artifactId,
              description: 'Artifact ${type.wireName} changed',
              metadata: {
                'compatibility': compatibility.status.wireName,
              },
            ),
          );
          _compareArtifactDetail(
            fromArtifact,
            toArtifact,
            changes,
            warnings,
            compatibilities,
            compatibility: compatibility,
          );
        }
      }
    }

    final compatibility = _compatibilityChecker.merge(compatibilities);
    changes.sort((a, b) {
      final typeCmp = a.changeType.wireName.compareTo(b.changeType.wireName);
      if (typeCmp != 0) return typeCmp;
      return a.subjectId.compareTo(b.subjectId);
    });

    return HistoryDiff(
      fromSnapshotId: from.metadata.historySnapshotId,
      toSnapshotId: to.metadata.historySnapshotId,
      compatibility: compatibility,
      changes: changes,
      summary: _summarize(changes),
      warnings: warnings,
      comparedArtifactTypes: allTypes.map((t) => t.wireName).toList(),
    );
  }

  void _compareArtifactDetail(
    HistoryArtifact? from,
    HistoryArtifact? to,
    List<HistoryChange> changes,
    List<String> warnings,
    List<HistoryCompatibility> compatibilities, {
    HistoryCompatibility? compatibility,
  }) {
    final artifact = to ?? from;
    if (artifact == null) return;

    switch (artifact.artifactType) {
      case HistoryArtifactType.metrics:
        if (from != null &&
            to != null &&
            _compatibilityChecker.supportsComparison(
              compatibility ??
                  const HistoryCompatibility(
                      status: HistoryCompatibilityStatus.compatible),
            )) {
          _compareMetrics(from, to, changes, warnings);
        }
      case HistoryArtifactType.graph:
        if (from != null &&
            to != null &&
            _compatibilityChecker.supportsComparison(
              compatibility ??
                  const HistoryCompatibility(
                      status: HistoryCompatibilityStatus.compatible),
            )) {
          _compareGraph(from, to, changes);
        } else if (from == null || to == null) {
          // handled at artifact level
        } else {
          warnings.add(
              'Graph detail comparison unavailable due to incompatibility');
        }
      case HistoryArtifactType.guardian:
        if (from != null && to != null) {
          _compareGuardian(from, to, changes);
        }
      case HistoryArtifactType.report:
        if (from != null && to != null) {
          _compareReport(from, to, changes);
        }
      case HistoryArtifactType.ast:
        if (from != null && to != null) {
          _compareAst(from, to, changes);
        }
      case HistoryArtifactType.mes:
        if (from != null && to != null) {
          _compareMes(from, to, changes);
        }
      case HistoryArtifactType.dashboard:
        if (from != null && to != null) {
          _compareDashboard(from, to, changes);
        }
      case HistoryArtifactType.telemetry:
        if (from != null && to != null) {
          _compareTelemetry(from, to, changes);
        }
      case HistoryArtifactType.qualityGate:
        if (from != null && to != null) {
          _compareQualityGate(from, to, changes);
        }
      case HistoryArtifactType.releaseGovernance:
        if (from != null && to != null) {
          _compareReleaseGovernance(from, to, changes);
        }
      case HistoryArtifactType.releaseEvidence:
        if (from != null && to != null) {
          _compareReleaseEvidence(from, to, changes);
        }
      case HistoryArtifactType.releaseSupplyChain:
        if (from != null && to != null) {
          _compareReleaseSupplyChain(from, to, changes);
        }
      case HistoryArtifactType.cicdIntegration:
        if (from != null && to != null) {
          _compareCicdIntegration(from, to, changes);
        }
      case HistoryArtifactType.cryptographicTrust:
        if (from != null && to != null) {
          _compareCryptographicTrust(from, to, changes);
        }
      case HistoryArtifactType.persistentArtifacts:
        if (from != null && to != null) {
          _comparePersistentArtifacts(from, to, changes);
        }
    }
  }

  void _compareMetrics(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
    List<String> warnings,
  ) {
    final fromSnapshot = MetricsSnapshot.fromJson(from.payload.data);
    final toSnapshot = MetricsSnapshot.fromJson(to.payload.data);
    final fromById = {
      for (final m in fromSnapshot.metrics) m.definition.id: m,
    };
    final toById = {
      for (final m in toSnapshot.metrics) m.definition.id: m,
    };
    final allIds = {...fromById.keys, ...toById.keys}.toList()..sort();

    for (final id in allIds) {
      final fromMetric = fromById[id];
      final toMetric = toById[id];
      if (fromMetric == null && toMetric != null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricAdded,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
          ),
        );
        continue;
      }
      if (fromMetric != null && toMetric == null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricRemoved,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
          ),
        );
        continue;
      }
      if (fromMetric == null || toMetric == null) continue;

      final calcCompatible = fromMetric.definition.calculationVersion ==
          toMetric.definition.calculationVersion;
      if (!calcCompatible) {
        warnings.add(
          'Metric $id has incompatible calculationVersion; value delta skipped',
        );
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricValueChanged,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
            description: 'calculationVersion changed',
            previousValue: fromMetric.definition.calculationVersion.toString(),
            currentValue: toMetric.definition.calculationVersion.toString(),
            metadata: {'compatible': 'false'},
          ),
        );
        continue;
      }

      if (fromMetric.availability != toMetric.availability) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricValueChanged,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
            description: 'availability changed',
            previousValue: fromMetric.availability.wireName,
            currentValue: toMetric.availability.wireName,
          ),
        );
      }
      if (fromMetric.definition.unit != toMetric.definition.unit) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricValueChanged,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
            description: 'unit changed',
            previousValue: fromMetric.definition.unit.wireName,
            currentValue: toMetric.definition.unit.wireName,
          ),
        );
      }
      if (jsonEncode(fromMetric.definition.toJson()) !=
          jsonEncode(toMetric.definition.toJson())) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricValueChanged,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
            description: 'definition changed',
          ),
        );
      }

      final fromNum = _numericValue(fromMetric);
      final toNum = _numericValue(toMetric);
      if (fromNum != null && toNum != null && fromNum != toNum) {
        final absoluteDelta = toNum - fromNum;
        double? relativeDelta;
        if (fromNum != 0 &&
            fromMetric.definition.unit == toMetric.definition.unit) {
          relativeDelta = absoluteDelta / fromNum.abs();
        }
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricValueChanged,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
            previousValue: fromNum.toString(),
            currentValue: toNum.toString(),
            absoluteDelta: absoluteDelta,
            relativeDelta: relativeDelta,
          ),
        );
      } else if (jsonEncode(fromMetric.value?.toJson()) !=
          jsonEncode(toMetric.value?.toJson())) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.metricValueChanged,
            category: HistoryChangeCategory.metrics,
            subjectId: id,
            previousValue: fromMetric.value?.toJson().toString(),
            currentValue: toMetric.value?.toJson().toString(),
          ),
        );
      }
    }
  }

  void _compareGraph(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final fromGraph = ProjectGraph.fromJson(from.payload.data);
    final toGraph = ProjectGraph.fromJson(to.payload.data);
    final fromNodes = {for (final n in fromGraph.nodes) n.id: n};
    final toNodes = {for (final n in toGraph.nodes) n.id: n};
    final allNodeIds = {...fromNodes.keys, ...toNodes.keys}.toList()..sort();

    for (final id in allNodeIds) {
      final fromNode = fromNodes[id];
      final toNode = toNodes[id];
      if (fromNode == null && toNode != null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.graphNodeAdded,
            category: HistoryChangeCategory.graph,
            subjectId: id,
          ),
        );
      } else if (fromNode != null && toNode == null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.graphNodeRemoved,
            category: HistoryChangeCategory.graph,
            subjectId: id,
          ),
        );
      } else if (fromNode != null && toNode != null) {
        if (jsonEncode(fromNode.toJson()) != jsonEncode(toNode.toJson())) {
          changes.add(
            HistoryChange(
              changeType: HistoryChangeType.graphNodeAdded,
              category: HistoryChangeCategory.graph,
              subjectId: id,
              description: 'node metadata changed',
            ),
          );
        }
      }
    }

    final fromEdges = {for (final e in fromGraph.edges) e.dedupeKey: e};
    final toEdges = {for (final e in toGraph.edges) e.dedupeKey: e};
    final allEdgeKeys = {...fromEdges.keys, ...toEdges.keys}.toList()..sort();

    for (final key in allEdgeKeys) {
      final fromEdge = fromEdges[key];
      final toEdge = toEdges[key];
      if (fromEdge == null && toEdge != null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.graphEdgeAdded,
            category: HistoryChangeCategory.graph,
            subjectId: key,
          ),
        );
      } else if (fromEdge != null && toEdge == null) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.graphEdgeRemoved,
            category: HistoryChangeCategory.graph,
            subjectId: key,
          ),
        );
      } else if (fromEdge != null &&
          toEdge != null &&
          jsonEncode(fromEdge.metadata) != jsonEncode(toEdge.metadata)) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.graphEdgeAdded,
            category: HistoryChangeCategory.graph,
            subjectId: key,
            description: 'edge context changed',
          ),
        );
      }
    }
  }

  void _compareGuardian(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final fromMap = from.payload.data;
    final toMap = to.payload.data;
    final fromDecision = fromMap['decision']?.toString();
    final toDecision = toMap['decision']?.toString();
    if (fromDecision != toDecision) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.guardianDecisionChanged,
          category: HistoryChangeCategory.guardian,
          subjectId: 'decision',
          previousValue: fromDecision,
          currentValue: toDecision,
        ),
      );
    }

    final fromViolations = _violationKeys(fromMap);
    final toViolations = _violationKeys(toMap);
    for (final key in toViolations.difference(fromViolations)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.guardianViolationAdded,
          category: HistoryChangeCategory.guardian,
          subjectId: key,
        ),
      );
    }
    for (final key in fromViolations.difference(toViolations)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.guardianViolationRemoved,
          category: HistoryChangeCategory.guardian,
          subjectId: key,
        ),
      );
    }
  }

  void _compareReport(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final fromDoc = ReportDocument.fromJson(from.payload.data);
    final toDoc = ReportDocument.fromJson(to.payload.data);

    if (fromDoc.metadata.reportSchemaVersion !=
        toDoc.metadata.reportSchemaVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.reportSectionAdded,
          category: HistoryChangeCategory.report,
          subjectId: 'metadata:reportSchemaVersion',
          previousValue: fromDoc.metadata.reportSchemaVersion.toString(),
          currentValue: toDoc.metadata.reportSchemaVersion.toString(),
          description: 'schema metadata changed',
        ),
      );
    }

    final fromSections = {for (final s in fromDoc.sections) s.id: s};
    final toSections = {for (final s in toDoc.sections) s.id: s};
    final fromSectionIds = fromSections.keys.toSet();
    final toSectionIds = toSections.keys.toSet();
    for (final id in toSectionIds.difference(fromSectionIds)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.reportSectionAdded,
          category: HistoryChangeCategory.report,
          subjectId: id,
        ),
      );
    }
    for (final id in fromSectionIds.difference(toSectionIds)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.reportSectionRemoved,
          category: HistoryChangeCategory.report,
          subjectId: id,
        ),
      );
    }

    for (final id in fromSectionIds.intersection(toSectionIds)) {
      final fromSection = fromSections[id]!;
      final toSection = toSections[id]!;
      _compareFindings(fromSection, toSection, changes);
    }
  }

  void _compareFindings(
    ReportSection from,
    ReportSection to,
    List<HistoryChange> changes,
  ) {
    final fromFindings = _findingKeys(from);
    final toFindings = _findingKeys(to);
    for (final key in toFindings.difference(fromFindings)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.reportSectionAdded,
          category: HistoryChangeCategory.report,
          subjectId: '${to.id}:finding:$key',
          description: 'finding added',
        ),
      );
    }
    for (final key in fromFindings.difference(toFindings)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.reportSectionRemoved,
          category: HistoryChangeCategory.report,
          subjectId: '${from.id}:finding:$key',
          description: 'finding removed',
        ),
      );
    }
  }

  void _compareAst(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final fromMetrics =
        from.payload.data['metrics'] as Map<String, dynamic>? ?? {};
    final toMetrics = to.payload.data['metrics'] as Map<String, dynamic>? ?? {};
    if (jsonEncode(fromMetrics) != jsonEncode(toMetrics)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.astSummaryChanged,
          category: HistoryChangeCategory.ast,
          subjectId: 'metrics',
        ),
      );
    }
    final fromMeta = from.payload.data['meta'] as Map<String, dynamic>? ?? {};
    final toMeta = to.payload.data['meta'] as Map<String, dynamic>? ?? {};
    if (jsonEncode(fromMeta) != jsonEncode(toMeta)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.astSummaryChanged,
          category: HistoryChangeCategory.ast,
          subjectId: 'meta',
        ),
      );
    }
  }

  void _compareMes(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final fromSnap = MESSnapshot.fromJson(from.payload.data);
    final toSnap = MESSnapshot.fromJson(to.payload.data);

    if (fromSnap.mesValue.value != toSnap.mesValue.value) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.metricValueChanged,
          category: HistoryChangeCategory.metrics,
          subjectId: 'mes.value',
          absoluteDelta: toSnap.mesValue.value - fromSnap.mesValue.value,
        ),
      );
    }
    if (fromSnap.eligibility.status != toSnap.eligibility.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.compatibility,
          subjectId: 'mes.eligibility',
        ),
      );
    }
    if (fromSnap.band?.bandId != toSnap.band?.bandId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.compatibility,
          subjectId: 'mes.band',
        ),
      );
    }
    if (fromSnap.metadata.policyVersion != toSnap.metadata.policyVersion) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.compatibility,
          subjectId: 'mes.policyVersion',
        ),
      );
    }
    if (fromSnap.coverage.policyCoverage != toSnap.coverage.policyCoverage) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.metricValueChanged,
          category: HistoryChangeCategory.metrics,
          subjectId: 'mes.coverage',
          absoluteDelta:
              toSnap.coverage.policyCoverage - fromSnap.coverage.policyCoverage,
        ),
      );
    }
  }

  void _compareDashboard(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final fromSnap = DashboardSnapshot.fromJson(from.payload.data);
    final toSnap = DashboardSnapshot.fromJson(to.payload.data);

    if (fromSnap.metadata.status != toSnap.metadata.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'dashboard.status',
        ),
      );
    }

    final fromSections = fromSnap.sections.map((s) => s.sectionId).toSet();
    final toSections = toSnap.sections.map((s) => s.sectionId).toSet();
    for (final id in toSections.difference(fromSections)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactAdded,
          category: HistoryChangeCategory.artifact,
          subjectId: 'dashboard.section:$id',
        ),
      );
    }
    for (final id in fromSections.difference(toSections)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactRemoved,
          category: HistoryChangeCategory.artifact,
          subjectId: 'dashboard.section:$id',
        ),
      );
    }

    if (fromSnap.metadata.freshness != toSnap.metadata.freshness) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.compatibility,
          subjectId: 'dashboard.freshness',
        ),
      );
    }

    final fromSources =
        fromSnap.sourceReferences.map((r) => r.artifactId).toSet();
    final toSources = toSnap.sourceReferences.map((r) => r.artifactId).toSet();
    if (fromSources != toSources) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'dashboard.sources',
        ),
      );
    }
  }

  void _compareTelemetry(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    final mapper = const TelemetryHistoryMapper();
    final fromSnap = TelemetrySnapshot.fromJson(from.payload.data);
    final toSnap = TelemetrySnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnap, toSnap));
  }

  void _compareQualityGate(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = QualityGateHistoryMapper();
    final fromSnap = QualityGateSnapshot.fromJson(from.payload.data);
    final toSnap = QualityGateSnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnap, toSnap));
  }

  void _compareReleaseGovernance(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = ReleaseGovernanceHistoryMapper();
    final fromSnap = ReleaseDecisionSnapshot.fromJson(from.payload.data);
    final toSnap = ReleaseDecisionSnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnap, toSnap));
  }

  void _compareReleaseEvidence(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = ReleaseEvidenceHistoryMapper();
    final fromBundle = ReleaseEvidenceBundle.fromJson(from.payload.data);
    final toBundle = ReleaseEvidenceBundle.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromBundle, toBundle));
  }

  void _compareReleaseSupplyChain(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = ReleaseSupplyChainHistoryMapper();
    final fromSnapshot = ReleaseSupplyChainSnapshot.fromJson(from.payload.data);
    final toSnapshot = ReleaseSupplyChainSnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnapshot, toSnapshot));
  }

  void _compareCicdIntegration(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = CicdIntegrationHistoryMapper();
    final fromSnapshot = CicdIntegrationSnapshot.fromJson(from.payload.data);
    final toSnapshot = CicdIntegrationSnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnapshot, toSnapshot));
  }

  void _compareCryptographicTrust(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = CryptographicTrustHistoryMapper();
    final fromSnapshot = CryptographicTrustSnapshot.fromJson(from.payload.data);
    final toSnapshot = CryptographicTrustSnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnapshot, toSnapshot));
  }

  void _comparePersistentArtifacts(
    HistoryArtifact from,
    HistoryArtifact to,
    List<HistoryChange> changes,
  ) {
    const mapper = PersistentArtifactHistoryMapper();
    final fromSnapshot =
        PersistentArtifactInfrastructureSnapshot.fromJson(from.payload.data);
    final toSnapshot =
        PersistentArtifactInfrastructureSnapshot.fromJson(to.payload.data);
    changes.addAll(mapper.compare(fromSnapshot, toSnapshot));
  }

  Set<String> _violationKeys(Map<String, dynamic> guardian) {
    final violations = guardian['violations'] as List<dynamic>? ?? [];
    return violations.whereType<Map>().map((v) {
      final code = v['code']?.toString() ?? '';
      final subject = _normalizePath(v['file']?.toString() ?? '');
      final context = v['message']?.toString() ?? '';
      return '$code|$subject|$context';
    }).toSet();
  }

  Set<String> _findingKeys(ReportSection section) {
    final keys = <String>{};
    for (final block in section.blocks) {
      if (block is FindingBlock) {
        keys.add(_findingIdentity(block.finding));
      }
    }
    return keys;
  }

  String _findingIdentity(ReportFinding finding) {
    return '${finding.code}|${finding.message}|${finding.severity.wireName}';
  }

  String _normalizePath(String path) => path.replaceAll('\\', '/');

  double? _numericValue(MetricRecord record) {
    final value = record.value;
    if (value is IntegerMetricValue) return value.value.toDouble();
    if (value is DecimalMetricValue) return value.value;
    if (value is PercentageMetricValue) return value.value;
    return null;
  }

  Map<HistoryArtifactType, HistoryArtifact> _indexByType(
    List<HistoryArtifact> artifacts,
  ) {
    return {for (final a in artifacts) a.artifactType: a};
  }

  HistoryDiffSummary _summarize(List<HistoryChange> changes) {
    var added = 0;
    var removed = 0;
    var changed = 0;
    var unchanged = 0;
    for (final change in changes) {
      switch (change.changeType) {
        case HistoryChangeType.artifactAdded:
        case HistoryChangeType.metricAdded:
        case HistoryChangeType.graphNodeAdded:
        case HistoryChangeType.graphEdgeAdded:
        case HistoryChangeType.reportSectionAdded:
        case HistoryChangeType.guardianViolationAdded:
          added++;
        case HistoryChangeType.artifactRemoved:
        case HistoryChangeType.metricRemoved:
        case HistoryChangeType.graphNodeRemoved:
        case HistoryChangeType.graphEdgeRemoved:
        case HistoryChangeType.reportSectionRemoved:
        case HistoryChangeType.guardianViolationRemoved:
          removed++;
        case HistoryChangeType.artifactUnchanged:
          unchanged++;
        default:
          changed++;
      }
    }
    return HistoryDiffSummary(
      totalChanges: changes.length,
      addedCount: added,
      removedCount: removed,
      changedCount: changed,
      unchangedCount: unchanged,
    );
  }
}
