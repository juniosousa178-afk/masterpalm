import '../models/history/history_artifact_type.dart';
import '../models/history/history_metadata.dart';
import '../models/history/history_request.dart';
import '../models/history/history_snapshot.dart';
import '../models/history/history_snapshot_status.dart';
import 'history_artifact_factory.dart';
import 'history_canonical_serializer.dart';
import 'history_compatibility_checker.dart';
import 'history_exceptions.dart';
import 'history_snapshot_id_factory.dart';
import 'history_validator.dart';

/// Stateless engine that builds validated history snapshots.
class HistoryEngine {
  HistoryEngine({
    HistoryArtifactFactory? artifactFactory,
    HistoryCanonicalSerializer? serializer,
    HistorySnapshotIdFactory? idFactory,
    HistoryValidator? validator,
    HistoryCompatibilityChecker? compatibilityChecker,
  })  : _artifactFactory = artifactFactory ?? HistoryArtifactFactory(),
        _serializer = serializer ?? const HistoryCanonicalSerializer(),
        _idFactory = idFactory ?? const HistorySnapshotIdFactory(),
        _validator = validator ?? const HistoryValidator(),
        _compatibilityChecker =
            compatibilityChecker ?? const HistoryCompatibilityChecker();

  final HistoryArtifactFactory _artifactFactory;
  final HistoryCanonicalSerializer _serializer;
  final HistorySnapshotIdFactory _idFactory;
  final HistoryValidator _validator;
  final HistoryCompatibilityChecker _compatibilityChecker;

  HistoryResult capture(HistoryRequest request) {
    if (request.projectId.isEmpty) {
      throw HistoryValidationException('projectId is required');
    }
    if (request.createdAt.isEmpty) {
      throw HistoryValidationException('createdAt is required');
    }

    final artifacts = _artifactFactory.buildFromRequest(request);
    if (artifacts.isEmpty) {
      throw HistoryValidationException('at least one artifact is required');
    }

    final presentTypes = artifacts.map((a) => a.artifactType).toSet();
    final missingArtifacts = <HistoryArtifactType>[];
    if (request.artifactSelection != null) {
      missingArtifacts.addAll(
        request.artifactSelection!.difference(presentTypes).toList(),
      );
      missingArtifacts.sort((a, b) => a.wireName.compareTo(b.wireName));
    }

    final warnings = <String>[];
    if (missingArtifacts.isNotEmpty) {
      warnings.add(
        'Missing artifacts: ${missingArtifacts.map((t) => t.wireName).join(', ')}',
      );
    }
    if (request.requireComplete && missingArtifacts.isNotEmpty) {
      throw HistoryValidationException(
        'complete snapshot required but artifacts are missing',
      );
    }

    final status = missingArtifacts.isEmpty
        ? HistorySnapshotStatus.complete
        : HistorySnapshotStatus.partial;

    final fingerprint =
        _serializer.snapshotFingerprint(artifacts, request.projectId);
    final snapshotId = _idFactory.create(
      projectId: request.projectId,
      snapshotFingerprint: fingerprint,
    );

    final artifactTypes = artifacts.map((a) => a.artifactType).toList()
      ..sort((a, b) => a.wireName.compareTo(b.wireName));

    final artifactCompatibilities =
        artifacts.map(_compatibilityChecker.forArtifact).toList();
    final compatibility = _compatibilityChecker.merge(artifactCompatibilities);

    final metadata = HistoryMetadata(
      historySnapshotId: snapshotId,
      historySchemaVersion: HistoryMetadata.currentSchemaVersion,
      historyCanonicalizationVersion:
          HistoryMetadata.currentCanonicalizationVersion,
      projectId: request.projectId,
      createdAt: request.createdAt,
      snapshotFingerprint: fingerprint,
      artifactCount: artifacts.length,
      artifactTypes: artifactTypes,
      status: status,
      gitRef: request.gitRef,
      branch: request.branch,
      sourceEventId: request.sourceEventId,
      missingArtifacts: missingArtifacts,
      warnings: warnings,
      tags: List<String>.from(request.tags),
      extra: Map<String, String>.from(request.metadata),
      compatibility: compatibility,
    );

    final snapshot = HistorySnapshot(metadata: metadata, artifacts: artifacts);
    final validation = _validator.validate(snapshot);
    if (!validation.isValid) {
      throw HistoryValidationException(validation.errors.join('; '));
    }

    return HistoryResult(
      status: status,
      snapshot: snapshot,
      warnings: warnings,
    );
  }
}
