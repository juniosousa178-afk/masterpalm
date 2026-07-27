import '../models/release_supply_chain/artifact_registry_models.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_fingerprint.dart';
import 'release_supply_chain_collector.dart';
import 'resolved_release_supply_chain_sources.dart';

/// Builds artifact registry records from collected supply chain artifacts.
class ArtifactRegistryBuilder {
  const ArtifactRegistryBuilder();

  List<ArtifactRecord> build({
    required ReleaseSupplyChainEvaluationContext context,
    required ReleaseSupplyChainCollectedArtifacts collected,
    required String evaluatedAt,
    String? provenanceRecordId,
  }) {
    final releaseContext = context.request.releaseContext;
    final records = <ArtifactRecord>[];
    final seen = <String>{};

    for (final artifact in collected.artifacts) {
      if (!seen.add(artifact.artifactId)) continue;
      if (artifact.artifactType == 'attestation' ||
          artifact.artifactType == 'provenance') {
        continue;
      }

      final location = ArtifactLocation(
        locationId: 'loc-${artifact.artifactId}',
        locationType: 'registry',
        uri: 'registry://artifacts/${artifact.artifactId}',
      );
      final integrity = ArtifactIntegrity(
        digest: ArtifactDigest(
          algorithm: ArtifactDigestAlgorithm.sha256,
          value: artifact.fingerprint ?? artifact.artifactId,
        ),
        verified: artifact.fingerprint != null,
      );
      final comparable = {
        'metadata': {
          'projectId': releaseContext.projectId,
          'releaseId': releaseContext.releaseId,
          'status': ArtifactStatus.available.wireName,
          'schemaVersion': ArtifactMetadata.currentSchemaVersion,
        },
        'identifier': ArtifactIdentifier(
          artifactId: artifact.artifactId,
          name: artifact.artifactType,
          version: '1.0.0',
        ).toComparableJson(),
        'location': location.toComparableJson(),
        'integrity': integrity.toComparableJson(),
      };
      final fingerprint =
          ReleaseSupplyChainFingerprint.fromComparableJson(comparable);

      records.add(
        ArtifactRecord(
          metadata: ArtifactMetadata(
            recordId: 'artifact-record-${artifact.artifactId}',
            projectId: releaseContext.projectId,
            releaseId: releaseContext.releaseId,
            commitId: releaseContext.commitId,
            schemaVersion: ArtifactMetadata.currentSchemaVersion,
            createdAt: evaluatedAt,
            registeredAt: evaluatedAt,
            status: ArtifactStatus.available,
            fingerprint: fingerprint,
            mediaType: 'application/octet-stream',
          ),
          identifier: ArtifactIdentifier(
            artifactId: artifact.artifactId,
            name: artifact.artifactType,
            version: '1.0.0',
          ),
          location: ArtifactLocation(
            locationId: 'loc-${artifact.artifactId}',
            locationType: 'registry',
            uri: 'registry://artifacts/${artifact.artifactId}',
          ),
          integrity: integrity,
          provenanceRecordId: provenanceRecordId,
        ),
      );
    }

    records.sort(
      (a, b) => a.metadata.recordId.compareTo(b.metadata.recordId),
    );
    return records;
  }
}
