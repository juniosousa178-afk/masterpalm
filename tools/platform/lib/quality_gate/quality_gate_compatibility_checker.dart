import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_request.dart';
import 'quality_gate_canonical_serializer.dart';
import 'resolved_quality_gate_sources.dart';

/// Checks structural compatibility between policy, request and sources.
class QualityGateCompatibilityChecker {
  const QualityGateCompatibilityChecker({
    QualityGateCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final QualityGateCanonicalSerializer _serializer;

  QualityGateCompatibility check({
    required QualityGateRequest request,
    required QualityGatePolicy policy,
    required ResolvedQualityGateSources sources,
  }) {
    final checks = <String>[];
    final reasons = <String>[];
    final compatible = <QualityGateSourceType>[];
    final partiallyCompatible = <QualityGateSourceType>[];
    final incompatible = <QualityGateSourceType>[];
    final unknown = <QualityGateSourceType>[];

    if (policy.metadata.schemaVersion >
        QualityGatePolicy.currentSchemaVersion) {
      reasons.add('Unsupported policy schema version');
      checks.add('policy-schema-unsupported');
    }

    if (policy.metadata.status == QualityGatePolicyStatus.retired &&
        !request.historicalEvaluation) {
      reasons.add('Policy is retired');
      checks.add('policy-retired');
    }

    if (request.projectId.isEmpty) {
      reasons.add('Request projectId is required');
      checks.add('request-project-missing');
    }

    for (final ref in sources.sourceReferences) {
      switch (ref.compatibility) {
        case QualityGateCompatibilityStatus.compatible:
          compatible.add(ref.sourceType);
        case QualityGateCompatibilityStatus.partiallyCompatible:
          partiallyCompatible.add(ref.sourceType);
        case QualityGateCompatibilityStatus.incompatible:
          incompatible.add(ref.sourceType);
          reasons.add('Incompatible source ${ref.sourceType.wireName}');
        case QualityGateCompatibilityStatus.unknown:
          unknown.add(ref.sourceType);
      }
      if (ref.availability == QualityGateSourceAvailability.unavailable &&
          policy.requiredSourceTypes.contains(ref.sourceType)) {
        reasons.add('Required source unavailable: ${ref.sourceType.wireName}');
        checks.add('required-source-unavailable:${ref.sourceType.wireName}');
      }
      if (ref.fingerprint == null || ref.fingerprint!.isEmpty) {
        checks.add('missing-fingerprint:${ref.sourceType.wireName}');
      }
    }

    for (final hint in sources.compatibilityHints) {
      reasons.add(hint);
      checks.add('compatibility-hint');
    }

    if (request.strictCompatibility && incompatible.isNotEmpty) {
      return _result(
        status: QualityGateCompatibilityStatus.incompatible,
        checks: checks,
        compatible: compatible,
        partiallyCompatible: partiallyCompatible,
        incompatible: incompatible,
        unknown: unknown,
        reasons: reasons,
      );
    }

    final status = incompatible.isNotEmpty
        ? QualityGateCompatibilityStatus.incompatible
        : partiallyCompatible.isNotEmpty || unknown.isNotEmpty
            ? QualityGateCompatibilityStatus.partiallyCompatible
            : compatible.isNotEmpty
                ? QualityGateCompatibilityStatus.compatible
                : QualityGateCompatibilityStatus.unknown;

    return _result(
      status: status,
      checks: checks,
      compatible: compatible,
      partiallyCompatible: partiallyCompatible,
      incompatible: incompatible,
      unknown: unknown,
      reasons: reasons,
    );
  }

  QualityGateCompatibility _result({
    required QualityGateCompatibilityStatus status,
    required List<String> checks,
    required List<QualityGateSourceType> compatible,
    required List<QualityGateSourceType> partiallyCompatible,
    required List<QualityGateSourceType> incompatible,
    required List<QualityGateSourceType> unknown,
    required List<String> reasons,
  }) {
    final fingerprint = _serializer.fingerprintFromString(
      {
        'status': status.wireName,
        'checks': checks..sort(),
        'compatible': compatible.map((e) => e.wireName).toList()..sort(),
        'incompatible': incompatible.map((e) => e.wireName).toList()..sort(),
      }.toString(),
    );
    return QualityGateCompatibility(
      status: status,
      checks: checks..sort(),
      compatibleSources: compatible,
      partiallyCompatibleSources: partiallyCompatible,
      incompatibleSources: incompatible,
      unknownSources: unknown,
      reasons: reasons,
      compatibilityFingerprint: fingerprint,
    );
  }
}
