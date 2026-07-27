import '../models/quality_gate/quality_gate_snapshot.dart';
import '../models/release_evidence/release_evidence_bundle.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_governance/release_decision_snapshot.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Located artifact reference from resolved supply chain sources.
class ReleaseSupplyChainCollectedArtifact {
  const ReleaseSupplyChainCollectedArtifact({
    required this.artifactId,
    required this.artifactType,
    required this.sourceType,
    this.fingerprint,
    this.snapshotId,
    this.collectedAt,
  });

  final String artifactId;
  final String artifactType;
  final String sourceType;
  final String? fingerprint;
  final String? snapshotId;
  final String? collectedAt;
}

/// Collected artifacts located from resolved sources without rebuilding snapshots.
class ReleaseSupplyChainCollectedArtifacts {
  const ReleaseSupplyChainCollectedArtifacts({
    this.qualityGateSnapshot,
    this.releaseDecisionSnapshot,
    this.releaseEvidenceBundle,
    this.artifacts = const [],
  });

  final QualityGateSnapshot? qualityGateSnapshot;
  final ReleaseDecisionSnapshot? releaseDecisionSnapshot;
  final ReleaseEvidenceBundle? releaseEvidenceBundle;
  final List<ReleaseSupplyChainCollectedArtifact> artifacts;
}

/// Locates release supply chain artifacts from resolved sources.
class ReleaseSupplyChainCollector {
  const ReleaseSupplyChainCollector();

  ReleaseSupplyChainCollectedArtifacts collect(
    ReleaseSupplyChainEvaluationContext context,
  ) {
    final sources = context.sources;
    final referenceTime = context.request.referenceTime;
    final collected = <ReleaseSupplyChainCollectedArtifact>[];
    final seenArtifactIds = <String>{};

    void addArtifact(ReleaseSupplyChainCollectedArtifact artifact) {
      if (!seenArtifactIds.add(artifact.artifactId)) return;
      collected.add(artifact);
    }

    final qg = sources.qualityGateSnapshot.isAvailable
        ? sources.qualityGateSnapshot.resolvedArtifact
        : null;
    final rg = sources.releaseDecisionSnapshot.isAvailable
        ? sources.releaseDecisionSnapshot.resolvedArtifact
        : null;
    final bundle = sources.releaseEvidenceBundle.isAvailable
        ? sources.releaseEvidenceBundle.resolvedArtifact
        : null;

    if (qg != null) {
      addArtifact(
        ReleaseSupplyChainCollectedArtifact(
          artifactId: qg.metadata.qualityGateSnapshotId,
          artifactType: 'qualityGateSnapshot',
          sourceType: 'qualityGate',
          fingerprint: qg.metadata.qualityGateFingerprint,
          snapshotId: qg.metadata.qualityGateSnapshotId,
          collectedAt: referenceTime,
        ),
      );
    }

    if (rg != null) {
      addArtifact(
        ReleaseSupplyChainCollectedArtifact(
          artifactId: rg.metadata.snapshotId,
          artifactType: 'releaseDecisionSnapshot',
          sourceType: 'releaseGovernance',
          fingerprint: rg.fingerprint,
          snapshotId: rg.metadata.snapshotId,
          collectedAt: referenceTime,
        ),
      );
    }

    if (bundle != null) {
      addArtifact(
        ReleaseSupplyChainCollectedArtifact(
          artifactId: bundle.metadata.bundleId,
          artifactType: 'releaseEvidenceBundle',
          sourceType: 'releaseEvidence',
          fingerprint: bundle.fingerprint,
          snapshotId: bundle.metadata.bundleId,
          collectedAt: referenceTime,
        ),
      );

      for (final evidence in bundle.evidence) {
        addArtifact(
          ReleaseSupplyChainCollectedArtifact(
            artifactId: evidence.artifactReference.artifactId,
            artifactType: evidence.artifactReference.artifactType.wireName,
            sourceType: 'releaseEvidence',
            fingerprint: evidence.artifactReference.fingerprint,
            snapshotId: bundle.metadata.bundleId,
            collectedAt: referenceTime,
          ),
        );
      }

      for (final attestation in bundle.attestations) {
        addArtifact(
          ReleaseSupplyChainCollectedArtifact(
            artifactId: attestation.metadata.attestationId,
            artifactType: 'attestation',
            sourceType: 'releaseEvidence',
            fingerprint: attestation.fingerprint,
            snapshotId: bundle.metadata.bundleId,
            collectedAt: referenceTime,
          ),
        );
      }

      for (final provenance in bundle.provenance) {
        addArtifact(
          ReleaseSupplyChainCollectedArtifact(
            artifactId: provenance.provenanceId,
            artifactType: ReleaseEvidenceType.provenance.wireName,
            sourceType: 'releaseEvidence',
            fingerprint: provenance.fingerprint,
            snapshotId: bundle.metadata.bundleId,
            collectedAt: referenceTime,
          ),
        );
      }
    }

    collected.sort((a, b) => a.artifactId.compareTo(b.artifactId));

    return ReleaseSupplyChainCollectedArtifacts(
      qualityGateSnapshot: qg,
      releaseDecisionSnapshot: rg,
      releaseEvidenceBundle: bundle,
      artifacts: collected,
    );
  }
}
