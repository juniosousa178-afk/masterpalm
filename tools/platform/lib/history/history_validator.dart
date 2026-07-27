import 'dart:convert';

import '../models/history/history_artifact.dart';
import '../models/history/history_artifact_type.dart';
import '../models/history/history_snapshot.dart';
import '../models/history/history_snapshot_status.dart';
import '../models/history/history_validation_result.dart';
import 'history_canonical_serializer.dart';
import 'history_snapshot_id_factory.dart';

/// Validates structural integrity of history snapshots.
class HistoryValidator {
  const HistoryValidator({
    HistoryCanonicalSerializer? serializer,
    HistorySnapshotIdFactory? idFactory,
  })  : _serializer = serializer ?? const HistoryCanonicalSerializer(),
        _idFactory = idFactory ?? const HistorySnapshotIdFactory();

  final HistoryCanonicalSerializer _serializer;
  final HistorySnapshotIdFactory _idFactory;

  HistoryValidationResult validate(HistorySnapshot snapshot) {
    final errors = <String>[];
    final warnings = <String>[];
    var validArtifactCount = 0;
    var invalidArtifactCount = 0;

    final meta = snapshot.metadata;
    if (meta.historySnapshotId.isEmpty) {
      errors.add('historySnapshotId is empty');
    }
    if (meta.projectId.isEmpty) {
      errors.add('projectId is empty');
    }
    if (meta.historySchemaVersion <= 0) {
      errors.add('historySchemaVersion is missing or invalid');
    }
    if (meta.historyCanonicalizationVersion <= 0) {
      errors.add('historyCanonicalizationVersion is missing or invalid');
    }
    if (meta.snapshotFingerprint.isEmpty) {
      errors.add('snapshotFingerprint is empty');
    }
    if (meta.createdAt.isEmpty) {
      errors.add('createdAt is empty');
    }
    if (snapshot.artifacts.isEmpty) {
      errors.add('snapshot has no artifacts');
    }
    if (meta.artifactCount != snapshot.artifacts.length) {
      errors.add(
        'artifactCount ${meta.artifactCount} does not match artifacts length ${snapshot.artifacts.length}',
      );
    }

    final artifactTypes = snapshot.artifacts.map((a) => a.artifactType).toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    final metaTypes = List<HistoryArtifactType>.from(meta.artifactTypes)
      ..sort((a, b) => a.wireName.compareTo(b.wireName));
    if (!_listsEqual(artifactTypes, metaTypes)) {
      errors.add('artifactTypes metadata diverges from artifacts');
    }

    if (meta.status == HistorySnapshotStatus.partial &&
        meta.missingArtifacts.isEmpty) {
      errors.add('partial snapshot without missingArtifacts');
    }
    if (meta.status == HistorySnapshotStatus.complete &&
        meta.missingArtifacts.isNotEmpty) {
      errors.add('complete snapshot declares missingArtifacts');
    }

    final seenIds = <String>{};
    for (final artifact in snapshot.artifacts) {
      final artifactErrors = _validateArtifact(artifact);
      if (artifactErrors.isEmpty) {
        validArtifactCount++;
      } else {
        invalidArtifactCount++;
        errors.addAll(artifactErrors);
      }
      final key = '${artifact.artifactType.wireName}:${artifact.artifactId}';
      if (!seenIds.add(key)) {
        errors.add('duplicate artifact: $key');
      }
    }

    final expectedFingerprint = _serializer.snapshotFingerprint(
      snapshot.artifacts,
      meta.projectId,
    );
    if (meta.snapshotFingerprint != expectedFingerprint) {
      errors.add('snapshotFingerprint does not match computed fingerprint');
    }

    final expectedId = _idFactory.create(
      projectId: meta.projectId,
      snapshotFingerprint: expectedFingerprint,
      schemaVersion: meta.historySchemaVersion,
    );
    if (meta.historySnapshotId != expectedId) {
      errors.add('historySnapshotId does not match computed id');
    }

    if (!_isDeterministicOrder(snapshot.artifacts)) {
      errors.add('artifacts are not in deterministic order');
    }

    if (meta.status == HistorySnapshotStatus.invalid) {
      warnings.add('snapshot marked as invalid');
    }

    return HistoryValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      artifactCount: snapshot.artifacts.length,
      validArtifactCount: validArtifactCount,
      invalidArtifactCount: invalidArtifactCount,
      compatibilityStatus: meta.compatibility.status,
    );
  }

  List<String> _validateArtifact(HistoryArtifact artifact) {
    final errors = <String>[];
    if (artifact.artifactId.isEmpty) {
      errors.add('artifactId is empty for ${artifact.artifactType.wireName}');
    }
    if (artifact.fingerprint.isEmpty) {
      errors.add('fingerprint is empty for ${artifact.artifactId}');
    }
    if (artifact.payload.data.isEmpty) {
      errors.add('payload is empty for ${artifact.artifactId}');
    }
    try {
      jsonEncode(artifact.toJson());
    } catch (e) {
      errors.add('payload not serializable for ${artifact.artifactId}');
    }
    return errors;
  }

  bool _isDeterministicOrder(List<HistoryArtifact> artifacts) {
    for (var i = 1; i < artifacts.length; i++) {
      final prev = artifacts[i - 1];
      final curr = artifacts[i];
      final typeCmp =
          prev.artifactType.wireName.compareTo(curr.artifactType.wireName);
      if (typeCmp > 0) return false;
      if (typeCmp == 0 && prev.artifactId.compareTo(curr.artifactId) > 0) {
        return false;
      }
    }
    return true;
  }

  bool _listsEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
