import 'dart:convert';

import '../../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_change_type.dart';
import '../../models/history/history_diff.dart';
import '../history_canonical_serializer.dart';

/// Maps [CryptographicTrustSnapshot] to history artifacts and comparable fields.
///
/// History remains responsible for diff; this mapper does not execute evaluation.
class CryptographicTrustHistoryMapper {
  const CryptographicTrustHistoryMapper(
      {HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = CryptographicTrustSnapshot.fromJson(json);
    final comparable = snapshot.toComparableJson();
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );

    return HistoryArtifact(
      artifactType: HistoryArtifactType.cryptographicTrust,
      artifactId: snapshot.metadata.cryptographicTrustSnapshotId,
      schemaVersion: snapshot.metadata.schemaVersion,
      canonicalizationVersion: snapshot.metadata.canonicalizationVersion,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }

  List<HistoryChange> compare(
    CryptographicTrustSnapshot? from,
    CryptographicTrustSnapshot? to,
  ) {
    if (from == null || to == null) return const [];

    final changes = <HistoryChange>[];
    final fromMeta = from.metadata;
    final toMeta = to.metadata;

    if (fromMeta.releaseId != toMeta.releaseId) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'releaseContext',
          previousValue: fromMeta.releaseId,
          currentValue: toMeta.releaseId,
        ),
      );
    }

    if (from.status != to.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'snapshotStatus',
          previousValue: from.status.wireName,
          currentValue: to.status.wireName,
        ),
      );
    }

    if (from.signatures.length != to.signatures.length) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'signatureCount',
          previousValue: from.signatures.length.toString(),
          currentValue: to.signatures.length.toString(),
        ),
      );
    }

    if (from.attestations.length != to.attestations.length) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'attestationCount',
          previousValue: from.attestations.length.toString(),
          currentValue: to.attestations.length.toString(),
        ),
      );
    }

    if (from.trustChains.length != to.trustChains.length) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'trustChainCount',
          previousValue: from.trustChains.length.toString(),
          currentValue: to.trustChains.length.toString(),
        ),
      );
    }

    _diffIds(
      from.trustPolicies.map((p) => '${p.policyId}@${p.version}').toList(),
      to.trustPolicies.map((p) => '${p.policyId}@${p.version}').toList(),
      'trustPolicy',
      changes,
    );

    _diffVerificationStatus(from, to, changes);

    _diffIds(
      from.sourceReferences.map((r) => r.sourceId).toList(),
      to.sourceReferences.map((r) => r.sourceId).toList(),
      'sourceReference',
      changes,
    );

    if (fromMeta.fingerprint != toMeta.fingerprint) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'fingerprint',
          previousValue: fromMeta.fingerprint,
          currentValue: toMeta.fingerprint,
        ),
      );
    }

    return changes;
  }

  void _diffVerificationStatus(
    CryptographicTrustSnapshot from,
    CryptographicTrustSnapshot to,
    List<HistoryChange> changes,
  ) {
    final fromById = {
      for (final v in from.verificationResults) v.verificationId: v.status,
    };
    final toById = {
      for (final v in to.verificationResults) v.verificationId: v.status,
    };
    final allIds = {...fromById.keys, ...toById.keys}.toList()..sort();

    for (final id in allIds) {
      final fromStatus = fromById[id]?.wireName;
      final toStatus = toById[id]?.wireName;
      if (fromStatus != toStatus) {
        changes.add(
          HistoryChange(
            changeType: HistoryChangeType.artifactChanged,
            category: HistoryChangeCategory.artifact,
            subjectId: 'verificationStatus:$id',
            previousValue: fromStatus,
            currentValue: toStatus,
          ),
        );
      }
    }
  }

  void _diffIds(
    List<String> fromIds,
    List<String> toIds,
    String subject,
    List<HistoryChange> changes,
  ) {
    final fromSet = fromIds.toSet();
    final toSet = toIds.toSet();

    for (final added in toSet.difference(fromSet)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactAdded,
          category: HistoryChangeCategory.artifact,
          subjectId: '$subject:$added',
        ),
      );
    }

    for (final removed in fromSet.difference(toSet)) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactRemoved,
          category: HistoryChangeCategory.artifact,
          subjectId: '$subject:$removed',
        ),
      );
    }
  }
}
