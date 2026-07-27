import '../models/history/history_artifact.dart';
import '../models/history/history_artifact_type.dart';
import '../models/history/history_compatibility.dart';

/// Evaluates schema and algorithm compatibility between artifacts.
class HistoryCompatibilityChecker {
  const HistoryCompatibilityChecker();

  HistoryCompatibility betweenArtifacts(
    HistoryArtifact? from,
    HistoryArtifact? to,
  ) {
    if (from == null || to == null) {
      return const HistoryCompatibility(
        status: HistoryCompatibilityStatus.unknown,
        reasons: ['Artifact missing for comparison'],
      );
    }
    if (from.artifactType != to.artifactType) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.incompatible,
        reasons: [
          'Artifact type mismatch: ${from.artifactType.wireName} vs ${to.artifactType.wireName}',
        ],
      );
    }
    return betweenSameType(from, to);
  }

  HistoryCompatibility betweenSameType(
      HistoryArtifact from, HistoryArtifact to) {
    final reasons = <String>[];

    if (from.schemaVersion != to.schemaVersion) {
      reasons.add(
        'schemaVersion ${from.schemaVersion} vs ${to.schemaVersion}',
      );
    }
    if (from.canonicalizationVersion != to.canonicalizationVersion) {
      reasons.add(
        'canonicalizationVersion ${from.canonicalizationVersion} vs ${to.canonicalizationVersion}',
      );
    }
    if (from.calculationVersion != to.calculationVersion) {
      reasons.add(
        'calculationVersion ${from.calculationVersion} vs ${to.calculationVersion}',
      );
    }
    if (from.payloadEncoding != to.payloadEncoding) {
      reasons.add(
        'payloadEncoding ${from.payloadEncoding} vs ${to.payloadEncoding}',
      );
    }

    if (reasons.isEmpty) {
      return const HistoryCompatibility(
        status: HistoryCompatibilityStatus.compatible,
      );
    }

    final hasSchemaMismatch = from.schemaVersion != to.schemaVersion;
    final hasCalcMismatch = from.calculationVersion != to.calculationVersion;

    if (hasSchemaMismatch) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.incompatible,
        reasons: reasons,
      );
    }
    if (hasCalcMismatch) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.partiallyCompatible,
        reasons: reasons,
      );
    }

    return HistoryCompatibility(
      status: HistoryCompatibilityStatus.partiallyCompatible,
      reasons: reasons,
    );
  }

  HistoryCompatibility merge(Iterable<HistoryCompatibility> items) {
    final statuses = items.map((e) => e.status).toList();
    if (statuses.isEmpty) {
      return const HistoryCompatibility(
          status: HistoryCompatibilityStatus.unknown);
    }
    if (statuses.any((s) => s == HistoryCompatibilityStatus.incompatible)) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.incompatible,
        reasons: items.expand((e) => e.reasons).toList(),
      );
    }
    if (statuses
        .any((s) => s == HistoryCompatibilityStatus.partiallyCompatible)) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.partiallyCompatible,
        reasons: items.expand((e) => e.reasons).toList(),
      );
    }
    if (statuses.any((s) => s == HistoryCompatibilityStatus.unknown)) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.unknown,
        reasons: items.expand((e) => e.reasons).toList(),
      );
    }
    return const HistoryCompatibility(
        status: HistoryCompatibilityStatus.compatible);
  }

  HistoryCompatibility forArtifact(HistoryArtifact artifact) {
    if (artifact.fingerprint.isEmpty) {
      return const HistoryCompatibility(
        status: HistoryCompatibilityStatus.incompatible,
        reasons: ['Empty artifact fingerprint'],
      );
    }
    if (artifact.schemaVersion <= 0) {
      return HistoryCompatibility(
        status: HistoryCompatibilityStatus.unknown,
        reasons: [
          'Unknown schema version for ${artifact.artifactType.wireName}'
        ],
      );
    }
    return artifact.compatibility;
  }

  bool supportsComparison(HistoryCompatibility compatibility) {
    return compatibility.status == HistoryCompatibilityStatus.compatible ||
        compatibility.status == HistoryCompatibilityStatus.partiallyCompatible;
  }

  Set<HistoryArtifactType> allArtifactTypes() =>
      HistoryArtifactType.values.toSet();
}
