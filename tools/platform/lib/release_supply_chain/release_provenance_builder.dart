import '../models/release_supply_chain/release_provenance_models.dart';
import '../models/release_supply_chain/release_provenance_record.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_fingerprint.dart';
import 'release_supply_chain_collector.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Builds [ReleaseProvenanceRecord] from collected supply chain artifacts.
class ReleaseProvenanceBuilder {
  const ReleaseProvenanceBuilder();

  ReleaseProvenanceRecord? build({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    required String evaluatedAt,
  }) {
    final releaseContext = context.request.releaseContext;
    final bundle = collected.releaseEvidenceBundle;
    final qg = collected.qualityGateSnapshot;
    final rg = collected.releaseDecisionSnapshot;

    if (bundle == null && qg == null && rg == null) {
      return null;
    }

    final artifacts = <ReleaseProvenanceArtifact>[];
    if (qg != null) {
      artifacts.add(
        ReleaseProvenanceArtifact(
          artifactId: 'art-qg-${qg.metadata.qualityGateSnapshotId}',
          artifactType: ReleaseProvenanceArtifactType.qualityGateSnapshot,
          fingerprint: qg.metadata.qualityGateFingerprint,
          snapshotId: qg.metadata.qualityGateSnapshotId,
        ),
      );
    }
    if (rg != null) {
      artifacts.add(
        ReleaseProvenanceArtifact(
          artifactId: 'art-rg-${rg.metadata.snapshotId}',
          artifactType: ReleaseProvenanceArtifactType.releaseDecisionSnapshot,
          fingerprint: rg.fingerprint,
          snapshotId: rg.metadata.snapshotId,
        ),
      );
    }
    if (bundle != null) {
      artifacts.add(
        ReleaseProvenanceArtifact(
          artifactId: 'art-re-${bundle.metadata.bundleId}',
          artifactType: ReleaseProvenanceArtifactType.releaseEvidenceBundle,
          fingerprint: bundle.fingerprint,
          snapshotId: bundle.metadata.bundleId,
        ),
      );
    }

    final relations = <ReleaseProvenanceRelation>[];
    if (qg != null && rg != null) {
      relations.add(
        ReleaseProvenanceRelation(
          relationId: 'rel-qg-rg',
          relationType: ReleaseProvenanceRelationType.derivedFrom,
          fromArtifactId: 'art-qg-${qg.metadata.qualityGateSnapshotId}',
          toArtifactId: 'art-rg-${rg.metadata.snapshotId}',
        ),
      );
    }
    if (rg != null && bundle != null) {
      relations.add(
        ReleaseProvenanceRelation(
          relationId: 'rel-rg-re',
          relationType: ReleaseProvenanceRelationType.derivedFrom,
          fromArtifactId: 'art-rg-${rg.metadata.snapshotId}',
          toArtifactId: 'art-re-${bundle.metadata.bundleId}',
        ),
      );
    }

    final subject = ReleaseProvenanceSubject(
      subjectId: 'prov-subject-${releaseContext.releaseId}',
      subjectType: ReleaseProvenanceSubjectType.release,
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      commitId: releaseContext.commitId,
    );

    final identity = ReleaseProvenanceIdentity(
      identityId: 'prov-identity-${releaseContext.releaseId}',
      subjectType: ReleaseProvenanceSubjectType.release,
      projectId: releaseContext.projectId,
      releaseId: releaseContext.releaseId,
      commitId: releaseContext.commitId,
      bundleId: bundle?.metadata.bundleId,
    );

    final comparable = {
      'metadata': {
        'projectId': releaseContext.projectId,
        'releaseId': releaseContext.releaseId,
        'commitId': releaseContext.commitId,
        if (bundle != null) 'releaseEvidenceBundleId': bundle.metadata.bundleId,
        if (qg != null)
          'qualityGateSnapshotId': qg.metadata.qualityGateSnapshotId,
        if (rg != null) 'releaseDecisionSnapshotId': rg.metadata.snapshotId,
        'schemaVersion': ReleaseProvenanceMetadata.currentSchemaVersion,
        'canonicalizationVersion':
            ReleaseProvenanceMetadata.currentCanonicalizationVersion,
        'status': ReleaseProvenanceStatus.complete.wireName,
        'artifactCount': artifacts.length,
        'relationCount': relations.length,
      },
      'subject': subject.toComparableJson(),
      'identity': identity.toComparableJson(),
    };

    final fingerprint =
        ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

    return ReleaseProvenanceRecord(
      metadata: ReleaseProvenanceMetadata(
        provenanceRecordId: 'prov-record-${releaseContext.releaseId}',
        projectId: releaseContext.projectId,
        releaseId: releaseContext.releaseId,
        commitId: releaseContext.commitId,
        releaseEvidenceBundleId: bundle?.metadata.bundleId,
        qualityGateSnapshotId: qg?.metadata.qualityGateSnapshotId,
        releaseDecisionSnapshotId: rg?.metadata.snapshotId,
        schemaVersion: ReleaseProvenanceMetadata.currentSchemaVersion,
        canonicalizationVersion:
            ReleaseProvenanceMetadata.currentCanonicalizationVersion,
        createdAt: evaluatedAt,
        recordedAt: evaluatedAt,
        status: ReleaseProvenanceStatus.complete,
        fingerprint: fingerprint,
        artifactCount: artifacts.length,
        relationCount: relations.length,
      ),
      subject: subject,
      identity: identity,
      fingerprintDescriptor: ReleaseProvenanceFingerprint(
        algorithm: ReleaseProvenanceFingerprint.defaultAlgorithm,
        value: fingerprint,
      ),
      artifacts: artifacts,
      relations: relations,
    );
  }
}
